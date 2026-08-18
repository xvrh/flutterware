import 'dart:io';

import 'package:flutterware_app/src/splash/model/generated.dart';
import 'package:flutterware_app/src/splash/model/surface.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Finding the files `create` wrote, when a flavor moved them.
///
/// The iOS names here are the generator's own, out of `flavor_helper.dart`:
/// only the *folder* takes the flavor, and the files inside keep the names they
/// have without one. A fixture that suffixed the files too would pass against a
/// reader that suffixed nothing.
void main() {
  late Directory root;

  void writePng(String relative, int size) {
    var file = File(p.join(root.path, relative));
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(img.encodePng(img.Image(width: size, height: size)));
  }

  /// One iOS run's output, whole: the background is what marks it as generated.
  void writeIos({String suffix = '', int image = 200}) {
    writePng(
      'ios/Runner/Assets.xcassets/LaunchBackground$suffix.imageset/background.png',
      1,
    );
    writePng(
      'ios/Runner/Assets.xcassets/LaunchImage$suffix.imageset/LaunchImage@2x.png',
      image,
    );
  }

  List<SplashArtifact> ios(List<SplashArtifact> all) =>
      all.where((a) => a.surface == SplashSurface.ios).toList();

  setUp(() => root = Directory.systemTemp.createTempSync('splash_artifacts'));
  tearDown(() => root.deleteSync(recursive: true));

  group('the iOS asset catalog under a flavor', () {
    test('is the flavor’s own imagesets', () {
      writeIos(suffix: 'Dev', image: 999);
      var found = ios(findSplashArtifacts(root.path, flavor: 'dev'));

      expect(
        found.map((a) => a.path),
        containsAll([
          p.join(
            'ios',
            'Runner',
            'Assets.xcassets',
            'LaunchImageDev.imageset',
            'LaunchImage@2x.png',
          ),
        ]),
      );
      expect(found.firstWhere((a) => a.pixelWidth == 999), isNotNull);
    });

    test('is not the default’s when only the default was generated', () {
      // The failure this replaces was silent: the stock names are always there
      // on a project that has generated once, so a flavor nobody had run came
      // back looking generated, with production's splash in it.
      writeIos();
      expect(ios(findSplashArtifacts(root.path, flavor: 'dev')), isEmpty);
    });

    test('leaves the default reading the unsuffixed names', () {
      writeIos(image: 200);
      var found = ios(findSplashArtifacts(root.path));
      expect(found, isNotEmpty);
      expect(found.every((a) => !a.path.contains('Dev')), isTrue);
    });

    test('a flavor and the default do not see each other', () {
      writeIos(image: 200);
      writeIos(suffix: 'Dev', image: 999);

      expect(
        ios(findSplashArtifacts(root.path)).map((a) => a.pixelWidth),
        isNot(contains(999)),
      );
      expect(
        ios(
          findSplashArtifacts(root.path, flavor: 'dev'),
        ).map((a) => a.pixelWidth),
        isNot(contains(200)),
      );
    });

    test('the dark file is still dark inside a flavored set', () {
      writeIos(suffix: 'Dev');
      writePng(
        'ios/Runner/Assets.xcassets/LaunchImageDev.imageset/LaunchImageDark@2x.png',
        200,
      );
      expect(
        ios(
          findSplashArtifacts(root.path, flavor: 'dev'),
        ).where((a) => a.theme == SplashTheme.dark),
        hasLength(1),
      );
    });
  });

  group('the flavor’s iOS spelling', () {
    // `_FlavorHelper` capitalises with the package's own extension, which
    // lower-cases everything after the first character. Matching it exactly is
    // the whole reason this is computed rather than read off disk.
    test('upper-cases the first character and lower-cases the rest', () {
      expect(iosFlavorName('dev'), 'Dev');
      expect(iosFlavorName('devQA'), 'Devqa');
      expect(iosFlavorName('PROD'), 'Prod');
    });

    test('is empty for no flavor at all', () {
      expect(iosFlavorName(null), '');
      expect(iosFlavorName(''), '');
    });

    test('is what the reader actually uses', () {
      // `devQA` is the case that proves the transform is applied rather than
      // the flavor pasted on: the folder is `Devqa`, which no straight
      // concatenation produces.
      writeIos(suffix: 'Devqa', image: 999);
      expect(ios(findSplashArtifacts(root.path, flavor: 'devQA')), isNotEmpty);
    });
  });

  test('android still moves with the flavor, and iOS with it', () {
    writePng('android/app/src/dev/res/drawable-hdpi/splash.png', 100);
    writePng('android/app/src/dev/res/drawable/background.png', 1);
    writeIos(suffix: 'Dev', image: 999);

    var found = findSplashArtifacts(root.path, flavor: 'dev');
    expect(
      found.map((a) => a.surface).toSet(),
      containsAll([SplashSurface.android, SplashSurface.ios]),
    );
    expect(found.every((a) => !a.path.contains('src/main')), isTrue);
  });
}
