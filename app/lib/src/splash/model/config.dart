/// The `flutter_native_splash` config, and what each surface actually resolves
/// out of it.
///
/// The cascade here is **transcribed from the package's own
/// `cli_commands.dart`, not inferred from its README**, because the two do not
/// say the same thing and the difference is the whole reason this plugin is
/// worth having. See [SplashConfig.resolve] for the rule and for the trap it
/// exposes.
library;

import 'surface.dart';

/// Where a config was found. Part of the answer, not bookkeeping: a project with
/// both a `flutter_native_splash.yaml` and a `flutter_native_splash:` block in
/// its pubspec is reading only one of them, and which one is the first thing to
/// tell someone whose edits appear to do nothing.
enum SplashConfigKind {
  /// `flutter_native_splash-<flavor>.yaml`.
  flavorFile,

  /// `flutter_native_splash.yaml`.
  file,

  /// The `flutter_native_splash:` key inside `pubspec.yaml`.
  pubspec,
}

/// One property resolved for a surface and a theme, carrying the key that won.
///
/// The key is the point. A resolved colour on its own invites "but I set
/// `color`" — the key answers it, and is what the panel prints beside the value
/// and what `describe` puts in its output.
class Resolved<T extends Object> {
  const Resolved(this.value, this.key);

  const Resolved.absent() : value = null, key = null;

  final T? value;

  /// The config key this came from — `color_dark_android`, or
  /// `android_12.color`. Null exactly when [value] is.
  final String? key;

  bool get isPresent => value != null;

  Map<String, Object?> toJson() => {
    if (value != null) 'value': '$value',
    if (key != null) 'from': key,
  };

  @override
  String toString() => value == null ? 'absent' : '$value (from $key)';
}

/// A parsed `flutter_native_splash` config for one package.
///
/// Holds the decoded YAML and nothing derived — [resolve] and the accessors are
/// pure reads, so a config is cheap to build and safe to keep.
class SplashConfig {
  SplashConfig({
    required this.raw,
    required this.kind,
    required this.path,
    this.flavor,
  });

  /// The decoded map, exactly as written.
  final Map<String, Object?> raw;

  final SplashConfigKind kind;

  /// Package-relative path of the file it was read from — `pubspec.yaml` for
  /// [SplashConfigKind.pubspec].
  final String path;

  /// The flavor this config is for, for `flutter_native_splash-<flavor>.yaml`.
  final String? flavor;

  /// The `android_12:` block, or empty when the project declared none.
  ///
  /// Empty and absent are deliberately the same here for *reading*; whether the
  /// section exists at all is a separate question, and [hasAndroid12Section]
  /// is what answers it — because "no section" is the single most consequential
  /// thing this config can say.
  Map<String, Object?> get android12Section {
    var section = raw['android_12'];
    return section is Map ? section.cast<String, Object?>() : const {};
  }

  bool get hasAndroid12Section => raw['android_12'] is Map;

  /// Resolves [base] for [surface] and [theme].
  ///
  /// The rule, transcribed from `_createSplashByConfig`:
  ///
  /// ```dart
  /// color:     colorAndroid     ?? color
  /// darkColor: darkColorAndroid ?? darkColor
  /// ```
  ///
  /// **Light and dark are two independent two-step chains.** Dark never falls
  /// through to light — `color_dark_android ?? color_dark` and then nothing. A
  /// project that sets `color` and no `color_dark` resolves *nothing* for dark
  /// here.
  ///
  /// **That is the config level, and it is only half the story.** The files the
  /// generator writes are platform *resources*, and every platform resolves a
  /// missing dark resource to the light one — so "nothing resolved" does not
  /// mean "nothing is shown". [resolveSplash] is where that second half lives,
  /// and reading this method as the whole answer is what produced the plugin's
  /// most confident wrong claim. Nothing here should grow a fallback; the
  /// distinction is the point.
  Resolved<String> resolve(
    String base,
    SplashSurface surface,
    SplashTheme theme,
  ) {
    var suffix = surface.keySuffix;
    var keys = switch (theme) {
      SplashTheme.light => ['${base}_$suffix', base],
      SplashTheme.dark => ['${base}_dark_$suffix', '${base}_dark'],
    };
    for (var key in keys) {
      var value = stringify(raw[key]);
      if (value != null) return Resolved(value, key);
    }
    return const Resolved.absent();
  }

  /// The Android 12 window background.
  ///
  /// `android12Color = android_12.color ?? color` — the **top-level** `color`,
  /// not `color_android`, which is a genuine asymmetry in the package rather
  /// than a simplification here. Dark then falls back to the resolved light
  /// value, matching `android12DarkBackgroundColor: android12DarkColor ??
  /// android12Color`.
  Resolved<String> android12Color(SplashTheme theme) {
    var section = android12Section;
    if (theme == SplashTheme.light) {
      var own = stringify(section['color']);
      if (own != null) return Resolved(own, 'android_12.color');
      var top = stringify(raw['color']);
      return top == null ? const Resolved.absent() : Resolved(top, 'color');
    }
    var own = stringify(section['color_dark']);
    if (own != null) return Resolved(own, 'android_12.color_dark');
    var top = stringify(raw['color_dark']);
    if (top != null) return Resolved(top, 'color_dark');
    return android12Color(SplashTheme.light);
  }

  /// The Android 12 icon.
  ///
  /// **No fallback to the top-level `image`** — `android12Image` is read from
  /// the section and nowhere else. This is the footgun: an app with a perfectly
  /// good `image:` and no `android_12:` section shows its *launcher icon* on
  /// every device from Android 12 on, because the generator then writes no
  /// `windowSplashScreenAnimatedIcon` and that attribute's platform default is
  /// the app icon. `validateSplash` reports it, and `composeSplash` draws the
  /// launcher icon rather than nothing, so the preview shows what will really
  /// happen.
  Resolved<String> android12Image(SplashTheme theme) {
    var section = android12Section;
    if (theme == SplashTheme.dark) {
      var dark = stringify(section['image_dark']);
      if (dark != null) return Resolved(dark, 'android_12.image_dark');
    }
    var light = stringify(section['image']);
    return light == null
        ? const Resolved.absent()
        : Resolved(light, 'android_12.image');
  }

  /// The circle drawn behind the Android 12 icon. Also decides the icon canvas
  /// the package expects — 960px with one, 1152px without.
  Resolved<String> android12IconBackgroundColor(SplashTheme theme) {
    var section = android12Section;
    if (theme == SplashTheme.dark) {
      var dark = stringify(section['icon_background_color_dark']);
      if (dark != null) {
        return Resolved(dark, 'android_12.icon_background_color_dark');
      }
    }
    var light = stringify(section['icon_background_color']);
    return light == null
        ? const Resolved.absent()
        : Resolved(light, 'android_12.icon_background_color');
  }

  Resolved<String> android12Branding(SplashTheme theme) {
    var section = android12Section;
    if (theme == SplashTheme.dark) {
      var dark = stringify(section['branding_dark']);
      if (dark != null) return Resolved(dark, 'android_12.branding_dark');
    }
    var light = stringify(section['branding']);
    return light == null
        ? const Resolved.absent()
        : Resolved(light, 'android_12.branding');
  }

  /// Whether the project switched a platform off with `android: false`.
  ///
  /// Absent means on — the generator's own test is
  /// `!config.containsKey(platform) || config[platform] as bool`.
  bool enabled(SplashSurface surface) {
    var value = raw[surface.enableKey];
    return value is bool ? value : true;
  }

  /// Placement and chrome keys, which are **global** — none of them is
  /// platform-suffixed or has a dark variant, however much the rest of the
  /// config suggests they might be.
  String? get androidGravity => stringify(raw['android_gravity']);
  String? get iosContentMode => stringify(raw['ios_content_mode']);
  String? get webImageMode => stringify(raw['web_image_mode']);
  String? get brandingMode => stringify(raw['branding_mode']);

  bool get fullscreen => raw['fullscreen'] == true;

  /// `branding_bottom_padding_<platform> ?? branding_bottom_padding`. Suffixed
  /// per platform, but with no dark variant.
  int brandingBottomPadding(SplashSurface surface) {
    var suffixed = raw['branding_bottom_padding_${surface.keySuffix}'];
    var value = suffixed ?? raw['branding_bottom_padding'];
    return switch (value) {
      int v => v,
      num v => v.toInt(),
      String v => int.tryParse(v) ?? 0,
      _ => 0,
    };
  }

  /// Every key the project actually wrote, for reporting unknown ones.
  Set<String> get declaredKeys => {
    ...raw.keys,
    for (var key in android12Section.keys) 'android_12.$key',
  };

  /// YAML gives a number where a colour is expected — `color: 000000` parses as
  /// the int `0`, and `#ffffff` only stays a string because of the quotes the
  /// author remembered. Coercing here means the cascade never silently skips a
  /// key that was set.
  ///
  /// The zero-padding is the package's, verbatim:
  ///
  /// ```dart
  /// if (colorValue is int) colorValue = colorValue.toString().padLeft(6, '0');
  /// ```
  ///
  /// so `color: 000000` resolves to `000000` here exactly as it does there.
  static String? stringify(Object? value) => switch (value) {
    String v when v.trim().isNotEmpty => v.trim(),
    String() => null,
    null => null,
    int v => v.toString().padLeft(6, '0'),
    _ => '$value',
  };
}

/// Everything one surface × theme resolves to, and how it got there.
///
/// Built by [resolveSplash]. Pure data, so `fw describe` prints it, the panel
/// draws from it, and neither can disagree with the other about what the config
/// says.
class SplashResolution {
  SplashResolution({
    required this.surface,
    required this.theme,
    required this.enabled,
    required this.color,
    required this.backgroundImage,
    required this.image,
    required this.branding,
    required this.iconBackgroundColor,
    required this.fit,
    required this.alignment,
    required this.brandingAlignment,
    required this.brandingBottomPadding,
    required this.fullscreen,
    required this.fallsBackToLight,
  });

  final SplashSurface surface;
  final SplashTheme theme;

  /// False when the project switched this platform off.
  final bool enabled;

  final Resolved<String> color;
  final Resolved<String> backgroundImage;
  final Resolved<String> image;
  final Resolved<String> branding;

  /// Android 12 only; absent everywhere else.
  final Resolved<String> iconBackgroundColor;

  final SplashFit fit;
  final SplashAlignment alignment;
  final SplashAlignment brandingAlignment;
  final int brandingBottomPadding;

  /// Android and iOS only — the web splash has no status bar to hide.
  final bool fullscreen;

  /// This is the dark variant, the dark chain resolved nothing, and so the OS
  /// will show the light splash.
  ///
  /// Not an error and not a warning: for a great many apps it is the intended
  /// answer. It is reported because "dark mode shows the light splash" is
  /// otherwise indistinguishable from "the preview is broken".
  final bool fallsBackToLight;

  /// Whether anything at all was configured for this cell.
  bool get isEmpty =>
      !color.isPresent && !backgroundImage.isPresent && !image.isPresent;

  /// This light resolution, labelled as the dark cell it will be shown in.
  ///
  /// Everything keeps its light key, which is the honest answer and what the
  /// captions print: the value really did come from `color`, and that is
  /// precisely the thing the reader needs to know.
  SplashResolution _asDarkFallback() => SplashResolution(
    surface: surface,
    theme: SplashTheme.dark,
    enabled: enabled,
    color: color,
    backgroundImage: backgroundImage,
    image: image,
    branding: branding,
    iconBackgroundColor: iconBackgroundColor,
    fit: fit,
    alignment: alignment,
    brandingAlignment: brandingAlignment,
    brandingBottomPadding: brandingBottomPadding,
    fullscreen: fullscreen,
    fallsBackToLight: true,
  );

  Map<String, Object?> toJson() => {
    'surface': surface.name,
    'theme': theme.name,
    if (!enabled) 'enabled': false,
    if (color.isPresent) 'color': color.toJson(),
    if (backgroundImage.isPresent) 'backgroundImage': backgroundImage.toJson(),
    if (image.isPresent) 'image': image.toJson(),
    if (branding.isPresent) 'branding': branding.toJson(),
    if (iconBackgroundColor.isPresent)
      'iconBackgroundColor': iconBackgroundColor.toJson(),
    'fit': fit.name,
    'alignment': alignment.label,
    if (branding.isPresent) ...{
      'brandingAlignment': brandingAlignment.label,
      'brandingBottomPadding': brandingBottomPadding,
    },
    if (fullscreen) 'fullscreen': true,
    if (fallsBackToLight) 'fallsBackToLight': true,
  };

  /// The placement in words — what `fw describe` prints, and the reason the
  /// CLI never needs to render anything to answer "where does my logo go?".
  String get placementSummary {
    if (!image.isPresent) return 'no image';
    var scale = switch (fit) {
      SplashFit.none => 'at natural size (source ÷ ${sourceDensity.toInt()})',
      SplashFit.contain => 'scaled to fit',
      SplashFit.cover => 'scaled to fill, cropped',
      SplashFit.fill => 'stretched to fill',
      SplashFit.fillWidth => 'stretched horizontally',
      SplashFit.fillHeight => 'stretched vertically',
    };
    return '${alignment.label}, $scale';
  }
}

/// Resolves one cell of the matrix.
///
/// Every surface-specific rule lives here rather than in the panel, so `fw`,
/// MCP and the GUI are looking at one answer.
SplashResolution resolveSplash(
  SplashConfig config,
  SplashSurface surface,
  SplashTheme theme,
) {
  var isAndroid12 = surface == SplashSurface.android12;

  // Dark falls back to light at the **resource** level, and this is where that
  // finally happens rather than only being described.
  //
  // The config cascade really does not fall through: `color_dark` never reads
  // `color`. But the *files* the generator writes are resources, and every
  // platform resolves a missing dark one to the light one:
  //
  // - **Android** — the dark `launch_background.xml` is written with
  //   `showImage: imagePath != null`, the **light** path, so it references
  //   `@drawable/splash` whether or not a dark one exists. With no
  //   `drawable-night-*/splash.png`, Android's own resource resolution picks the
  //   non-night folder.
  // - **iOS** — `Contents.json` is `darkImagePath != null ? …Dark : …`, so with
  //   no dark image the asset catalog has no dark appearance at all and the one
  //   image serves both.
  // - **Web** — `darkImagePath ??= imagePath`, in as many words.
  //
  // Modelling this as "dark resolved nothing, so draw nothing" produced the
  // plugin's most confident and most wrong claim: that a project with
  // `color_dark` and no `image_dark` ships a dark splash with no logo on it. It
  // ships the light logo on the dark colour, which is what most people wanted.
  if (theme == SplashTheme.dark && _fallsBackToLight(config, surface)) {
    // Nothing dark is generated at all, so *every* resource resolves to the
    // light folder: this cell is the light cell. Drawing it as empty is how the
    // dark tile came to be a black rectangle underneath a caption saying the OS
    // shows the light splash.
    return resolveSplash(config, surface, SplashTheme.light)._asDarkFallback();
  }

  /// The dark value, or the light resource it resolves to when unset.
  Resolved<String> resource(String base) {
    if (theme == SplashTheme.light) return config.resolve(base, surface, theme);
    var dark = config.resolve(base, surface, theme);
    if (dark.isPresent) return dark;
    return config.resolve(base, surface, SplashTheme.light);
  }

  var color = isAndroid12
      ? config.android12Color(theme)
      : config.resolve('color', surface, theme);
  var image = isAndroid12
      // Android 12's own cascade already falls back — `android12Image(dark)`
      // reads `image_dark` then `image` — so the section needs nothing here.
      ? config.android12Image(theme)
      : resource('image');
  var branding = isAndroid12
      ? config.android12Branding(theme)
      // **Web is the exception, and it is a bug in the generator rather than a
      // choice.** `index.html` gets a `<source media="(prefers-color-scheme:
      // dark)" srcset="splash/img/branding-dark-…">` whenever the *light*
      // branding is set, and `_createWebImages(imagePath: null)` **deletes**
      // the files it points at. The browser matches that source and finds
      // nothing, so the branding is simply missing in dark mode — there is no
      // fallback to model and `validateSplash` reports it.
      : surface == SplashSurface.web
      ? config.resolve('branding', surface, theme)
      : resource('branding');

  // Android 12 draws a window background and an icon. A background image is not
  // part of that path at all, so it is not merely unused here — it is absent.
  var backgroundImage = isAndroid12
      ? const Resolved<String>.absent()
      : config.resolve('background_image', surface, theme);

  var (fit, alignment) = switch (surface) {
    // The Android 12 icon is centred and mask-fitted; `android_gravity` does
    // not reach it.
    SplashSurface.android12 => (SplashFit.contain, SplashAlignment.center),
    SplashSurface.android => parseAndroidGravity(config.androidGravity),
    SplashSurface.ios => parseIosContentMode(config.iosContentMode),
    SplashSurface.web => parseWebImageMode(config.webImageMode),
  };

  return SplashResolution(
    surface: surface,
    theme: theme,
    enabled: config.enabled(surface),
    color: color,
    backgroundImage: backgroundImage,
    image: image,
    branding: branding,
    iconBackgroundColor: isAndroid12
        ? config.android12IconBackgroundColor(theme)
        : const Resolved<String>.absent(),
    fit: fit,
    alignment: alignment,
    brandingAlignment: parseBrandingMode(config.brandingMode),
    brandingBottomPadding: config.brandingBottomPadding(surface),
    // Web has no status bar; Android 12's splash is drawn by the system and
    // ignores the flag.
    fullscreen:
        config.fullscreen &&
        (surface == SplashSurface.android || surface == SplashSurface.ios),
    // The whole-theme case returned early above; anything reaching here has
    // dark resources of its own.
    fallsBackToLight: false,
  );
}

/// Whether the dark chain resolves nothing at all, so the generator writes no
/// dark resources and the OS shows the light splash.
///
/// Not "is any dark key set" — it is specifically the keys that make the
/// generator write a `-night` folder. For Android 12 the colour always resolves
/// (it ends at the top-level `color`), so it cannot be part of the test.
bool _fallsBackToLight(SplashConfig config, SplashSurface surface) {
  const dark = SplashTheme.dark;
  return !config.resolve('color', surface, dark).isPresent &&
      !config.resolve('image', surface, dark).isPresent &&
      !config.resolve('background_image', surface, dark).isPresent &&
      (surface != SplashSurface.android12 ||
          !config.android12Image(dark).isPresent);
}
