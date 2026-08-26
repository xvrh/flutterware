import 'package:flutterware/src/flutter_gpu_diagnosis.dart';
import 'package:test/test.dart';

/// The engine is accurate about Flutter GPU and unhelpful about it: two of its
/// three messages name a flag without naming who should have passed it, and
/// the third — the one a real project actually hits — is
/// `Failed to initialize ShaderLibrary:` with nothing after the colon. A test
/// process can read its own engine flags, so it can finish the sentence.
void main() {
  const impeller = '--enable-impeller';
  const flutterGpu = '--enable-flutter-gpu';
  const metal = '--impeller-backend=metal';

  const noContext =
      'Exception: Flutter GPU requires the Impeller rendering backend, but '
      'Impeller is not enabled.';
  const noGpu =
      'Exception: Flutter GPU must be enabled via the Flutter GPU '
      'manifest setting.';
  const noShaders = 'Exception: Failed to initialize ShaderLibrary: ';

  group('reading the flags', () {
    test('finds all three', () {
      var flags = readRasterizerFlags([impeller, metal, flutterGpu]);
      expect(flags.impeller, isTrue);
      expect(flags.flutterGpu, isTrue);
      expect(flags.backend, 'metal');
    });

    test('an absent backend is null, not empty', () {
      expect(readRasterizerFlags([impeller, flutterGpu]).backend, isNull);
    });

    test('the macOS embedder spells it with =true', () {
      // `FlutterEngine.mm` pushes `--enable-flutter-gpu=true` rather than the
      // bare switch, and the engine's own parser takes either.
      expect(
        readRasterizerFlags(['--enable-flutter-gpu=true']).flutterGpu,
        isTrue,
      );
    });

    test('nothing named is three falsehoods', () {
      var flags = readRasterizerFlags(const ['--non-interactive']);
      expect(flags.impeller, isFalse);
      expect(flags.flutterGpu, isFalse);
      expect(flags.backend, isNull);
    });
  });

  group('what counts as a Flutter GPU failure', () {
    test("the engine's three", () {
      expect(isFlutterGpuFailure(noContext), isTrue);
      expect(isFlutterGpuFailure(noGpu), isTrue);
      expect(isFlutterGpuFailure(noShaders), isTrue);
    });

    test('the fragment-shader stage mismatch too', () {
      expect(
        isFlutterGpuFailure(
          "Asset 'shaders/x.frag' does not contain appropriate runtime stage "
          'data for current backend (Metal).',
        ),
        isTrue,
      );
    });

    test(
      'and nothing else — a sentence on the wrong failure costs a minute',
      () {
        expect(
          isFlutterGpuFailure('A RenderFlex overflowed by 476 pixels'),
          isFalse,
        );
        expect(isFlutterGpuFailure('A Timer is still pending'), isFalse);
        expect(
          withFlutterGpuDiagnosis(
            'A RenderFlex overflowed by 476 pixels',
            executableArguments: const [],
            macOS: true,
          ),
          'A RenderFlex overflowed by 476 pixels',
        );
      },
    );
  });

  group('the diagnosis', () {
    String? note(List<String> args, {bool macOS = true}) =>
        flutterGpuDiagnosis(noShaders, executableArguments: args, macOS: macOS);

    test('no Impeller at all names both lanes it could be', () {
      var said = note(const []);
      expect(said, contains('software rasterizer'));
      expect(said, contains('FW_SOFTWARE_RENDERING'));
    });

    test('Impeller without Flutter GPU says the engine wants both', () {
      var said = note(const [impeller]);
      expect(said, contains('--enable-flutter-gpu'));
      expect(said, contains('one without the other'));
    });

    test('the one that actually bites: no backend named, on macOS', () {
      var said = note(const [impeller, flutterGpu]);
      expect(said, contains('Vulkan'));
      expect(said, contains('build hook'));
      expect(said, contains('Metal'));
      // The way out, not just the cause.
      expect(said, contains('--impeller-backend'));
      expect(said, contains('flutterware'));
    });

    test(
      'off macOS the default is what the hook targeted, so nothing is said',
      () {
        // Linux and Windows hooks emit SPIR-V and GLES, which is what the
        // tester's Vulkan default reads — measured on both runners.
        expect(note(const [impeller, flutterGpu], macOS: false), isNull);
      },
    );

    test('a named backend points at the bundle instead of the flags', () {
      var said = note(const [impeller, flutterGpu, metal]);
      expect(said, contains('metal'));
      expect(said, contains('build hook'));
      expect(said, isNot(contains('--impeller-backend=')));
    });

    test('the note is appended, never a replacement', () {
      var full = withFlutterGpuDiagnosis(
        noShaders,
        executableArguments: const [impeller, flutterGpu],
        macOS: true,
      );
      expect(full, startsWith(noShaders));
      expect(full.length, greaterThan(noShaders.length));
    });
  });
}
