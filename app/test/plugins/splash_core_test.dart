import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware/plugins.dart';
// ignore: implementation_imports
import 'package:flutterware/src/log_client.dart';
import 'package:flutterware_app/src/context.dart';
import 'package:flutterware_app/src/plugins/native/splash_core.dart';
import 'package:flutterware_app/src/plugins/native/splash_results.dart';
import 'package:flutterware_app/src/plugins/plugin_host.dart';
import 'package:flutterware_app/src/shell/workspace.dart';
import 'package:flutterware_app/src/shell/worktree.dart';
import 'package:flutterware_app/src/splash/model/surface.dart';
import 'package:flutterware_app/src/utils/flutter_sdk.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

/// Everything asserted here is read through [PluginReport] or an action result —
/// the same data the sidebar, `fw` and an agent see. A fact that only reaches
/// the panel is a fact the other two surfaces do not have.
void main() {
  late Directory root;

  SplashCore core({List<String> packages = const ['.']}) {
    var worktree = Worktree(path: root.path);
    return SplashCore(
      PluginHost(
        id: splashPluginId,
        label: 'Splash screen',
        worktree: worktree,
        workspace: Workspace(
          root: worktree.path,
          declared: [for (var path in packages) Pkg(path)],
          discovered: packages,
          appContext: AppContext(logger: LogClient.print()),
          flutterSdk: FlutterSdkPath('/tmp/flutter'),
        ),
        config: {
          'packages': [
            for (var path in packages) {'path': path},
          ],
        },
      ),
      // No timer: `checkForChanges` is driven by hand, which is steadier than
      // waiting on a clock and says the same thing.
      pollInterval: Duration.zero,
    );
  }

  void write(String relative, String content) {
    var file = File(p.join(root.path, relative));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
  }

  /// A real PNG of exactly [width]×[height], so the dimension rules are checked
  /// against something the generator itself could read.
  void writePng(String relative, int width, int height) {
    var file = File(p.join(root.path, relative));
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(
      img.encodePng(img.Image(width: width, height: height)),
    );
  }

  void writePubspec({bool withSplashDependency = true}) {
    write('pubspec.yaml', '''
name: sample
environment:
  sdk: ^3.0.0
dev_dependencies:
${withSplashDependency ? '  flutter_native_splash: ^2.4.0' : '  flutter_lints:'}
''');
  }

  /// Reads a config's problems the way a caller does — through `describe`.
  Future<List<SplashProblemEntry>> problems(
    SplashCore c, {
    String surface = 'android',
    String theme = 'light',
  }) async {
    var result =
        (await c.invoke(
              'describe',
              arguments: {'surface': surface, 'theme': theme},
            ))!
            as SplashDescribeResult;
    return result.problems;
  }

  setUp(() {
    root = Directory.systemTemp.createTempSync('splash_core_test');
    writePubspec();
  });

  tearDown(() => root.deleteSync(recursive: true));

  group('discovery', () {
    test('a project with no config says so rather than erroring', () async {
      var c = core();
      await c.computeAll();
      // The package row says it; the plugin row stays quiet.
      expect(c.report.status, Status.none);
      expect(
        c.report.children.single.status.message,
        contains('No splash configured'),
      );
      expect(c.report.badge.isEmpty, isTrue);
    });

    test('reads flutter_native_splash.yaml', () async {
      write('flutter_native_splash.yaml', '''
flutter_native_splash:
  color: "FFFFFF"
''');
      var c = core();
      await c.computeAll();
      expect(c.scanFor('.')!.main!.config.path, 'flutter_native_splash.yaml');
    });

    test(
      'reads the pubspec section when there is no standalone file',
      () async {
        write('pubspec.yaml', '''
name: sample
environment:
  sdk: ^3.0.0
dev_dependencies:
  flutter_native_splash: ^2.4.0
flutter_native_splash:
  color: "FFFFFF"
''');
        var c = core();
        await c.computeAll();
        expect(c.scanFor('.')!.main!.config.path, 'pubspec.yaml');
      },
    );

    test('the standalone file wins over the pubspec section', () async {
      write('pubspec.yaml', '''
name: sample
environment:
  sdk: ^3.0.0
flutter_native_splash:
  color: "000000"
''');
      write('flutter_native_splash.yaml', '''
flutter_native_splash:
  color: "FFFFFF"
''');
      var c = core();
      await c.computeAll();
      var config = c.scanFor('.')!.main!.config;
      expect(config.path, 'flutter_native_splash.yaml');
      expect(config.raw['color'], 'FFFFFF');
    });

    test(
      'a config file with no flutter_native_splash section is an error',
      () async {
        // The generator throws on this rather than reading the root keys, so a
        // file sitting there doing nothing has to be reported.
        write('flutter_native_splash.yaml', '''
color: "FFFFFF"
image: assets/logo.png
''');
        var c = core();
        await c.computeAll();
        expect(c.scanFor('.')!.configErrors, isNotEmpty);
        expect(c.report.status.tone, Tone.error);
        expect(
          c.report.children.single.status.message,
          contains('flutter_native_splash:'),
        );
      },
    );

    test(
      'flavor files are listed beside the default, not in front of it',
      () async {
        write('flutter_native_splash.yaml', '''
flutter_native_splash:
  color: "FFFFFF"
''');
        write('flutter_native_splash-production.yaml', '''
flutter_native_splash:
  color: "112233"
''');
        var c = core();
        await c.computeAll();
        var scan = c.scanFor('.')!;
        expect(scan.main!.config.flavor, isNull);
        expect(scan.flavors, ['production']);
      },
    );
  });

  group('validation', () {
    test('an unknown key stops generation', () async {
      write('flutter_native_splash.yaml', '''
flutter_native_splash:
  color: "FFFFFF"
  colour_dark: "000000"
''');
      var c = core();
      await c.computeAll();
      var found = await problems(c);
      var unknown = found.singleWhere((p) => p.key == 'colour_dark');
      expect(unknown.blocksGeneration, isTrue);
      expect(unknown.tone, 'error');
      // Counts live on the package row, not repeated on the plugin's own; the
      // plugin row carries only a badge.
      expect(c.report.status, Status.none);
      expect(c.report.children.single.status.message, contains('blocking'));
      expect(c.report.badge.tone, Tone.error);
    });

    test('a missing image stops generation', () async {
      write('flutter_native_splash.yaml', '''
flutter_native_splash:
  color: "FFFFFF"
  image: assets/nope.png
''');
      var c = core();
      await c.computeAll();
      var missing = (await problems(c)).singleWhere((p) => p.key == 'image');
      expect(missing.blocksGeneration, isTrue);
      expect(missing.message, contains('was not found'));
    });

    test('a colour that is not six hex digits stops generation', () async {
      write('flutter_native_splash.yaml', '''
flutter_native_splash:
  color: "FF00FF00"
''');
      var c = core();
      await c.computeAll();
      var bad = (await problems(c)).singleWhere((p) => p.key == 'color');
      expect(bad.blocksGeneration, isTrue);
    });

    test('a non-PNG image is a conversion note, not an error', () async {
      // The README reads like PNG is required; the generator accepts a dozen
      // formats and converts them.
      writePng('assets/logo.jpg', 100, 100);
      write('flutter_native_splash.yaml', '''
flutter_native_splash:
  color: "FFFFFF"
  image: assets/logo.jpg
''');
      var c = core();
      await c.computeAll();
      var note = (await problems(c)).singleWhere((p) => p.key == 'image');
      expect(note.tone, 'info');
      expect(note.blocksGeneration, isFalse);
    });

    test(
      'legacy art with no android_12 section warns about the launcher icon',
      () async {
        // Not "a bare colour", which is what this said until it was checked
        // against the generator: with no `android_12.image` it writes no
        // `windowSplashScreenAnimatedIcon`, and Android's default for that
        // attribute is the app icon.
        writePng('assets/logo.png', 1024, 1024);
        write('flutter_native_splash.yaml', '''
flutter_native_splash:
  color: "FFFFFF"
  image: assets/logo.png
''');
        var c = core();
        await c.computeAll();
        var found = await problems(c, surface: 'android12');
        var warning = found.singleWhere((p) => p.key == 'android_12.image');
        expect(warning.tone, 'warn');
        expect(warning.message, contains('launcher icon'));
        expect(warning.message, isNot(contains('bare colour')));
      },
    );

    test(
      'the android 12 cell draws the launcher icon it will really show',
      () async {
        // The picture has to be what a device produces, not an empty rectangle.
        writePng('assets/logo.png', 1024, 1024);
        writePng(
          'android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png',
          192,
          192,
        );
        write('flutter_native_splash.yaml', '''
flutter_native_splash:
  color: "FFFFFF"
  image: assets/logo.png
''');
        var c = core();
        await c.computeAll();

        var result =
            (await c.invoke('describe', arguments: {'surface': 'android12'}))!
                as SplashDescribeResult;
        expect(result.placement, contains('launcher icon'));
        expect(result.placement, contains('ic_launcher.png'));
      },
    );

    test(
      'a project with no mipmaps says nothing about a launcher icon',
      () async {
        writePng('assets/logo.png', 1024, 1024);
        write('flutter_native_splash.yaml', '''
flutter_native_splash:
  color: "FFFFFF"
  image: assets/logo.png
''');
        var c = core();
        await c.computeAll();

        var result =
            (await c.invoke('describe', arguments: {'surface': 'android12'}))!
                as SplashDescribeResult;
        expect(result.placement, contains('no image'));
      },
    );

    test(
      'an android_12 icon on the wrong canvas warns with both sizes',
      () async {
        writePng('assets/a12.png', 512, 512);
        write('flutter_native_splash.yaml', '''
flutter_native_splash:
  color: "FFFFFF"
  android_12:
    image: assets/a12.png
''');
        var c = core();
        await c.computeAll();
        var found = await problems(c, surface: 'android12');
        var warning = found.firstWhere((p) => p.message.contains('512×512'));
        expect(warning.message, contains('1152×1152'));
      },
    );

    test(
      'the expected canvas shrinks when an icon background is set',
      () async {
        writePng('assets/a12.png', 1152, 1152);
        write('flutter_native_splash.yaml', '''
flutter_native_splash:
  color: "FFFFFF"
  android_12:
    image: assets/a12.png
    icon_background_color: "AABBCC"
''');
        var c = core();
        await c.computeAll();
        var found = await problems(c, surface: 'android12');
        // 1152 is right without a background and wrong with one.
        expect(found.any((p) => p.message.contains('960×960')), isTrue);
      },
    );

    test('a correct android_12 icon raises nothing', () async {
      writePng('assets/a12.png', 1152, 1152);
      write('flutter_native_splash.yaml', '''
flutter_native_splash:
  color: "FFFFFF"
  android_12:
    image: assets/a12.png
''');
      var c = core();
      await c.computeAll();
      var found = await problems(c, surface: 'android12');
      expect(found.where((p) => p.tone == 'warn'), isEmpty);
    });

    test(
      'a bad android_gravity warns, since the generator silently ignores it',
      () async {
        write('flutter_native_splash.yaml', '''
flutter_native_splash:
  color: "FFFFFF"
  android_gravity: middle
''');
        var c = core();
        await c.computeAll();
        var found = await problems(c);
        expect(found.any((p) => p.key == 'android_gravity'), isTrue);
      },
    );

    test('a dark colour with no dark image draws the light logo', () async {
      // The common half-configured case, and the one this plugin got
      // **backwards** and shipped: it claimed `color_dark` alone produced a
      // dark splash with no logo on it, and warned about it. Every platform
      // resolves the missing dark resource to the light one, so what ships is
      // the light logo on the dark colour — usually the intent.
      //
      // The rule that narrated all this is gone with the rest of the
      // transcription. The picture says it, which is what a picture is for.
      writePng('assets/logo.png', 1024, 1024);
      write('flutter_native_splash.yaml', '''
flutter_native_splash:
  color: "FFFFFF"
  color_dark: "101418"
  image: assets/logo.png
''');
      var c = core();
      await c.computeAll();

      expect(await problems(c, theme: 'dark'), isEmpty);

      var dark = c
          .scanFor('.')!
          .main!
          .compositionFor(SplashSurface.android, SplashTheme.dark);
      expect(dark.image, isNotNull);
      expect(dark.image!.path, 'assets/logo.png');
      expect(dark.backgroundColor, 0xFF101418);
    });

    test('a cell with no dark config at all draws the light splash', () async {
      // The caption has always said "the OS shows the light splash". The
      // picture beside it was a **black rectangle**, because "the dark chain
      // resolved nothing" was modelled as "draw nothing" — so the tile
      // contradicted its own caption on the most common config there is.
      writePng('assets/logo.png', 1024, 1024);
      write('flutter_native_splash.yaml', '''
flutter_native_splash:
  color: "FFFFFF"
  image: assets/logo.png
''');
      var c = core();
      await c.computeAll();

      var dark = c
          .scanFor('.')!
          .main!
          .compositionFor(SplashSurface.android, SplashTheme.dark);
      expect(dark.backgroundColor, 0xFFFFFFFF);
      expect(dark.image!.path, 'assets/logo.png');
      // Still flagged as the fallback, which is what the caption reads.
      expect(dark.fallsBackToLight, isTrue);
    });

    test('a fully configured dark variant raises nothing', () async {
      writePng('assets/logo.png', 1024, 1024);
      writePng('assets/logo_dark.png', 1024, 1024);
      write('flutter_native_splash.yaml', '''
flutter_native_splash:
  color: "FFFFFF"
  color_dark: "101418"
  image: assets/logo.png
  image_dark: assets/logo_dark.png
''');
      var c = core();
      await c.computeAll();
      var found = await problems(c, surface: 'ios', theme: 'dark');
      expect(found.where((p) => p.key == 'image_dark'), isEmpty);
    });

    test('a missing dev_dependency is reported', () async {
      writePubspec(withSplashDependency: false);
      write('flutter_native_splash.yaml', '''
flutter_native_splash:
  color: "FFFFFF"
''');
      var c = core();
      await c.computeAll();
      var found = await problems(c);
      expect(found.any((p) => p.message.contains('dev_dependencies')), isTrue);
    });
  });

  group('describe', () {
    setUp(() {
      writePng('assets/logo.png', 1024, 1024);
      write('flutter_native_splash.yaml', '''
flutter_native_splash:
  color: "FFFFFF"
  color_dark: "101418"
  color_dark_android: "000000"
  image: assets/logo.png
''');
    });

    test('names the key each value came from', () async {
      var c = core();
      await c.computeAll();
      var result =
          (await c.invoke(
                'describe',
                arguments: {'surface': 'android', 'theme': 'dark'},
              ))!
              as SplashDescribeResult;

      var color = result.properties.singleWhere((p) => p.name == 'color');
      expect(color.value, '000000');
      expect(color.from, 'color_dark_android');
    });

    test('hands back an address that names the same cell', () async {
      var c = core();
      await c.computeAll();
      var result =
          (await c.invoke(
                'describe',
                arguments: {'surface': 'android12', 'theme': 'dark'},
              ))!
              as SplashDescribeResult;
      expect(result.address, contains('surface=android12'));
      expect(result.address, contains('theme=dark'));
    });

    test('describes the placement in words, without rendering', () async {
      var c = core();
      await c.computeAll();
      var result =
          (await c.invoke('describe', arguments: {'surface': 'ios'}))!
              as SplashDescribeResult;
      // 1024px at 4x density is 256 logical pixels, centred.
      expect(result.placement, contains('center'));
      expect(result.placement, contains('assets/logo.png'));
    });

    test('flags a dark cell that will show the light splash', () async {
      write('flutter_native_splash.yaml', '''
flutter_native_splash:
  color: "FFFFFF"
  image: assets/logo.png
''');
      var c = core();
      await c.computeAll();
      var result =
          (await c.invoke(
                'describe',
                arguments: {'surface': 'ios', 'theme': 'dark'},
              ))!
              as SplashDescribeResult;
      expect(result.fallsBackToLight, isTrue);
    });

    test('rejects a package it was not declared with', () async {
      var c = core();
      await c.computeAll();
      expect(
        () => c.invoke('describe', arguments: {'package': 'elsewhere'}),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('artifacts', () {
    test('says nothing has been generated rather than pretending', () async {
      write('flutter_native_splash.yaml', '''
flutter_native_splash:
  color: "FFFFFF"
''');
      var c = core();
      await c.computeAll();
      var result = (await c.invoke('artifacts'))! as SplashArtifactsResult;
      expect(result.generated, isFalse);
      expect(result.artifacts, isEmpty);
    });

    test(
      'does not mistake stock Flutter launch images for generated output',
      () async {
        // Every Flutter project ships LaunchImage.imageset from `flutter create`.
        // Counting it reported three generated files — and then a drift warning —
        // for a project that had never run the generator once.
        write('flutter_native_splash.yaml', '''
flutter_native_splash:
  color: "FFFFFF"
''');
        for (var name in [
          'LaunchImage.png',
          'LaunchImage@2x.png',
          'LaunchImage@3x.png',
        ]) {
          writePng(
            'ios/Runner/Assets.xcassets/LaunchImage.imageset/$name',
            10,
            10,
          );
        }

        var c = core();
        await c.computeAll();
        var result = (await c.invoke('artifacts'))! as SplashArtifactsResult;
        expect(result.generated, isFalse);
        expect(result.stale, isFalse);
      },
    );

    test(
      'counts iOS output once the generator has left its own marker',
      () async {
        // `LaunchBackground.imageset` is written unconditionally by
        // `_createiOSSplash`, and by nothing else.
        write('flutter_native_splash.yaml', '''
flutter_native_splash:
  color: "FFFFFF"
''');
        writePng(
          'ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage.png',
          10,
          10,
        );
        write(
          'ios/Runner/Assets.xcassets/LaunchBackground.imageset/Contents.json',
          '{}',
        );

        var c = core();
        await c.computeAll();
        var result = (await c.invoke('artifacts'))! as SplashArtifactsResult;
        expect(result.generated, isTrue);
        expect(result.artifacts.single.surface, 'ios');
      },
    );

    test(
      'finds generated files and classifies them by surface and theme',
      () async {
        write('flutter_native_splash.yaml', '''
flutter_native_splash:
  color: "FFFFFF"
''');
        writePng('android/app/src/main/res/drawable-xxhdpi/splash.png', 10, 10);
        writePng(
          'android/app/src/main/res/drawable-night-xxhdpi/splash.png',
          10,
          10,
        );
        writePng(
          'android/app/src/main/res/drawable-xxhdpi/android12splash.png',
          10,
          10,
        );

        var c = core();
        await c.computeAll();
        var result = (await c.invoke('artifacts'))! as SplashArtifactsResult;

        expect(result.generated, isTrue);
        expect(result.artifacts.where((a) => a.theme == 'dark').length, 1);
        expect(
          result.artifacts.where((a) => a.surface == 'android12').length,
          1,
        );
        expect(result.artifacts.every((a) => a.density == 'xxhdpi'), isTrue);
      },
    );

    test('tells the layers apart, background included', () async {
      // A splash is a stack, and `background.png` — the *colour*, rendered to a
      // bitmap — used to be skipped outright.
      write('flutter_native_splash.yaml', '''
flutter_native_splash:
  color: "FFFFFF"
''');
      writePng('android/app/src/main/res/drawable-xxhdpi/splash.png', 10, 10);
      writePng('android/app/src/main/res/drawable/background.png', 4, 4);
      writePng('android/app/src/main/res/drawable-xxhdpi/branding.png', 8, 8);
      writePng(
        'android/app/src/main/res/drawable-xxhdpi/android12splash.png',
        10,
        10,
      );

      var c = core();
      await c.computeAll();
      var result = (await c.invoke('artifacts'))! as SplashArtifactsResult;

      expect(result.artifacts.map((a) => a.role).toSet(), {
        'image',
        'background',
        'branding',
        'icon',
      });
    });

    test("reads each file's real size without decoding it", () async {
      write('flutter_native_splash.yaml', '''
flutter_native_splash:
  color: "FFFFFF"
''');
      writePng('android/app/src/main/res/drawable-xxhdpi/splash.png', 768, 768);

      var c = core();
      await c.computeAll();
      var result = (await c.invoke('artifacts'))! as SplashArtifactsResult;
      var splash = result.artifacts.single;

      expect(splash.pixelWidth, 768);
      expect(splash.pixelHeight, 768);
      // xxhdpi is 3×, and the generator writes `source * density ~/ 4` — so a
      // 1024px source lands here as 768px, which is 256dp. Every density of one
      // image should agree on that number.
      expect(splash.logicalWidth, 256);
    });

    test('claims no dp for platforms where the rule is unverified', () async {
      write('flutter_native_splash.yaml', '''
flutter_native_splash:
  color: "FFFFFF"
''');
      write(
        'ios/Runner/Assets.xcassets/LaunchBackground.imageset/Contents.json',
        '{}',
      );
      writePng(
        'ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage@3x.png',
        300,
        300,
      );

      var c = core();
      await c.computeAll();
      var result = (await c.invoke('artifacts'))! as SplashArtifactsResult;
      var ios = result.artifacts.firstWhere((a) => a.surface == 'ios');

      expect(ios.pixelWidth, 300);
      expect(ios.logicalWidth, isNull);
    });
  });

  group('the report', () {
    test('projects the whole matrix as text', () async {
      writePng('assets/logo.png', 1024, 1024);
      write('flutter_native_splash.yaml', '''
flutter_native_splash:
  color: "FFFFFF"
  image: assets/logo.png
''');
      var c = core();
      await c.computeAll();
      var text = c.report.toText();

      // Four surfaces, both themes, in the projection `fw` prints.
      for (var label in ['Android', 'Android 12+', 'iOS', 'Web']) {
        expect(text, contains(label), reason: label);
      }
      expect(text, contains('flutter_native_splash.yaml'));
    });

    test('a package with nothing loaded says nothing, and starts nothing', () {
      // The report must never start work — it is read for every plugin on every
      // sidebar paint. It must also not *narrate* that: "not computed" is the
      // resting state of every plugin until you click it, so announcing it drew
      // the eye to the one thing that had not happened.
      var c = core();
      expect(c.report.status, Status.none);
      expect(c.report.children.single.status, Status.none);
      expect(c.report.badge.isEmpty, isTrue);
      expect(c.scanFor('.'), isNull);
    });
  });

  group('does it fit a real screen', () {
    test('an oversized image names the phone it is clipped on', () async {
      // 2048px at 4× is 512dp, which no Android phone is wide enough for.
      writePng('assets/logo.png', 2048, 2048);
      write('flutter_native_splash.yaml', '''
flutter_native_splash:
  color: "FFFFFF"
  image: assets/logo.png
''');
      var c = core();
      await c.computeAll();

      var clipped = (await problems(
        c,
      )).singleWhere((p) => p.message.contains('cut off'));
      expect(clipped.tone, 'warn');
      // The device is what makes it actionable — and navigable.
      expect(clipped.device, 'android-small');
      expect(clipped.message, contains('Small phone'));
    });

    test('a sensibly sized image raises nothing at all', () async {
      writePng('assets/logo.png', 1024, 1024);
      write('flutter_native_splash.yaml', '''
flutter_native_splash:
  color: "FFFFFF"
  image: assets/logo.png
''');
      var c = core();
      await c.computeAll();
      expect(
        (await problems(c)).where((p) => p.message.contains('cut off')),
        isEmpty,
      );
    });

    test(
      'branding with no padding is flagged against the home indicator',
      () async {
        writePng('assets/logo.png', 1024, 1024);
        writePng('assets/branding.png', 800, 320);
        write('flutter_native_splash.yaml', '''
flutter_native_splash:
  color: "FFFFFF"
  image: assets/logo.png
  branding: assets/branding.png
''');
        var c = core();
        await c.computeAll();

        // The key is platform-suffixed, because the number that clears it comes
        // from that platform's hardware — 34dp on a notched iPhone. A global
        // `branding_bottom_padding` set from the worst iPhone would over-pad
        // every Android device to answer an iOS problem.
        var found = (await problems(
          c,
          surface: 'ios',
        )).singleWhere((p) => p.key == 'branding_bottom_padding_ios');
        expect(found.message, contains('home indicator'));
        expect(found.device, isNotNull);
        // The message names the key and the number; nothing writes it.
        expect(found.message, contains('at least'));
      },
    );

    test('one problem per issue, not one per device', () async {
      // Fourteen lines saying the same thing about fourteen phones is how a
      // warning list turns into wallpaper.
      writePng('assets/logo.png', 2048, 2048);
      write('flutter_native_splash.yaml', '''
flutter_native_splash:
  color: "FFFFFF"
  image: assets/logo.png
''');
      var c = core();
      await c.computeAll();
      expect(
        (await problems(c)).where((p) => p.message.contains('cut off')).length,
        1,
      );
    });
  });

  group('staying current', () {
    test(
      'an edited config is picked up without anything being clicked',
      () async {
        write('flutter_native_splash.yaml', '''
flutter_native_splash:
  color: "FFFFFF"
''');
        var c = core();
        await c.computeAll();
        expect(c.scanFor('.')!.main!.config.raw['color'], 'FFFFFF');

        write('flutter_native_splash.yaml', '''
flutter_native_splash:
  color: "FFFFFF"
  color_dark: "101418"
''');
        await c.checkForChanges();

        expect(c.scanFor('.')!.main!.config.raw['color_dark'], '101418');
      },
    );

    test('a re-exported image is picked up too', () async {
      // The half a config watcher would miss: the file that moved is not the
      // config, it is what the config points at.
      writePng('assets/logo.png', 1024, 1024);
      write('flutter_native_splash.yaml', '''
flutter_native_splash:
  color: "FFFFFF"
  android_12:
    image: assets/logo.png
''');
      var c = core();
      await c.computeAll();
      expect(await problems(c, surface: 'android12'), isNotEmpty);

      // 1152 is the canvas the generator wants with no icon background, so the
      // size warning should go away on its own.
      writePng('assets/logo.png', 1152, 1152);
      await c.checkForChanges();

      var found = await problems(c, surface: 'android12');
      expect(found.where((p) => p.key == 'android_12.image'), isEmpty);
    });

    test('an untouched project is not re-read', () async {
      // The point of a fingerprint rather than a timer that just rescans: a
      // quiet project must cost nothing but the `stat`s.
      write('flutter_native_splash.yaml', '''
flutter_native_splash:
  color: "FFFFFF"
''');
      var c = core();
      await c.computeAll();
      var first = c.scannedAt('.');

      await c.checkForChanges();
      expect(c.scannedAt('.'), first);
    });

    test('reload reads again and says whether anything had moved', () async {
      write('flutter_native_splash.yaml', '''
flutter_native_splash:
  color: "FFFFFF"
''');
      var c = core();
      await c.computeAll();

      var quiet = (await c.invoke('reload'))! as SplashReloadResult;
      expect(quiet.changed, isFalse);
      expect(quiet.configPath, 'flutter_native_splash.yaml');

      write('flutter_native_splash.yaml', '''
flutter_native_splash:
  color: "FFFFFF"
  color_dark: "101418"
''');
      var moved = (await c.invoke('reload'))! as SplashReloadResult;
      expect(moved.changed, isTrue);
      expect(c.scanFor('.')!.main!.config.raw['color_dark'], '101418');
    });

    test('reload works on a package that has never been read', () async {
      // It is also the recovery path, so it must not require a good scan first.
      write('flutter_native_splash.yaml', '''
flutter_native_splash:
  color: "FFFFFF"
''');
      var c = core();
      var result = (await c.invoke('reload'))! as SplashReloadResult;
      expect(result.configPath, 'flutter_native_splash.yaml');
      expect(c.scanFor('.'), isNotNull);
    });

    test('retaining twice keeps polling until both let go', () async {
      var c = core();
      var first = c.retain();
      var second = c.retain();
      first();
      first(); // Idempotent — a double release must not take the other retain.
      second();
      // Nothing to assert but that it did not throw and disposes cleanly; the
      // counter is the thing under test.
      c.dispose();
    });
  });
}
