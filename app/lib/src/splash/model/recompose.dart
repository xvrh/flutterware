/// The splash as the *generated files* describe it, not as the config predicts.
///
/// **There is no runtime code in a splash.** `flutter_native_splash:create` is a
/// pure generator: it writes files and exits, and the OS inflates those files at
/// launch. So the picture a device shows is fully determined by a recipe sitting
/// in the repo, and every ingredient of it is readable.
///
/// On Android the recipe is `drawable/launch_background.xml`, a layer-list:
///
/// ```xml
/// <layer-list>
///     <item><bitmap android:gravity="fill"   android:src="@drawable/background" /></item>
///     <item><bitmap android:gravity="center" android:src="@drawable/splash" /></item>
///     <item android:bottom="24dp"><bitmap android:src="@drawable/branding" /></item>
/// </layer-list>
/// ```
///
/// with `styles.xml` pointing `windowBackground` at it. The part that makes this
/// cheap: **even the colour is a PNG** — `_createBackground` renders it to
/// `background.png` rather than emitting a `<color>` drawable — so the whole
/// legacy splash is three bitmaps, one gravity each, and one padding number.
///
/// **This is the panel's answer, not a second opinion.** Everything else here
/// reasons from the config through a hand-transcription of somebody else's
/// `cli_commands.dart`, and a transcription can be confidently wrong — several
/// of them were, and the tests agreed with them, because the tests encoded the
/// same reading. What is on disk cannot be wrong about what is on disk. So a
/// cell shows this when it exists, and falls back to the prediction only where
/// there is nothing to read.
///
/// **Android only.** iOS is `LaunchScreen.storyboard`, which is constraints —
/// a layout engine, not a recipe — and recomposing it would mean implementing
/// one. Web is next; its `style.css` is the easiest of the three. Those two
/// surfaces are predicted permanently, and the panel says so on the tile.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

import 'color.dart';
import 'composition.dart';
import 'generated.dart';
import 'surface.dart';

/// What the generated Android resources say one cell will look like.
///
/// Null only when nothing has been generated for this package at all, or when
/// the surface is one whose output cannot be read back.
///
/// A dark cell with no dark resources is *not* null: it is the light splash,
/// because that is what the device shows. The generator writes
/// `drawable-night/` and `values-night-v31/` only when the config resolved
/// something dark, and Android falls back per file to the unqualified folder —
/// so resolving the same way is what makes this a readback of the device rather
/// than of the directory listing.
SplashComposition? recomposeSplash({
  required String packageRoot,
  required SplashSurface surface,
  required SplashTheme theme,
  required List<SplashArtifact> artifacts,
  String? flavor,
}) {
  if (surface != SplashSurface.android && surface != SplashSurface.android12) {
    return null;
  }
  var res = p.join(packageRoot, androidResFolder(flavor));
  if (!Directory(res).existsSync()) return null;

  // **`launch_background.xml` is not evidence that anything was generated.**
  // `flutter create` writes one — `<item android:drawable="@android:color/white" />`
  // and a commented-out bitmap — into every project from the start. Reading it
  // as generator output produced a "What shipped" with no colour and no layers
  // in it, which the renderer drew as a **black rectangle**: a picture of a
  // splash no device would ever show, on a project that had simply never run
  // `create`.
  //
  // `background.png` is the honest marker, and it is exactly as unconditional as
  // `LaunchBackground.imageset` is on iOS (see `findSplashArtifacts`, which
  // already refuses to count the stock `LaunchImage.imageset` for the same
  // reason). `_createBackground` renders the colour to a 1×1 PNG and **throws**
  // when there is neither a colour nor a background image, so a successful
  // Android run always leaves one behind.
  var ran = artifacts.any(
    (a) =>
        a.role == SplashArtifactRole.background &&
        (a.surface == SplashSurface.android ||
            a.surface == SplashSurface.android12),
  );
  if (!ran) return null;

  return surface == SplashSurface.android12
      ? _recomposeAndroid12(packageRoot, res, theme, artifacts)
      : _recomposeLegacy(packageRoot, res, theme, artifacts);
}

// ---- Legacy ---------------------------------------------------------------

SplashComposition? _recomposeLegacy(
  String packageRoot,
  String res,
  SplashTheme theme,
  List<SplashArtifact> artifacts,
) {
  var document = _readQualified(
    res,
    theme,
    'drawable',
    'launch_background.xml',
  );
  if (document == null) return null;

  SplashLayer? layerFor(SplashArtifactRole role, String? gravity) {
    var artifact = _bestArtifact(artifacts, SplashSurface.android, theme, role);
    if (artifact == null) return null;
    var (fit, alignment) = parseAndroidGravity(gravity);
    // The drawable's pixels divided by its own density bucket — which is what
    // Android does with it, and the number the prediction has to match.
    var scale = splashDensityScale(artifact.density) ?? 1;
    return SplashLayer(
      path: artifact.path,
      absolutePath: p.join(packageRoot, artifact.path),
      fit: fit,
      alignment: alignment,
      naturalWidth: artifact.pixelWidth == null
          ? null
          : artifact.pixelWidth! / scale,
      naturalHeight: artifact.pixelHeight == null
          ? null
          : artifact.pixelHeight! / scale,
    );
  }

  String? gravityOf(String drawable) {
    for (var item in document.findAllElements('item')) {
      var bitmap = item.getElement('bitmap');
      if (bitmap?.getAttribute('android:src') == '@drawable/$drawable') {
        return bitmap?.getAttribute('android:gravity');
      }
    }
    return null;
  }

  bool has(String drawable) => document
      .findAllElements('bitmap')
      .any((b) => b.getAttribute('android:src') == '@drawable/$drawable');

  // `android:bottom="24dp"` on the branding item — the only number in the file.
  var brandingPadding = 0;
  for (var item in document.findAllElements('item')) {
    var bitmap = item.getElement('bitmap');
    if (bitmap?.getAttribute('android:src') != '@drawable/branding') continue;
    var bottom = item.getAttribute('android:bottom');
    if (bottom != null) {
      brandingPadding =
          int.tryParse(bottom.replaceAll(RegExp(r'[^0-9-]'), '')) ?? 0;
    }
  }

  return SplashComposition(
    surface: SplashSurface.android,
    theme: theme,
    enabled: true,
    // The background is a bitmap here, exactly as the layer-list says. Reading
    // a colour back out of it would mean decoding a PNG to learn something the
    // picture already shows.
    backgroundImage: has('background')
        ? layerFor(SplashArtifactRole.background, 'fill')
        : null,
    image: has('splash')
        ? layerFor(SplashArtifactRole.image, gravityOf('splash'))
        : null,
    branding: has('branding')
        ? layerFor(SplashArtifactRole.branding, gravityOf('branding'))
        : null,
    brandingAlignment: parseBrandingMode(
      _brandingModeFrom(gravityOf('branding')),
    ),
    brandingBottomPadding: brandingPadding,
  );
}

/// `android_gravity`'s spelling of a branding position, back to `branding_mode`.
String? _brandingModeFrom(String? gravity) {
  if (gravity == null) return null;
  if (gravity.contains('left') || gravity.contains('start')) {
    return 'bottomLeft';
  }
  if (gravity.contains('right') || gravity.contains('end')) {
    return 'bottomRight';
  }
  return 'bottom';
}

// ---- Android 12 -----------------------------------------------------------

SplashComposition? _recomposeAndroid12(
  String packageRoot,
  String res,
  SplashTheme theme,
  List<SplashArtifact> artifacts,
) {
  // `values-v31` and `values-night-v31`, the theme Android 12 and later read.
  var document = _readQualified(res, theme, 'values-v31', 'styles.xml');
  if (document == null) return null;

  var items = <String, String>{};
  for (var style in document.findAllElements('style')) {
    if (style.getAttribute('name') != 'LaunchTheme') continue;
    for (var item in style.findElements('item')) {
      var name = item.getAttribute('name');
      if (name != null) items[name] = item.innerText.trim();
    }
  }

  // These are literal `#RRGGBB` values in the generated theme, which is what
  // makes Android 12 the one surface whose *colour* can be checked against
  // ground truth without decoding anything.
  var background = parseSplashColor(
    _stripHash(items['android:windowSplashScreenBackground']),
  );
  var iconBackground = parseSplashColor(
    _stripHash(items['android:windowSplashScreenIconBackgroundColor']),
  );

  var hasIcon = items.containsKey('android:windowSplashScreenAnimatedIcon');
  var icon = hasIcon
      ? _bestArtifact(
          artifacts,
          SplashSurface.android12,
          theme,
          SplashArtifactRole.icon,
        )
      : null;

  // `windowSplashScreenBrandingImage`, which this used to ignore entirely — so
  // a project that generated an Android 12 branding image saw it in the
  // prediction and not in what shipped, and drift said nothing because
  // `compareSplash` had nothing to compare.
  //
  // The system positions this itself; there is no padding in the theme to read,
  // which is the same reason `branding_bottom_padding` does not reach this
  // surface (see `checkSplashFit`).
  var branding = items.containsKey('android:windowSplashScreenBrandingImage')
      ? _bestArtifact(
          artifacts,
          SplashSurface.android12,
          theme,
          SplashArtifactRole.branding,
        )
      : null;

  return SplashComposition(
    surface: SplashSurface.android12,
    theme: theme,
    enabled: true,
    backgroundColor: background,
    image: icon == null
        ? null
        : SplashLayer(
            path: icon.path,
            absolutePath: p.join(packageRoot, icon.path),
            fit: SplashFit.contain,
            alignment: SplashAlignment.center,
          ),
    iconBackgroundColor: iconBackground,
    iconCanvas: android12IconCanvasDp,
    iconMaskFraction: android12MaskFraction,
    branding: branding == null
        ? null
        : SplashLayer(
            path: branding.path,
            absolutePath: p.join(packageRoot, branding.path),
            fit: SplashFit.none,
            alignment: SplashAlignment.bottomCenter,
          ),
    // No animated icon in the theme means Android draws the launcher icon.
    usesLauncherIcon: !hasIcon,
  );
}

String? _stripHash(String? value) => value?.replaceFirst('#', '').trim();

// ---- Shared ---------------------------------------------------------------

/// One generated resource, resolved the way the platform resolves it.
///
/// **`-night` falls back per file, not per folder.** A dark cell whose project
/// has no `drawable-night/launch_background.xml` is not a cell with no answer —
/// it is the light splash, because that is the file Android will inflate. The
/// same holds for `values-night-v31/styles.xml`. Reading only the qualified
/// folder and calling its absence "nothing generated" describes the directory
/// listing rather than the device.
///
/// The qualifier goes directly after the resource type, before any others:
/// `drawable` → `drawable-night`, `values-v31` → `values-night-v31`.
XmlDocument? _readQualified(
  String res,
  SplashTheme theme,
  String base,
  String file,
) {
  if (theme == SplashTheme.dark) {
    var cut = base.indexOf('-');
    var night = cut < 0
        ? '$base-night'
        : '${base.substring(0, cut)}-night${base.substring(cut)}';
    var dark = _readXml(File(p.join(res, night, file)));
    if (dark != null) return dark;
  }
  return _readXml(File(p.join(res, base, file)));
}

/// The densest generated file for a role, so the recomposed picture is drawn
/// from the same pixels a modern phone would use.
SplashArtifact? _bestArtifact(
  List<SplashArtifact> artifacts,
  SplashSurface surface,
  SplashTheme theme,
  SplashArtifactRole role,
) {
  SplashArtifact? pick(SplashTheme wanted) {
    SplashArtifact? best;
    for (var artifact in artifacts) {
      if (artifact.surface != surface ||
          artifact.theme != wanted ||
          artifact.role != role) {
        continue;
      }
      var scale = splashDensityScale(artifact.density) ?? 0;
      var bestScale = best == null
          ? -1.0
          : (splashDensityScale(best.density) ?? 0);
      if (best == null || scale > bestScale) best = artifact;
    }
    return best;
  }

  // **Android's own resource resolution, and the reason it belongs here.** The
  // dark `launch_background.xml` references `@drawable/splash` and
  // `@drawable/branding` whether or not a dark copy of either exists — the
  // generator writes it with the *light* paths. With no
  // `drawable-night-xxxhdpi/branding.png`, Android picks
  // `drawable-xxxhdpi/branding.png`, and so must a readback that claims to say
  // what shipped.
  //
  // Reporting "no branding" here was wrong in exactly the same way the
  // prediction was — both halves agreed, and both were describing a device that
  // does not exist.
  return pick(theme) ??
      (theme == SplashTheme.dark ? pick(SplashTheme.light) : null);
}

/// Parsed, or null when the file is absent or not XML at all.
///
/// A malformed `styles.xml` is somebody's hand-edit in progress, not a reason
/// for the panel to throw.
XmlDocument? _readXml(File file) {
  if (!file.existsSync()) return null;
  try {
    return XmlDocument.parse(file.readAsStringSync());
  } on XmlException {
    return null;
  } on FileSystemException {
    return null;
  }
}
