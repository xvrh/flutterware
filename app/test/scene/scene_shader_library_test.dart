// What the inspector reads before it can draw a control per uniform: the
// package's declared shaders, and what each one's compiler reflection and
// its own `// @...` comments say about each uniform.
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware_app/src/embedder/flutter_cache.dart';
import 'package:flutterware_app/src/previews/project_shaders.dart';
import 'package:flutterware_app/src/scene/shader_library.dart';
import 'package:flutterware_app/src/utils/run_dir.dart';
import 'package:path/path.dart' as p;

const reflection = '''
{"uniforms": [
  {"name": "uSize", "location": 0, "type": {"type_name": "ShaderType::kFloat", "vec_size": 2, "columns": 1}},
  {"name": "uAngle", "location": 3, "type": {"type_name": "ShaderType::kFloat", "vec_size": 1, "columns": 1}},
  {"name": "uTime", "location": 1, "type": {"type_name": "ShaderType::kFloat", "vec_size": 1, "columns": 1}},
  {"name": "uShine", "location": 2, "type": {"type_name": "ShaderType::kFloat", "vec_size": 3, "columns": 1}}
], "sampled_images": []}''';

const source = '''
uniform vec2 uSize;
uniform float uTime;
uniform vec3 uShine; // @color @default 1 0.85 0.4
uniform float uAngle; // @range 0 6.283 @default 0.6
''';

void main() {
  late Directory root;
  setUp(() => root = Directory.systemTemp.createTempSync('fw_shader_library'));
  tearDown(() => root.deleteSync(recursive: true));

  String write(String relative, String content) {
    var file = File(p.join(root.path, relative))..createSync(recursive: true);
    file.writeAsStringSync(content);
    return file.path;
  }

  group('readShaderUniforms', () {
    test('uniforms come in declaration order, with what the comments add', () {
      var u = readShaderUniforms(reflection, source);
      expect(u.map((x) => x.name), ['uSize', 'uTime', 'uShine', 'uAngle']);
      expect(u[2].isColor, isTrue);
      expect(u[2].defaults, [1, 0.85, 0.4]);
      expect(u[3].range, (0, 6.283));
      expect(u[3].defaults, [0.6]);
      expect(u[0].rendererOwned, isTrue);
      expect(u[3].rendererOwned, isFalse);
    });

    test('a tag that does not fit is ignored', () {
      var u = readShaderUniforms(
        reflection,
        'uniform float uAngle; // @range zero six @default 1 2\n'
        'uniform vec2 uSize; // @color',
      );
      var angle = u.firstWhere((x) => x.name == 'uAngle');
      expect(angle.range, isNull);
      expect(angle.defaults, isNull);
      expect(u.firstWhere((x) => x.name == 'uSize').isColor, isFalse);
    });

    test('unreadable reflection is no uniforms, not a throw', () {
      expect(readShaderUniforms('not json', source), isEmpty);
      expect(readShaderUniforms('{"uniforms": 3}', source), isEmpty);
    });

    test('a declared-but-unused uniform is kept', () {
      var u = readShaderUniforms(reflection, '');
      expect(u.map((x) => x.name), ['uSize', 'uTime', 'uShine', 'uAngle']);
      expect(u.every((x) => x.range == null && x.defaults == null), isTrue);
    });

    test('a non-float or a matrix uniform is left out', () {
      var withSampler = '''
{"uniforms": [
  {"name": "uSize", "location": 0, "type": {"type_name": "ShaderType::kFloat", "vec_size": 2, "columns": 1}},
  {"name": "uMatrix", "location": 1, "type": {"type_name": "ShaderType::kFloat", "vec_size": 4, "columns": 4}},
  {"name": "uWide", "location": 2, "type": {"type_name": "ShaderType::kFloat", "vec_size": 5, "columns": 1}},
  {"name": "uOther", "location": 3, "type": {"type_name": "ShaderType::kInt", "vec_size": 1, "columns": 1}}
], "sampled_images": []}''';
      var u = readShaderUniforms(withSampler, source);
      expect(u.map((x) => x.name), ['uSize']);
    });
  });

  group('declaredShaders', () {
    test("the declared shaders are the pubspec's, in order", () {
      write('pubspec.yaml', '''
name: project
flutter:
  shaders:
    - shaders/b.frag
    - shaders/a.frag
''');
      expect(declaredShaders(root.path), ['shaders/b.frag', 'shaders/a.frag']);
    });

    test('no shaders declared is an empty list', () {
      write('pubspec.yaml', 'name: project\n');
      expect(declaredShaders(root.path), isEmpty);
    });

    test('a non-string entry is dropped, the rest kept in order', () {
      write('pubspec.yaml', '''
name: project
flutter:
  shaders:
    - shaders/a.frag
    - 7
    - shaders/b.frag
''');
      expect(declaredShaders(root.path), ['shaders/a.frag', 'shaders/b.frag']);
    });

    test('an unreadable pubspec is an empty list, not a throw', () {
      expect(declaredShaders(p.join(root.path, 'nowhere')), isEmpty);
    });

    test('an unparsable pubspec is an empty list, not a throw', () {
      write('pubspec.yaml', 'not: [valid: yaml');
      expect(declaredShaders(root.path), isEmpty);
    });
  });

  group('SceneShaderLibrary', () {
    setUp(() {
      write('shaders/a.frag', source);
    });

    test('info is null while compiling, then lands and notifies', () async {
      var reflectionFile = write('cache/reflection.json', reflection);
      var gate = Completer<CompiledShader>();
      var library = SceneShaderLibrary(
        cache: null,
        compile: (_) => gate.future,
      );
      var shaders = library.forPackage(root.path);
      var heard = 0;
      shaders.addListener(() => heard++);
      expect(shaders.info('shaders/a.frag'), isNull);
      gate.complete(
        CompiledShader(binary: reflectionFile, reflection: reflectionFile),
      );
      await pumpEventQueue();
      expect(shaders.info('shaders/a.frag')!.uniforms, hasLength(4));
      expect(heard, 1);
    });

    test('a shader that does not compile says why', () async {
      var library = SceneShaderLibrary(
        cache: null,
        compile: (_) => Future.error(
          StateError('impellerc failed on shaders/a.frag:\nsyntax error'),
        ),
      );
      var shaders = library.forPackage(root.path);
      expect(shaders.info('shaders/a.frag'), isNull);
      await pumpEventQueue();
      var info = shaders.info('shaders/a.frag')!;
      expect(info.error, isNotNull);
      expect(info.error, contains('syntax error'));
      expect(info.uniforms, isEmpty);
    });

    test('a missing source says so, with no compile attempted', () {
      var library = SceneShaderLibrary(
        cache: null,
        compile: (_) => throw StateError('should not be called'),
      );
      var shaders = library.forPackage(root.path);
      var info = shaders.info('shaders/missing.frag');
      expect(info?.error, "'shaders/missing.frag' is not on disk");
    });

    test('no Flutter SDK and no override says why', () async {
      var library = SceneShaderLibrary(cache: null);
      var shaders = library.forPackage(root.path);
      expect(shaders.info('shaders/a.frag'), isNull);
      await pumpEventQueue();
      expect(
        shaders.info('shaders/a.frag')!.error,
        'no Flutter SDK to compile with',
      );
    });

    test('a hit returns at once, without compiling again', () async {
      var reflectionFile = write('cache/reflection.json', reflection);
      var calls = 0;
      var library = SceneShaderLibrary(
        cache: null,
        compile: (_) async {
          calls++;
          return CompiledShader(
            binary: reflectionFile,
            reflection: reflectionFile,
          );
        },
      );
      var shaders = library.forPackage(root.path);
      shaders.info('shaders/a.frag');
      await pumpEventQueue();
      shaders.info('shaders/a.frag');
      shaders.info('shaders/a.frag');
      expect(calls, 1);
    });

    test('a changed hash starts a fresh compile', () async {
      var reflectionFile = write('cache/reflection.json', reflection);
      var calls = 0;
      var library = SceneShaderLibrary(
        cache: null,
        compile: (_) async {
          calls++;
          return CompiledShader(
            binary: reflectionFile,
            reflection: reflectionFile,
          );
        },
      );
      var shaders = library.forPackage(root.path);
      shaders.info('shaders/a.frag');
      await pumpEventQueue();
      write('shaders/a.frag', '$source\n// touched\n');
      expect(shaders.info('shaders/a.frag'), isNull);
      await pumpEventQueue();
      expect(calls, 2);
      expect(shaders.info('shaders/a.frag'), isNotNull);
    });

    test('a sampler is reported alongside the uniforms it does have', () async {
      var sampled = '''
{"uniforms": [
  {"name": "uSize", "location": 0, "type": {"type_name": "ShaderType::kFloat", "vec_size": 2, "columns": 1}}
], "sampled_images": [{"name": "uTexture"}]}''';
      var reflectionFile = write('cache/reflection.json', sampled);
      var library = SceneShaderLibrary(
        cache: null,
        compile: (_) async =>
            CompiledShader(binary: reflectionFile, reflection: reflectionFile),
      );
      var shaders = library.forPackage(root.path);
      shaders.info('shaders/a.frag');
      await pumpEventQueue();
      var info = shaders.info('shaders/a.frag')!;
      expect(info.uniforms, hasLength(1));
      expect(info.error, contains('uTexture'));
      expect(info.error, contains('cannot feed one yet'));
    });

    test('declared re-reads the pubspec when its mtime changed', () {
      write('pubspec.yaml', 'name: project\n');
      var library = SceneShaderLibrary(cache: null);
      var shaders = library.forPackage(root.path);
      expect(shaders.declared, isEmpty);
      // Force the mtime forward — same-second writes can otherwise look
      // untouched to a filesystem with one-second resolution.
      File(p.join(root.path, 'pubspec.yaml'))
          .setLastModifiedSync(DateTime.now().add(const Duration(seconds: 2)));
      write('pubspec.yaml', '''
name: project
flutter:
  shaders:
    - shaders/a.frag
''');
      expect(shaders.declared, ['shaders/a.frag']);
    });
  });

  group('FixedSceneShaders', () {
    test('serves exactly what it was given', () {
      const info = SceneShaderInfo(key: 'shaders/a.frag');
      var shaders = FixedSceneShaders({'shaders/a.frag': info});
      expect(shaders.declared, ['shaders/a.frag']);
      expect(shaders.info('shaders/a.frag'), same(info));
      expect(shaders.info('shaders/nowhere.frag'), isNull);
    });
  });

  group('on the pinned SDK', () {
    // The reflection JSON is the compiler's output, not an API: this pins
    // that it still carries what the inspector reads.
    test("the probe shader's uniforms, from impellerc itself", () async {
      var saved = flutterwareDirOverride;
      flutterwareDirOverride = p.join(root.path, 'flutterware');
      addTearDown(() => flutterwareDirOverride = saved);

      var cache = FlutterCache(
        p.join(Platform.environment['FLUTTER_ROOT']!, 'bin', 'cache'),
      );
      var compiled = await compileProjectShader(
        cache: cache,
        source: p.absolute('test/scene/shaders/probe.frag'),
      );
      var u = readShaderUniforms(
        File(compiled.reflection).readAsStringSync(),
        File('test/scene/shaders/probe.frag').readAsStringSync(),
      );
      expect(
        [for (var x in u) (x.name, x.size)],
        [('uSize', 2), ('uColor', 4), ('uTime', 1), ('uTint', 3), ('uMode', 1)],
      );
    }, timeout: const Timeout(Duration(minutes: 2)));
  });
}
