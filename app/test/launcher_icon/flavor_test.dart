import 'dart:io';

import 'package:flutterware_app/src/launcher_icon/model/role.dart';
import 'package:flutterware_app/src/launcher_icon/model/scan.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Which flavors a package has, and what each one turns out to own.
///
/// The three sources are deliberately exercised apart as well as together: the
/// bug this replaces was a discovery that knew only one of them, and a fixture
/// carrying all three at once would have passed against it.
void main() {
  late Directory root;

  String path(String relative) => p.join(root.path, relative);

  void write(String relative, String content) {
    var file = File(path(relative));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
  }

  void writePng(String relative, int size) {
    var file = File(path(relative));
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(img.encodePng(img.Image(width: size, height: size)));
  }

  /// The generator's config for one flavor. Never opened by the scan, so the
  /// contents only have to look like a config.
  void writeFlavorConfig(String flavor) => write(
    'flutter_launcher_icons-$flavor.yaml',
    'flutter_launcher_icons:\n  image_path: "assets/icon.png"\n',
  );

  /// What `createIcons` writes on iOS for [flavor] — one catalog set named
  /// after it, with the icon files named after it too.
  void writeIosCatalog({String? flavor, int size = 1024}) {
    var set = flavor == null ? 'AppIcon' : 'AppIcon-$flavor';
    var file = flavor == null
        ? 'Icon-App-1024x1024@1x.png'
        : '$set-1024x1024@1x.png';
    writePng('ios/Runner/Assets.xcassets/$set.appiconset/$file', size);
    write('ios/Runner/Assets.xcassets/$set.appiconset/Contents.json', '''
{"images":[{"size":"1024x1024","idiom":"ios-marketing","filename":"$file","scale":"1x"}],
 "info":{"version":1,"author":"xcode"}}
''');
  }

  IconScan scan({String? flavor}) =>
      scanIcons(packageRoot: root.path, packagePath: '.', flavor: flavor);

  IconFlavor named(String name) =>
      scan().flavors.firstWhere((f) => f.name == name);

  setUp(() => root = Directory.systemTemp.createTempSync('icon_flavor_test'));
  tearDown(() => root.deleteSync(recursive: true));

  group('discovery', () {
    test('a config alone is a flavor, generated or not', () {
      // The case the old source-set listing could not see at all: the project
      // has been set up and nobody has run the generator yet.
      writeFlavorConfig('dev');
      expect(named('dev').sources, {IconFlavorSource.config});
      expect(named('dev').isUnbuilt, isTrue);
    });

    test('an Android source set alone is a flavor', () {
      writePng('android/app/src/dev/res/mipmap-hdpi/ic_launcher.png', 72);
      expect(named('dev').sources, {IconFlavorSource.androidSourceSet});
      expect(named('dev').isUnbuilt, isFalse);
    });

    test('an iOS catalog alone is a flavor', () {
      // An iOS-only flavor was invisible twice over: nothing listed it, and
      // nothing would have read it if something had.
      writeIosCatalog(flavor: 'dev');
      expect(named('dev').sources, {IconFlavorSource.iosCatalog});
    });

    test('the three fold into one flavor carrying all of them', () {
      writeFlavorConfig('dev');
      writePng('android/app/src/dev/res/mipmap-hdpi/ic_launcher.png', 72);
      writeIosCatalog(flavor: 'dev');

      expect(scan().flavors, hasLength(1));
      expect(named('dev').sources, IconFlavorSource.values.toSet());
    });

    test('build types are not flavors, and the default set is not one', () {
      writePng('android/app/src/main/res/mipmap-hdpi/ic_launcher.png', 72);
      for (var reserved in ['debug', 'profile', 'release', 'androidTest']) {
        Directory(
          path('android/app/src/$reserved'),
        ).createSync(recursive: true);
      }
      expect(scan().flavors, isEmpty);
    });

    test('the stock AppIcon.appiconset is not a flavor called anything', () {
      writeIosCatalog();
      expect(scan().flavors, isEmpty);
    });

    test('they come back sorted, whatever order the disk gave them', () {
      for (var name in ['prod', 'dev', 'staging']) {
        writeFlavorConfig(name);
      }
      expect(scan().flavors.map((f) => f.name), ['dev', 'prod', 'staging']);
    });
  });

  group('what a flavor owns', () {
    test('the iOS icons are the flavor’s catalog', () {
      writeIosCatalog(size: 1024);
      writeIosCatalog(flavor: 'dev', size: 512);

      var files = scan(flavor: 'dev').forRole(IconRole.iosApp)!.files;
      expect(files, hasLength(1));
      expect(files.single.width, 512);
      expect(files.single.path, contains('AppIcon-dev.appiconset'));
    });

    test('the default is still the stock catalog, not the flavor’s', () {
      writeIosCatalog(size: 1024);
      writeIosCatalog(flavor: 'dev', size: 512);

      var files = scan().forRole(IconRole.iosApp)!.files;
      expect(files, hasLength(1));
      expect(files.single.width, 1024);
    });

    test('a flavor with no catalog of its own reports no iOS icons', () {
      // Not the default's. This is the failure the whole change is about: it
      // used to come back with production's marketing icon under a `dev` chip.
      writeIosCatalog(size: 1024);
      writePng('android/app/src/dev/res/mipmap-hdpi/ic_launcher.png', 72);

      var scanned = scan(flavor: 'dev');
      expect(scanned.forRole(IconRole.iosApp)!.files, isEmpty);
      expect(scanned.ios, IosCatalog.none);
      expect(scanned.forRole(IconRole.androidLegacy)!.files, hasLength(1));
    });

    test('dark and tinted come out of the flavor’s own set', () {
      // `createIcons` puts all three appearances inside one catalog and tells
      // them apart with `appearances`, so a flavor is one directory, not three.
      writePng(
        'ios/Runner/Assets.xcassets/AppIcon-dev.appiconset/AppIcon-dev-1024x1024@1x.png',
        1024,
      );
      writePng(
        'ios/Runner/Assets.xcassets/AppIcon-dev.appiconset/AppIcon-dev-Dark-1024x1024@1x.png',
        1024,
      );
      write(
        'ios/Runner/Assets.xcassets/AppIcon-dev.appiconset/Contents.json',
        '''
{"images":[
  {"size":"1024x1024","idiom":"ios-marketing","filename":"AppIcon-dev-1024x1024@1x.png","scale":"1x"},
  {"size":"1024x1024","idiom":"ios-marketing","filename":"AppIcon-dev-Dark-1024x1024@1x.png","scale":"1x",
   "appearances":[{"appearance":"luminosity","value":"dark"}]}
],"info":{"version":1,"author":"xcode"}}
''',
      );

      var scanned = scan(flavor: 'dev');
      expect(scanned.forRole(IconRole.iosApp)!.files, hasLength(1));
      expect(scanned.forRole(IconRole.iosDark)!.files, hasLength(1));
    });

    test(
      'macOS, web and Windows ignore the flavor, because the generator does',
      () {
        // `createIconsFromConfig` hands the flavor to Android and iOS only; the
        // other three take none and write to the one fixed place. A flavored scan
        // that hid them would be describing a project that does not exist.
        writePng('android/app/src/dev/res/mipmap-hdpi/ic_launcher.png', 72);
        writePng('web/icons/Icon-192.png', 192);
        writePng('windows/runner/resources/app_icon.ico', 0);
        writePng(
          'macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_512.png',
          512,
        );
        write(
          'macos/Runner/Assets.xcassets/AppIcon.appiconset/Contents.json',
          '{"images":[{"size":"512x512","idiom":"mac","filename":"app_icon_512.png","scale":"1x"}]}',
        );

        var scanned = scan(flavor: 'dev');
        expect(scanned.forRole(IconRole.webIcon)!.files, isNotEmpty);
        expect(scanned.forRole(IconRole.macosApp)!.files, isNotEmpty);
      },
    );
  });
}
