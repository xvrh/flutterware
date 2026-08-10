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

      // **In dp, which is not a detail.** `SplashRender` sizes a `none` layer
      // with no natural size to the whole screen, so leaving these null drew
      // 800×320 across the entire phone — three teal slabs behind the icon,
      // reported as "the Android 12 tile has two logos in it". 800 ÷ 4 is the
      // 200dp Android sizes this slot at, which is why the generator writes
      // that number.
      expect(generated.branding!.naturalWidth, 200);
      expect(generated.branding!.naturalHeight, 80);
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

    test('no dark layer-list resolves to the light one, as Android does', () {
      // The generator writes `drawable-night/launch_background.xml` only when
      // the config resolved something dark. Its absence does not leave the dark
      // cell unanswered — it means the device inflates the unqualified file, so
      // the dark splash *is* the light one. Returning null here made the panel
      // draw a prediction next to a caption saying what shipped.
      writeLaunchBackground();
      writePng(
        'android/app/src/main/res/drawable-xxxhdpi/splash.png',
        1024,
        1024,
      );

      var light = recompose(SplashSurface.android, SplashTheme.light)!;
      var dark = recompose(SplashSurface.android, SplashTheme.dark)!;
      expect(dark.image!.path, light.image!.path);
      expect(dark.theme, SplashTheme.dark);
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

  group('the web splash, out of index.html', () {
    /// What `_createSplashCss`, `_createSplashJs` and `_updateHtml` leave
    /// behind — one file, since 2.4.x inlines the stylesheet rather than
    /// linking `splash/style.css`.
    void writeIndexHtml({
      String color = '#FFFF00',
      String? darkColor,
      String? backgroundImage,
      String imageMode = 'center',
      bool image = true,
      String? brandingMode,
    }) {
      write('web/index.html', '''
<!DOCTYPE html>
<html>
<head>
  <style id="splash-screen-style">
    html { height: 100% }

    body {
      margin: 0;
      min-height: 100%;
      background-color: $color;
${backgroundImage == null ? '' : '      background-image: url("splash/img/$backgroundImage");'}
      background-size: 100% 100%;
    }

    .center { position: absolute; top: 50%; left: 50%; }
    .contain { object-fit: contain; }
${darkColor == null ? '' : '''
    @media (prefers-color-scheme: dark) {
      body {
        background-color: $darkColor;
      }
    }'''}
  </style>
</head>
<body>
${image ? '''  <picture id="splash">
      <source srcset="splash/img/light-1x.png 1x, splash/img/light-4x.png 4x" media="(prefers-color-scheme: light)">
      <source srcset="splash/img/dark-1x.png 1x, splash/img/dark-4x.png 4x" media="(prefers-color-scheme: dark)">
      <img class="$imageMode" aria-hidden="true" src="splash/img/light-1x.png" alt=""/>
  </picture>''' : ''}
${brandingMode == null ? '' : '''  <picture id="splash-branding">
    <source srcset="splash/img/branding-4x.png 4x" media="(prefers-color-scheme: light)">
    <source srcset="splash/img/branding-dark-4x.png 4x" media="(prefers-color-scheme: dark)">
    <img class="$brandingMode" aria-hidden="true" src="splash/img/branding-1x.png" alt=""/>
  </picture>'''}
</body>
</html>
''');
    }

    /// The generator writes each density at `source * n ~/ 4`, both themes
    /// always — `darkImagePath ??= imagePath`.
    void writeWebImages({
      int source = 1024,
      bool branding = false,
      String? background,
    }) {
      for (var name in ['light', 'dark']) {
        for (var n in [1, 2, 3, 4]) {
          writePng(
            'web/splash/img/$name-${n}x.png',
            source * n ~/ 4,
            source * n ~/ 4,
          );
        }
      }
      if (branding) {
        for (var name in ['branding', 'branding-dark']) {
          for (var n in [1, 2, 3, 4]) {
            writePng(
              'web/splash/img/$name-${n}x.png',
              400 * n ~/ 4,
              100 * n ~/ 4,
            );
          }
        }
      }
      if (background != null) writePng('web/splash/img/$background', 8, 8);
    }

    SplashComposition? web(SplashTheme theme) => recomposeSplash(
      packageRoot: root.path,
      surface: SplashSurface.web,
      theme: theme,
      artifacts: artifacts(),
    );

    test('a stock index.html is not generator output', () {
      // `flutter create`'s own file. No `<style id="splash-screen-style">` in
      // it — unlike Android's `launch_background.xml`, there is nothing here to
      // mistake for a generated splash, which is why the marker can be the
      // element itself.
      write(
        'web/index.html',
        '<!DOCTYPE html><html><head></head><body></body></html>',
      );
      expect(web(SplashTheme.light), isNull);
    });

    test('no web/index.html at all is null, not a throw', () {
      expect(web(SplashTheme.light), isNull);
    });

    test('reads the colour out of the inline stylesheet', () {
      writeIndexHtml(color: '#FFFF00', darkColor: '#101418');
      writeWebImages();

      expect(web(SplashTheme.light)!.backgroundColor, 0xFFFFFF00);
      expect(web(SplashTheme.dark)!.backgroundColor, 0xFF101418);
    });

    test('a missing dark media query means dark is the light colour', () {
      // The CSS cascade's own answer, and the same fact `drawable-night`'s
      // absence carries on Android.
      writeIndexHtml(color: '#FFFF00');
      writeWebImages();

      expect(web(SplashTheme.dark)!.backgroundColor, 0xFFFFFF00);
    });

    test('the densest file wins, and its CSS size is its own multiplier', () {
      // `light-4x.png` is 1024 wide and carries a `4x` descriptor, so the
      // browser draws it at 256 CSS px — the same 256 every other density lands
      // on, which is the whole point of the ~/ 4.
      writeIndexHtml();
      writeWebImages(source: 1024);

      var image = web(SplashTheme.light)!.image!;
      expect(image.path, 'web/splash/img/light-4x.png');
      expect(image.naturalWidth, 256);
    });

    test('the img class is the placement', () {
      writeIndexHtml(imageMode: 'contain');
      writeWebImages();
      expect(web(SplashTheme.light)!.image!.fit, SplashFit.contain);

      writeIndexHtml(imageMode: 'center');
      expect(web(SplashTheme.light)!.image!.fit, SplashFit.none);
    });

    test('no picture#splash means no image, whatever is on disk', () {
      // The files stay behind a config that stopped setting `image`, so the
      // directory listing says one thing and the page says another. The page is
      // the one the browser reads.
      writeIndexHtml(image: false);
      writeWebImages();

      expect(web(SplashTheme.light)!.image, isNull);
    });

    test('branding comes back with its own dark file and its mode', () {
      writeIndexHtml(brandingMode: 'bottomRight');
      writeWebImages(branding: true);

      var light = web(SplashTheme.light)!.branding!;
      var dark = web(SplashTheme.dark)!.branding!;
      expect(light.path, 'web/splash/img/branding-4x.png');
      expect(dark.path, 'web/splash/img/branding-dark-4x.png');
      expect(light.alignment, SplashAlignment.bottomRight);
    });

    test('a background image stretches, because the template says so', () {
      writeIndexHtml(backgroundImage: 'light-background.png');
      writeWebImages(background: 'light-background.png');

      var background = web(SplashTheme.light)!.backgroundImage!;
      expect(background.path, 'web/splash/img/light-background.png');
      expect(background.fit, SplashFit.fill);
    });
  });

  group('the picture one cell shows', () {
    void writeConfig([String extra = '']) {
      write('pubspec.yaml', 'name: sample\n');
      write('flutter_native_splash.yaml', '''
flutter_native_splash:
  color: "FFFFFF"
  image: assets/logo.png
$extra''');
      writePng('assets/logo.png', 1024, 1024);
    }

    SplashPicture picture(SplashSurface surface, SplashTheme theme) =>
        scanSplash(
          packageRoot: root.path,
          packagePath: '.',
        ).main!.pictureFor(surface, theme);

    test('is the generated files wherever they exist', () {
      writeConfig();
      writeLaunchBackground();
      writePng(
        'android/app/src/main/res/drawable-xxxhdpi/splash.png',
        1024,
        1024,
      );

      var shown = picture(SplashSurface.android, SplashTheme.light);
      expect(shown.isGenerated, isTrue);
      expect(shown.reason, isNull);
      expect(shown.label, 'From the generated files');
    });

    test('is still the generated files in dark with no dark resources', () {
      // **The `-night` qualifier falls back per file.** With no
      // `drawable-night/launch_background.xml` the device inflates the
      // unqualified one, so the dark cell is the light splash — a fact, not a
      // gap. Calling it "nothing generated" and drawing the prediction instead
      // describes the directory listing rather than the phone.
      writeConfig('  color_dark: "101418"\n');
      writeLaunchBackground();
      writePng(
        'android/app/src/main/res/drawable-xxxhdpi/splash.png',
        1024,
        1024,
      );

      var shown = picture(SplashSurface.android, SplashTheme.dark);
      expect(shown.isGenerated, isTrue);
      expect(shown.composition.image, isNotNull);
    });

    test('prefers the dark resources when the generator wrote them', () {
      writeConfig('  color_dark: "101418"\n');
      writeLaunchBackground();
      writeLaunchBackground(folder: 'drawable-night', gravity: 'bottom');
      writePng(
        'android/app/src/main/res/drawable-xxxhdpi/splash.png',
        1024,
        1024,
      );

      var shown = picture(SplashSurface.android, SplashTheme.dark);
      expect(shown.isGenerated, isTrue);
      // `bottom` is only in the night layer-list, so this is proof the dark file
      // won rather than the fallback firing anyway.
      expect(shown.composition.image!.alignment, SplashAlignment.bottomCenter);
    });

    test('android 12 falls back to values-v31 the same way', () {
      writeConfig('  color_dark: "101418"\n');
      writeV31Styles();
      writePng(
        'android/app/src/main/res/drawable-xxxhdpi-v31/android12splash.png',
        768,
        768,
      );

      var shown = picture(SplashSurface.android12, SplashTheme.dark);
      expect(shown.isGenerated, isTrue);
      expect(shown.composition.image, isNotNull);
    });

    test('is a prediction on iOS, permanently, and says why', () {
      writeConfig();
      writeLaunchBackground();

      var shown = picture(SplashSurface.ios, SplashTheme.light);
      expect(shown.isGenerated, isFalse);
      expect(shown.label, 'Prediction');
      expect(shown.reason, contains('cannot be read back'));
      expect(shown.reason, contains('storyboard'));
    });

    test('is a prediction that names the next step before create has run', () {
      writeConfig();

      var shown = picture(SplashSurface.android, SplashTheme.light);
      expect(shown.isGenerated, isFalse);
      expect(shown.reason, contains('Nothing has been generated yet'));
      expect(shown.reason, contains('flutter_native_splash:create'));
    });
  });
}
