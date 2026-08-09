import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware_app/src/splash/model/composition.dart';
import 'package:flutterware_app/src/splash/model/generated.dart';
import 'package:flutterware_app/src/splash/model/recompose.dart';
import 'package:flutterware_app/src/splash/model/scan.dart';
import 'package:flutterware_app/src/splash/model/surface.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

/// Reading the splash back out of the files the generator wrote.
///
/// The XML here is the generator's own, copied from `templates.dart` and
/// `android.dart` rather than invented — a parser tested against XML this file
/// made up would only prove it agrees with itself.
void main() {
  late Directory root;

  void write(String relative, String content) {
    var file = File(p.join(root.path, relative));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
  }

  void writePng(String relative, int width, int height) {
    var file = File(p.join(root.path, relative));
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(
      img.encodePng(img.Image(width: width, height: height)),
    );
  }

  /// What `_applyLaunchBackgroundXml` produces.
  ///
  /// [withBackgroundPng] models the other half of the same Android run:
  /// `_createBackground` renders the colour to a 1×1 PNG beside the layer-list
  /// and throws if it has neither a colour nor a background image, so a real
  /// generated project always has both. Only the test for the guard itself
  /// turns it off.
  void writeLaunchBackground({
    String folder = 'drawable',
    String gravity = 'center',
    bool image = true,
    bool branding = false,
    int brandingBottom = 0,
    bool withBackgroundPng = true,
  }) {
    if (withBackgroundPng) {
      writePng('android/app/src/main/res/$folder/background.png', 1, 1);
    }
    write('android/app/src/main/res/$folder/launch_background.xml', '''
<?xml version="1.0" encoding="utf-8"?>
<layer-list xmlns:android="http://schemas.android.com/apk/res/android">
    <item>
        <bitmap android:gravity="fill" android:src="@drawable/background" />
    </item>
${image ? '    <item>\n        <bitmap android:gravity="$gravity" android:src="@drawable/splash" />\n    </item>' : ''}
${branding ? '    <item android:bottom="${brandingBottom}dp">\n        <bitmap android:gravity="bottom" android:src="@drawable/branding" />\n    </item>' : ''}
</layer-list>
''');
  }

  /// What `_updateStylesFile` leaves in `values-v31/styles.xml`.
  void writeV31Styles({
    String? background = '#FFFFFF',
    bool icon = true,
    String? iconBackground,
    bool branding = false,
  }) {
    // The v31 theme is written by the same Android run that renders the
    // background bitmap; a project with one and not the other has not run
    // `create`.
    writePng('android/app/src/main/res/drawable/background.png', 1, 1);
    write('android/app/src/main/res/values-v31/styles.xml', '''
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <style name="LaunchTheme" parent="@android:style/Theme.Light.NoTitleBar">
${background == null ? '' : '        <item name="android:windowSplashScreenBackground">$background</item>'}
${icon ? '        <item name="android:windowSplashScreenAnimatedIcon">@drawable/android12splash</item>' : ''}
${branding ? '        <item name="android:windowSplashScreenBrandingImage">@drawable/android12branding</item>' : ''}
${iconBackground == null ? '' : '        <item name="android:windowSplashScreenIconBackgroundColor">$iconBackground</item>'}
    </style>
</resources>
''');
  }

  List<SplashArtifact> artifacts() => findSplashArtifacts(root.path);

  SplashComposition? recompose(SplashSurface surface, SplashTheme theme) =>
      recomposeSplash(
        packageRoot: root.path,
        surface: surface,
        theme: theme,
        artifacts: artifacts(),
      );

  setUp(() => root = Directory.systemTemp.createTempSync('splash_recompose'));
  tearDown(() => root.deleteSync(recursive: true));

  group('a project that has never run the generator', () {
    /// Exactly what `flutter create` leaves behind, comment and all.
    ///
    /// Reading this as generator output produced a `SplashComposition` with no
    /// colour and no layers in it, which the renderer drew as a **black
    /// rectangle** beside the prediction — a picture of a splash no device would
    /// ever show, on a project whose only crime was not having run `create`.
    /// It is the first thing anybody opening the panel on a fresh app saw.
    void writeStockLaunchBackground({String folder = 'drawable'}) {
      write('android/app/src/main/res/$folder/launch_background.xml', '''
<?xml version="1.0" encoding="utf-8"?>
<!-- Modify this file to customize your launch splash screen -->
<layer-list xmlns:android="http://schemas.android.com/apk/res/android">
    <item android:drawable="@android:color/white" />

    <!-- You can insert your own image assets here -->
    <!-- <item>
        <bitmap
            android:gravity="center"
            android:src="@mipmap/launch_image" />
    </item> -->
</layer-list>
''');
    }

    test('is not read back at all', () {
      writeStockLaunchBackground();
      writeStockLaunchBackground(folder: 'drawable-v21');

      // Null, not an empty composition. "There is nothing to compare against"
      // is the truth here and the panel has a sentence for it; a composition
      // means "this is what shipped".
      expect(recompose(SplashSurface.android, SplashTheme.light), isNull);
      expect(recompose(SplashSurface.android12, SplashTheme.light), isNull);
    });

    test('and the scan agrees nothing was generated', () {
      writeStockLaunchBackground();
      expect(findSplashArtifacts(root.path), isEmpty);
    });

    test('one background.png is what makes it evidence', () {
      // `_createBackground` renders the colour to a 1×1 PNG and *throws* when
      // there is neither a colour nor a background image, so a successful
      // Android run always leaves one. Same marker, same reasoning, as
      // `LaunchBackground.imageset` on iOS.
      writeLaunchBackground(withBackgroundPng: false);
      expect(recompose(SplashSurface.android, SplashTheme.light), isNull);

      writePng('android/app/src/main/res/drawable/background.png', 1, 1);
      expect(recompose(SplashSurface.android, SplashTheme.light), isNotNull);
    });
  });

  group('dark resources that were never written', () {
    test('resolve to the light drawable, as Android resolves them', () {
      // The dark `launch_background.xml` references `@drawable/splash` and
      // `@drawable/branding` whether or not dark copies exist — the generator
      // writes it with `showImage: imagePath != null`, the *light* path. With no
      // `drawable-night-xxxhdpi/branding.png`, Android picks the non-night
      // folder, and so must anything claiming to say what shipped.
      writeLaunchBackground(branding: true);
      writeLaunchBackground(folder: 'drawable-night', branding: true);
      writePng(
        'android/app/src/main/res/drawable-xxxhdpi/splash.png',
        1024,
        1024,
      );
      writePng(
        'android/app/src/main/res/drawable-xxxhdpi/branding.png',
        800,
        320,
      );
      // A dark splash exists; a dark branding does not.
      writePng(
        'android/app/src/main/res/drawable-night-xxxhdpi/splash.png',
        512,
        512,
      );

      var dark = recompose(SplashSurface.android, SplashTheme.dark)!;
      expect(dark.image!.path, contains('drawable-night-xxxhdpi'));
      // Reporting "no branding" here was wrong in exactly the way the
      // prediction was, which is why drift never caught it.
      expect(dark.branding, isNotNull);
      expect(dark.branding!.path, contains('drawable-xxxhdpi/branding.png'));
    });

    test('a density qualifier carrying an API level is still a density', () {
      // `drawable-xxxhdpi-v31` is both. Reading it as "not a density" made every
      // Android 12 artifact score the same, so the readback named
      // `drawable-hdpi-v31` — the first and lowest — as the file that shipped.
      expect(splashDensityScale('xxxhdpi-v31'), 4);
      expect(splashDensityScale('mdpi-v31'), 1);
      // Still null for the things that really are only API levels.
      expect(splashDensityScale('v31'), isNull);
      expect(splashDensityScale('v21'), isNull);
      expect(splashDensityScale(null), isNull);
    });

    test('the Android 12 branding is read out of the theme', () {
      // `windowSplashScreenBrandingImage` was ignored entirely, so a project
      // that generated one saw it in the prediction and not in what shipped.
      writeV31Styles(branding: true);
      writePng(
        'android/app/src/main/res/drawable-xxxhdpi-v31/android12branding.png',
        800,
        320,
      );
      writePng(
        'android/app/src/main/res/drawable-xxxhdpi/android12splash.png',
        1152,
        1152,
      );

      var generated = recompose(SplashSurface.android12, SplashTheme.light)!;
      expect(generated.branding, isNotNull);
      expect(generated.branding!.path, contains('xxxhdpi-v31'));
    });

    test('and no branding in the theme means none in the picture', () {
      writeV31Styles();
      writePng(
        'android/app/src/main/res/drawable-xxxhdpi-v31/android12branding.png',
        800,
        320,
      );

      // The file being on disk is not the question — the theme is what Android
      // reads, and this one does not name a branding image.
      expect(
        recompose(SplashSurface.android12, SplashTheme.light)!.branding,
        isNull,
      );
    });
  });

  group('legacy Android', () {
    test('reads the layer-list back as layers', () {
      writeLaunchBackground();
      writePng(
        'android/app/src/main/res/drawable-xxxhdpi/splash.png',
        1024,
        1024,
      );
      writePng('android/app/src/main/res/drawable/background.png', 4, 4);

      var generated = recompose(SplashSurface.android, SplashTheme.light)!;
      expect(generated.backgroundImage, isNotNull);
      expect(generated.image, isNotNull);
      // xxxhdpi is 4×, so 1024px of drawable is 256dp on screen — the same
      // number the prediction reaches from a 1024px source ÷ 4.
      expect(generated.image!.naturalWidth, 256);
      expect(generated.image!.alignment, SplashAlignment.center);
    });

    test('carries the gravity the generator wrote', () {
      writeLaunchBackground(gravity: 'bottom|fill_horizontal');
      writePng(
        'android/app/src/main/res/drawable-xxxhdpi/splash.png',
        1024,
        1024,
      );

      var generated = recompose(SplashSurface.android, SplashTheme.light)!;
      expect(generated.image!.fit, SplashFit.fillWidth);
      expect(generated.image!.alignment, SplashAlignment.bottomCenter);
    });

    test('reads the branding padding off the item', () {
      writeLaunchBackground(branding: true, brandingBottom: 48);
      writePng(
        'android/app/src/main/res/drawable-xxxhdpi/splash.png',
        1024,
        1024,
      );
      writePng(
        'android/app/src/main/res/drawable-xxxhdpi/branding.png',
        800,
        320,
      );

      var generated = recompose(SplashSurface.android, SplashTheme.light)!;
      expect(generated.branding, isNotNull);
      expect(generated.brandingBottomPadding, 48);
    });

    test('a config with no image produces a layer-list with no splash', () {
      writeLaunchBackground(image: false);
      writePng('android/app/src/main/res/drawable/background.png', 4, 4);

      var generated = recompose(SplashSurface.android, SplashTheme.light)!;
      expect(generated.image, isNull);
    });

    test('no dark layer-list is the fallback, stated as null', () {
      // The generator writes `drawable-night/launch_background.xml` only when
      // the config resolved something dark. Its absence is ground truth that
      // the OS shows the light splash — the plugin's single most important
      // claim, checked against the disk rather than against itself.
      writeLaunchBackground();
      writePng(
        'android/app/src/main/res/drawable-xxxhdpi/splash.png',
        1024,
        1024,
      );

      expect(recompose(SplashSurface.android, SplashTheme.light), isNotNull);
      expect(recompose(SplashSurface.android, SplashTheme.dark), isNull);
    });

    test('a hand-mangled layer-list is null, not a throw', () {
      write(
        'android/app/src/main/res/drawable/launch_background.xml',
        '<layer-list><item>',
      );
      expect(recompose(SplashSurface.android, SplashTheme.light), isNull);
    });
  });

  group('Android 12', () {
    test('reads the literal colours out of the v31 theme', () {
      // The one surface whose *colour* is checkable without decoding anything:
      // the generator writes `#RRGGBB` straight into styles.xml.
      writeV31Styles(background: '#101418', iconBackground: '#FFFFFF');
      writePng(
        'android/app/src/main/res/drawable-xxxhdpi/android12splash.png',
        960,
        960,
      );

      var generated = recompose(SplashSurface.android12, SplashTheme.light)!;
      expect(generated.backgroundColor, 0xFF101418);
      expect(generated.iconBackgroundColor, 0xFFFFFFFF);
      expect(generated.usesLauncherIcon, isFalse);
      expect(generated.image, isNotNull);
    });

    test('no animated icon means the launcher icon, from the theme itself', () {
      writeV31Styles(icon: false);
      var generated = recompose(SplashSurface.android12, SplashTheme.light)!;
      expect(generated.usesLauncherIcon, isTrue);
      expect(generated.image, isNull);
    });
  });

  group('comparing the two', () {
    SplashComposition android({
      SplashFit fit = SplashFit.none,
      double? width,
      int brandingPadding = 0,
      bool branding = false,
    }) => SplashComposition(
      surface: SplashSurface.android,
      theme: SplashTheme.light,
      enabled: true,
      image: SplashLayer(
        path: 'logo.png',
        fit: fit,
        alignment: SplashAlignment.center,
        naturalWidth: width ?? 256,
        naturalHeight: width ?? 256,
      ),
      branding: branding
          ? const SplashLayer(
              path: 'b.png',
              fit: SplashFit.none,
              alignment: SplashAlignment.bottomCenter,
            )
          : null,
      brandingBottomPadding: brandingPadding,
    );

    test('agreement is silent', () {
      expect(
        compareSplash(predicted: android(), generated: android()),
        isEmpty,
      );
    });

    test('a different placement is reported', () {
      var notes = compareSplash(
        predicted: android(),
        generated: android(fit: SplashFit.cover),
      );
      expect(notes.single, contains('image placement'));
    });

    test('a different size is reported', () {
      var notes = compareSplash(
        predicted: android(width: 256),
        generated: android(width: 512),
      );
      expect(notes.single, contains('256'));
      expect(notes.single, contains('512'));
    });

    test('a different branding padding is reported', () {
      var notes = compareSplash(
        predicted: android(branding: true, brandingPadding: 0),
        generated: android(branding: true, brandingPadding: 48),
      );
      expect(notes.single, contains('branding bottom padding'));
    });
  });

  group('through the scan', () {
    test('a faithful generated set raises no drift', () {
      write('pubspec.yaml', 'name: sample\n');
      write('flutter_native_splash.yaml', '''
flutter_native_splash:
  color: "FFFFFF"
  image: assets/logo.png
''');
      writePng('assets/logo.png', 1024, 1024);
      writeLaunchBackground();
      writePng(
        'android/app/src/main/res/drawable-xxxhdpi/splash.png',
        1024,
        1024,
      );
      writePng('android/app/src/main/res/drawable/background.png', 4, 4);

      var scan = scanSplash(packageRoot: root.path, packagePath: '.');
      expect(
        scan.main!.problems.where((p) => p.message.contains('does not match')),
        isEmpty,
      );
    });

    test('a generated set that disagrees is reported against us', () {
      write('pubspec.yaml', 'name: sample\n');
      write('flutter_native_splash.yaml', '''
flutter_native_splash:
  color: "FFFFFF"
  image: assets/logo.png
''');
      writePng('assets/logo.png', 1024, 1024);
      // The drawable says `bottom`, the config says nothing — so the prediction
      // centres and the shipped splash does not.
      writeLaunchBackground(gravity: 'bottom');
      writePng(
        'android/app/src/main/res/drawable-xxxhdpi/splash.png',
        1024,
        1024,
      );
      writePng('android/app/src/main/res/drawable/background.png', 4, 4);

      var scan = scanSplash(packageRoot: root.path, packagePath: '.');
      var drift = scan.main!.problems.singleWhere(
        (p) => p.message.contains('does not match'),
      );
      // Never a warning: this indicts our reading of the generator, not the
      // project, and a perfect config must not grow an amber dot for it.
      expect(drift.tone.name, 'info');
      expect(drift.message, contains('not a problem with your project'));
    });
  });
}
