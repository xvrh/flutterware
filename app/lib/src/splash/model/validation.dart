/// What is wrong with a splash config, and how wrong.
///
/// Every rule here is checked against the generator's own source rather than
/// its README, and the two disagree often enough to matter. Two rules were
/// nearly written the other way round from what the package actually does:
///
/// - **A non-PNG source is fine.** The README's "PNG" reads like a
///   requirement; `_checkImageExists` accepts jpg, gif, bmp, tga and more, and
///   `_createImage` converts anything that is not already a PNG. So this
///   reports a conversion, not an error.
/// - **An unknown key is fatal.** It is not ignored and not warned about — the
///   generator prints and calls `exit(1)`, so one typo stops the whole run.
///
/// [SplashProblem.blocksGeneration] marks the rules that stop `create` dead, so
/// a reader can tell "this will not build" from "this will look wrong".
library;

import 'package:flutterware/plugins.dart';

import 'color.dart';
import 'config.dart';
import 'image_facts.dart';
import 'surface.dart';

/// Every key the generator accepts, transcribed from `_Parameter.all`.
///
/// Kept as a literal rather than derived, because it is the *other* project's
/// list: deriving it from what this plugin happens to read would make the
/// unknown-key check silently agree with itself.
const splashKnownKeys = {
  'android',
  'android_12',
  'android_min_sdk',
  'android_screen_orientation',
  'background_image',
  'background_image_android',
  'background_image_ios',
  'background_image_web',
  'background_image_dark',
  'background_image_dark_android',
  'background_image_dark_ios',
  'background_image_dark_web',
  'branding',
  'branding_android',
  'branding_ios',
  'branding_web',
  'branding_dark',
  'branding_dark_android',
  'branding_dark_ios',
  'branding_dark_web',
  'branding_mode',
  'branding_bottom_padding',
  'branding_bottom_padding_android',
  'branding_bottom_padding_ios',
  'color',
  'color_android',
  'color_ios',
  'color_web',
  'color_dark',
  'color_dark_android',
  'color_dark_ios',
  'color_dark_web',
  'image',
  'image_android',
  'image_ios',
  'image_web',
  'image_dark',
  'image_dark_android',
  'image_dark_ios',
  'image_dark_web',
  'fullscreen',
  'android_gravity',
  'icon_background_color',
  'icon_background_color_dark',
  'ios',
  'ios_content_mode',
  'info_plist_files',
  'web',
  'web_image_mode',
};

/// The keys the `android_12:` section accepts.
const splashAndroid12Keys = {
  'color',
  'color_dark',
  'image',
  'image_dark',
  'icon_background_color',
  'icon_background_color_dark',
  'branding',
  'branding_dark',
};

/// Formats the generator converts to PNG on the way in.
const splashConvertibleFormats = {
  'png',
  'apng',
  'jpg',
  'jpeg',
  'jpe',
  'jfif',
  'tga',
  'tpic',
  'gif',
  'ico',
  'bmp',
  'dib',
};

/// One thing wrong with a config.
class SplashProblem {
  const SplashProblem(
    this.tone,
    this.message, {
    this.key,
    this.surface,
    this.theme,
    this.blocksGeneration = false,
  });

  final Tone tone;
  final String message;

  /// The config key at fault, when one key is.
  final String? key;

  /// The cell this is about, when it is about one cell rather than the config.
  final SplashSurface? surface;
  final SplashTheme? theme;

  /// `dart run flutter_native_splash:create` will `exit(1)` on this.
  final bool blocksGeneration;

  Map<String, Object?> toJson() => {
    'tone': tone.name,
    'message': message,
    if (key != null) 'key': key,
    if (surface != null) 'surface': surface!.name,
    if (theme != null) 'theme': theme!.name,
    if (blocksGeneration) 'blocksGeneration': true,
  };

  @override
  String toString() => message;
}

/// Checks [config] and returns everything wrong with it, worst first.
///
/// [facts] is looked up by the path the config wrote. [hasDevDependency] and
/// [generatedIsStale] are supplied by the core, which is the only thing that
/// can see the pubspec and the generated files.
List<SplashProblem> validateSplash(
  SplashConfig config, {
  required SplashImageFacts? Function(String path) facts,
  bool hasDevDependency = true,
  bool generatedIsStale = false,
}) {
  var problems = <SplashProblem>[];

  // ---- Fatal: the generator refuses to run -------------------------------

  for (var key in config.raw.keys) {
    if (!splashKnownKeys.contains(key)) {
      problems.add(
        SplashProblem(
          Tone.error,
          '"$key" is not a flutter_native_splash parameter. The generator '
          'prints this and exits, so nothing is written at all.',
          key: key,
          blocksGeneration: true,
        ),
      );
    }
  }
  for (var key in config.android12Section.keys) {
    if (!splashAndroid12Keys.contains(key)) {
      problems.add(
        SplashProblem(
          Tone.error,
          '"$key" is not valid inside android_12.',
          key: 'android_12.$key',
          blocksGeneration: true,
        ),
      );
    }
  }

  // Colours and images are checked over every key the project actually wrote,
  // not over the resolved cells: a broken `color_ios` stops the run even when
  // some other surface resolves fine without it.
  config.raw.forEach((key, value) {
    if (!_isColorKey(key)) return;
    var text = SplashConfig.stringify(value);
    if (text != null && parseSplashColor(text) == null) {
      problems.add(
        SplashProblem(
          Tone.error,
          '"$key: $text" is not a colour the generator accepts — it wants '
          'exactly six hex digits, like "1E1E1E". It throws on anything else, '
          'including eight-digit values with alpha.',
          key: key,
          blocksGeneration: true,
        ),
      );
    }
  });
  config.android12Section.forEach((key, value) {
    if (!_isColorKey(key)) return;
    var text = SplashConfig.stringify(value);
    if (text != null && parseSplashColor(text) == null) {
      problems.add(
        SplashProblem(
          Tone.error,
          '"android_12.$key: $text" is not a six-digit hex colour.',
          key: 'android_12.$key',
          blocksGeneration: true,
        ),
      );
    }
  });

  for (var (key, path) in _referencedImages(config)) {
    var known = facts(path);
    if (known == null || !known.exists) {
      problems.add(
        SplashProblem(
          Tone.error,
          'The file "$path" set as "$key" was not found. The generator exits '
          'rather than skipping it.',
          key: key,
          blocksGeneration: true,
        ),
      );
      continue;
    }
    var extension = _extension(path);
    if (!splashConvertibleFormats.contains(extension)) {
      problems.add(
        SplashProblem(
          Tone.error,
          '"$path" is a .$extension, which the generator cannot decode.',
          key: key,
          blocksGeneration: true,
        ),
      );
    } else if (extension != 'png' && extension != 'apng') {
      problems.add(
        SplashProblem(
          Tone.info,
          '"$path" is a .$extension — the generator converts it to PNG. Any '
          'transparency the format does not carry is already gone by then.',
          key: key,
        ),
      );
    }
  }

  // ---- The Android 12 divergence ----------------------------------------

  var hasLegacyArt =
      config
          .resolve('image', SplashSurface.android, SplashTheme.light)
          .isPresent ||
      config
          .resolve('background_image', SplashSurface.android, SplashTheme.light)
          .isPresent;

  if (config.enabled(SplashSurface.android) &&
      hasLegacyArt &&
      !config.android12Image(SplashTheme.light).isPresent) {
    problems.add(
      SplashProblem(
        Tone.warn,
        config.hasAndroid12Section
            ? 'The android_12 section sets no "image", so every device from '
                  'Android 12 on shows a bare colour. The top-level "image" '
                  'does not reach this surface.'
            : 'There is no android_12 section, so every device from Android 12 '
                  'on shows a bare colour. The top-level "image" is read only '
                  'by the legacy path.',
        key: 'android_12.image',
        surface: SplashSurface.android12,
      ),
    );
  }

  var iconBackground = config.android12IconBackgroundColor(SplashTheme.light);
  var expectedIcon = android12IconSize(
    hasIconBackground: iconBackground.isPresent,
  );
  for (var theme in SplashTheme.values) {
    var icon = config.android12Image(theme);
    if (!icon.isPresent) continue;
    var known = facts(icon.value!);
    if (known == null || !known.isMeasured) continue;
    if (known.pixelWidth != expectedIcon || known.pixelHeight != expectedIcon) {
      problems.add(
        SplashProblem(
          Tone.warn,
          'The Android 12 icon "${icon.value}" is ${known.dimensions}; it '
          'should be $expectedIcon×$expectedIcon '
          '${iconBackground.isPresent ? 'with' : 'without'} an icon '
          'background. Android masks it to a circle at '
          '${(android12MaskFraction * 100).round()}% of the canvas, so a '
          'wrong canvas crops the logo rather than scaling it.',
          key: icon.key,
          surface: SplashSurface.android12,
          theme: theme,
        ),
      );
      break;
    }
  }

  for (var theme in SplashTheme.values) {
    var branding = config.android12Branding(theme);
    if (!branding.isPresent) continue;
    var known = facts(branding.value!);
    if (known == null || !known.isMeasured) continue;
    if (known.pixelWidth != android12BrandingWidth ||
        known.pixelHeight != android12BrandingHeight) {
      problems.add(
        SplashProblem(
          Tone.warn,
          'The Android 12 branding "${branding.value}" is '
          '${known.dimensions}; it should be '
          '$android12BrandingWidth×$android12BrandingHeight.',
          key: branding.key,
          surface: SplashSurface.android12,
          theme: theme,
        ),
      );
      break;
    }
  }

  // ---- Per-surface completeness -----------------------------------------

  for (var surface in SplashSurface.values) {
    if (!config.enabled(surface)) continue;
    var light = resolveSplash(config, surface, SplashTheme.light);
    if (light.isEmpty) {
      problems.add(
        SplashProblem(
          Tone.warn,
          'Nothing resolves for ${surface.label}: no colour and no background '
          'image, so the splash is whatever the platform defaults to.',
          surface: surface,
        ),
      );
    }

    var dark = resolveSplash(config, surface, SplashTheme.dark);
    if (dark.fallsBackToLight) {
      problems.add(
        SplashProblem(
          Tone.info,
          'No dark configuration for ${surface.label}. The dark keys are a '
          'chain of their own — "_dark_${surface.keySuffix}" then "_dark", '
          'never falling through to the light keys — so no dark resources are '
          'generated and the OS shows the light splash in dark mode.',
          surface: surface,
          theme: SplashTheme.dark,
        ),
      );
    } else if (light.image.isPresent && !dark.image.isPresent) {
      // The nastier half of the same rule, and the more common one. Setting
      // `color_dark` alone is enough to make dark resources real — so dark mode
      // stops falling back to the light splash and starts showing the dark
      // colour with **no logo on it**. It looks deliberate, which is why nobody
      // catches it until a screenshot arrives.
      var key = surface == SplashSurface.android12
          ? 'android_12.image_dark'
          : 'image_dark';
      problems.add(
        SplashProblem(
          Tone.warn,
          'The dark ${surface.label} splash has a background but no image. '
          'A dark colour is enough to make dark resources real, so this will '
          'not fall back to the light splash — it will show an empty '
          'background. Set "$key".',
          key: key,
          surface: surface,
          theme: SplashTheme.dark,
        ),
      );
    }
  }

  // ---- Placement vocabularies -------------------------------------------

  _checkVocabulary(
    problems,
    'android_gravity',
    config.androidGravity,
    androidGravityValues,
    separator: '|',
  );
  _checkVocabulary(
    problems,
    'ios_content_mode',
    config.iosContentMode,
    iosContentModeValues,
  );
  _checkVocabulary(
    problems,
    'web_image_mode',
    config.webImageMode,
    webImageModeValues,
  );
  _checkVocabulary(
    problems,
    'branding_mode',
    config.brandingMode,
    brandingModeValues,
  );

  // ---- Project state -----------------------------------------------------

  if (!hasDevDependency) {
    problems.add(
      const SplashProblem(
        Tone.warn,
        'flutter_native_splash is not in dev_dependencies, so '
        '`dart run flutter_native_splash:create` will not resolve.',
      ),
    );
  }

  if (generatedIsStale) {
    problems.add(
      const SplashProblem(
        Tone.info,
        'The config has changed since the splash was last generated. What ships '
        'is still the old one until `create` runs again.',
      ),
    );
  }

  problems.sort((a, b) => _severity(b.tone).compareTo(_severity(a.tone)));
  return problems;
}

/// Flags a value that is not in its vocabulary. The generator does not check
/// these — it silently falls back to its default — so a typo here is invisible
/// until someone looks at a device.
void _checkVocabulary(
  List<SplashProblem> problems,
  String key,
  String? value,
  List<String> legal, {
  String? separator,
}) {
  if (value == null || value.trim().isEmpty) return;
  var parts = separator == null ? [value.trim()] : value.split(separator);
  for (var part in parts) {
    var token = part.trim();
    if (token.isEmpty || legal.contains(token)) continue;
    problems.add(
      SplashProblem(
        Tone.warn,
        '"$key: $value" uses "$token", which is not one of '
        '${legal.join(', ')}. The generator does not validate this — it just '
        'falls back to its default.',
        key: key,
      ),
    );
  }
}

/// Every image path the config names, with the key that named it.
List<(String, String)> _referencedImages(SplashConfig config) {
  var found = <(String, String)>[];
  for (var base in ['image', 'background_image', 'branding']) {
    for (var key in [
      base,
      '${base}_dark',
      for (var suffix in ['android', 'ios', 'web']) ...[
        '${base}_$suffix',
        '${base}_dark_$suffix',
      ],
    ]) {
      var value = SplashConfig.stringify(config.raw[key]);
      if (value != null) found.add((key, value));
    }
  }
  for (var key in ['image', 'image_dark', 'branding', 'branding_dark']) {
    var value = SplashConfig.stringify(config.android12Section[key]);
    if (value != null) found.add(('android_12.$key', value));
  }
  return found;
}

bool _isColorKey(String key) =>
    key.startsWith('color') || key.startsWith('icon_background_color');

String _extension(String path) {
  var dot = path.lastIndexOf('.');
  return dot < 0 ? '' : path.substring(dot + 1).toLowerCase();
}

int _severity(Tone tone) => switch (tone) {
  Tone.error => 3,
  Tone.warn => 2,
  Tone.info => 1,
  Tone.good || Tone.neutral => 0,
};
