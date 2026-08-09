import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware/plugins.dart';
import 'package:flutterware_app/src/splash/model/config.dart';
import 'package:flutterware_app/src/splash/model/image_facts.dart';
import 'package:flutterware_app/src/splash/model/surface.dart';
import 'package:flutterware_app/src/splash/model/validation.dart';
import 'package:flutterware_app/src/splash/model/writer.dart';
import 'package:yaml/yaml.dart';

/// The repairs, and — at least as important — the problems that deliberately
/// have none.
///
/// Each fix is asserted twice: once as data (the keys it writes), and once by
/// putting it through [editSplashConfig] and checking the config it produces no
/// longer has the problem. A fix that looks right and does not actually clear
/// the warning is the failure mode that makes people stop pressing the button.
void main() {
  SplashConfig config(Map<String, Object?> raw) => SplashConfig(
    raw: raw,
    kind: SplashConfigKind.file,
    path: 'flutter_native_splash.yaml',
  );

  /// Every referenced image exists and is 1024×1024 — the fit and size rules are
  /// not what these tests are about.
  SplashImageFacts? facts(String path) => SplashImageFacts(
    path: path,
    exists: true,
    pixelWidth: 1024,
    pixelHeight: 1024,
  );

  List<SplashProblem> check(Map<String, Object?> raw) =>
      validateSplash(config(raw), facts: facts);

  SplashFix? fixFor(Map<String, Object?> raw, String id) {
    for (var problem in check(raw)) {
      if (problem.fix?.id == id) return problem.fix;
    }
    return null;
  }

  /// The config as it is after [fix] runs, decoded.
  Map<String, Object?> applied(Map<String, Object?> raw, SplashFix fix) {
    var source = StringBuffer('flutter_native_splash:\n');
    for (var entry in raw.entries) {
      if (entry.value is Map) {
        source.writeln('  ${entry.key}:');
        for (var nested in (entry.value! as Map).entries) {
          source.writeln('    ${nested.key}: "${nested.value}"');
        }
      } else {
        source.writeln('  ${entry.key}: "${entry.value}"');
      }
    }
    var edited = editSplashConfig('$source', fix.writes);
    var section = (loadYaml(edited) as Map)['flutter_native_splash'] as Map;
    return {
      for (var entry in section.entries)
        '${entry.key}': entry.value is Map
            ? {for (var n in (entry.value as Map).entries) '${n.key}': n.value}
            : entry.value,
    };
  }

  group('a misspelled key', () {
    test('is renamed, carrying its value', () {
      var raw = {'color': 'FFFFFF', 'color_darkk': '101418'};
      var fix = fixFor(raw, 'rename:color_darkk')!;

      expect(fix.label, 'Rename to "color_dark"');
      expect(
        [for (var write in fix.writes) '${write.key}=${write.value}'],
        ['color_darkk=null', 'color_dark=101418'],
      );

      var after = applied(raw, fix);
      expect(after.containsKey('color_darkk'), isFalse);
      expect(after['color_dark'], '101418');
      // And the config is now clean of the thing that stopped generation.
      expect(check(after).where((p) => p.blocksGeneration), isEmpty);
    });

    test('says the suggestion in the message, not only on the button', () {
      var problems = check({'colour': 'FFFFFF'});
      expect(problems.first.message, contains('Did you mean "color"?'));
    });

    test('is not renamed when nothing is close', () {
      expect(
        fixFor({'splashy_thing': 'FFFFFF'}, 'rename:splashy_thing'),
        isNull,
      );
    });

    test('is not renamed onto a key the config already uses', () {
      // `color_dark` is already set on purpose; renaming onto it would throw it
      // away in the name of fixing something.
      var raw = {'color_dark': '101418', 'color_darkk': '000000'};
      expect(fixFor(raw, 'rename:color_darkk'), isNull);
    });

    test('works inside the android_12 section too', () {
      var raw = {
        'android_12': {'imagee': 'assets/logo.png'},
      };
      var fix = fixFor(raw, 'rename:android_12.imagee')!;
      expect(
        [for (var write in fix.writes) write.key],
        ['android_12.imagee', 'android_12.image'],
      );

      var after = applied(raw, fix);
      expect((after['android_12']! as Map)['image'], 'assets/logo.png');
    });
  });

  group('a colour that is not six digits', () {
    test('is expanded when it is three-digit shorthand', () {
      var raw = {'color': '#fff'};
      var fix = fixFor(raw, 'color:color')!;
      expect(fix.label, 'Write "#fff" as FFFFFF');

      var after = applied(raw, fix);
      expect(after['color'], 'FFFFFF');
      expect(check(after).where((p) => p.blocksGeneration), isEmpty);
    });

    test('is left alone when it has eight digits', () {
      // FF at the front and FF at the back: ARGB says AABBCC, RGBA says FFAABB.
      // There is no way to know, so there is no button.
      expect(fixFor({'color': 'FFAABBCC'}, 'color:color'), isNull);
      expect(check({'color': 'FFAABBCC'}).first.blocksGeneration, isTrue);
    });

    test('is left alone when it is not hex at all', () {
      expect(fixFor({'color': 'red'}, 'color:color'), isNull);
    });
  });

  group('a dark splash with no image of its own', () {
    var raw = {
      'color': 'FFFFFF',
      'color_dark': '101418',
      'image': 'assets/logo.png',
    };

    test('gets no fix, because there is nothing to repair', () {
      // This used to be a `warn` with a button that wrote `image_dark` to the
      // file the config already falls back to — a no-op sold as a repair. The
      // rule behind it claimed the dark splash would "show an empty
      // background", which is the opposite of what every platform does.
      expect(fixFor(raw, 'dark-image:android'), isNull);
      expect(
        check(raw).where((p) => p.message.contains('empty background')),
        isEmpty,
      );
    });

    test('is an info saying which image will actually be drawn', () {
      var note = check(raw).firstWhere(
        (p) =>
            p.theme == SplashTheme.dark && p.surface == SplashSurface.android,
      );
      expect(note.tone, Tone.info);
      expect(note.message, contains('uses the light image'));
      expect(note.message, contains('assets/logo.png'));
      expect(note.fix, isNull);
    });

    test('cannot arise for Android 12 at all', () {
      // `android12Image(dark)` falls back to `android_12.image`, so a dark
      // Android 12 cell is never missing an image its light twin has. The rule
      // that used to special-case this surface was checking for something the
      // cascade makes impossible.
      var problems = check({
        'color': 'FFFFFF',
        'color_dark': '101418',
        'android_12': {'image': 'assets/android12.png'},
      });
      expect(
        problems.where(
          (p) =>
              p.surface?.name == 'android12' &&
              p.message.contains('but no image'),
        ),
        isEmpty,
      );
    });

    test('web branding is the one case that really does break', () {
      // And the old rule hid it: the image branch fired first and talked about
      // images. `index.html` gets a dark `<source>` pointing at
      // `branding-dark-*` whenever the light branding is set, and
      // `_createWebImages(imagePath: null)` deletes exactly those files.
      var withBranding = {
        'color': 'FFFFFF',
        'color_dark': '101418',
        'branding': 'assets/brand.png',
      };
      var fix = fixFor(withBranding, 'web-branding-dark')!;
      expect(fix.writes.single.key, 'branding_dark');
      expect(fix.writes.single.value, 'assets/brand.png');

      var problem = check(
        withBranding,
      ).firstWhere((p) => p.key == 'branding_dark');
      expect(problem.tone, Tone.warn);
      expect(problem.surface, SplashSurface.web);

      // Android and iOS resolve the missing dark drawable to the light one, so
      // they get no such warning.
      expect(
        check(withBranding).where(
          (p) => p.key == 'branding_dark' && p.surface != SplashSurface.web,
        ),
        isEmpty,
      );

      var after = applied(withBranding, fix);
      expect(check(after).where((p) => p.key == 'branding_dark'), isEmpty);
    });
  });

  group('branding under the home indicator', () {
    var raw = {'color': 'FFFFFF', 'branding': 'assets/brand.png'};

    test('writes the platform key, not the global one', () {
      var ios = fixFor(raw, 'branding-padding:ios')!;
      expect(ios.writes.single.key, 'branding_bottom_padding_ios');
      expect(ios.writes.single.value, isA<int>());

      var android = fixFor(raw, 'branding-padding:android')!;
      expect(android.writes.single.key, 'branding_bottom_padding_android');
      // Two platforms, two insets — which is the whole reason the global key is
      // the wrong one to write.
      expect(android.writes.single.value, isNot(ios.writes.single.value));
    });

    test('clears the warning it came from', () {
      var fix = fixFor(raw, 'branding-padding:ios')!;
      var after = applied(raw, fix);
      expect(
        check(after).where(
          (p) =>
              p.key == 'branding_bottom_padding_ios' &&
              p.message.contains('safe area'),
        ),
        isEmpty,
      );
    });

    test('is not offered for Android 12, which has no such key', () {
      // `_applyStylesXml` for the v31 templates takes no padding — the system
      // places `windowSplashScreenBrandingImage` itself.
      expect(fixFor(raw, 'branding-padding:android12'), isNull);
      expect(
        check(raw).where(
          (p) =>
              p.surface?.name == 'android12' && p.message.contains('safe area'),
        ),
        isEmpty,
      );
    });
  });

  group('a placement value that is not in its vocabulary', () {
    test('is corrected to the nearest legal one', () {
      var raw = {'color': 'FFFFFF', 'ios_content_mode': 'scaleAspectFt'};
      var fix = fixFor(raw, 'vocabulary:ios_content_mode:scaleAspectFt')!;
      expect(fix.writes.single.value, 'scaleAspectFit');

      var after = applied(raw, fix);
      expect(check(after).where((p) => p.key == 'ios_content_mode'), isEmpty);
    });

    test('is left alone when two legal values are equally close', () {
      // `scaleAspectFil` is one edit from `scaleAspectFit` and one from
      // `scaleAspectFill`. This is the tie the suggestion guard exists for, and
      // it is a real one rather than a contrived one — the two legal values
      // themselves are only two edits apart.
      var raw = {'color': 'FFFFFF', 'ios_content_mode': 'scaleAspectFil'};
      expect(fixFor(raw, 'vocabulary:ios_content_mode:scaleAspectFil'), isNull);
      var problem = check(raw).firstWhere((p) => p.key == 'ios_content_mode');
      expect(problem.message, isNot(contains('Did you mean')));
    });

    test('replaces only the bad token of a compound gravity', () {
      var raw = {'color': 'FFFFFF', 'android_gravity': 'bottom|rihgt'};
      var fix = fixFor(raw, 'vocabulary:android_gravity:rihgt')!;
      expect(fix.writes.single.value, 'bottom|right');
    });
  });

  group('problems with no fix', () {
    test('a missing file has none — we cannot invent the image', () {
      var problems = validateSplash(
        config({'color': 'FFFFFF', 'image': 'assets/gone.png'}),
        facts: (path) => SplashImageFacts.missing(path),
      );
      expect(problems.first.message, contains('was not found'));
      expect(problems.first.fix, isNull);
    });

    test(
      'no dark configuration at all has none — the colour is a decision',
      () {
        var problems = check({'color': 'FFFFFF'});
        var dark = problems.firstWhere(
          (p) => p.message.contains('No dark configuration'),
        );
        // Writing `color_dark: FFFFFF` would make dark resources real and
        // identical to light: more files, same picture, and a config that now
        // claims to have been thought about.
        expect(dark.fix, isNull);
      },
    );

    test('the missing dev_dependency has none', () {
      var problems = validateSplash(
        config({'color': 'FFFFFF'}),
        facts: facts,
        hasDevDependency: false,
      );
      var missing = problems.firstWhere(
        (p) => p.message.contains('dev_dependencies'),
      );
      // A version constraint transcribed here would go stale the week after;
      // `dart pub add dev:flutter_native_splash` gets it from pub.
      expect(missing.fix, isNull);
    });
  });
}
