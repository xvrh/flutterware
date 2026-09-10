// What a scene's shader inspector draws a control from: the package's
// declared shaders, and each one's uniforms as `impellerc`'s reflection JSON
// and the shader's own `// @range`/`// @color`/`// @default` comments
// describe them. Pure parsers first — reflection JSON and GLSL comments in,
// [SceneShaderUniform]s out — then the library that keeps them warm per
// package, compiling through [compileProjectShader] as a shader's content
// changes.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutterware/scene_authoring.dart' show ShaderPaint;
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../embedder/flutter_cache.dart';
import '../previews/project_shaders.dart';

/// One uniform a shader declares, as the reflection and the source's own
/// comments describe it.
class SceneShaderUniform {
  const SceneShaderUniform({
    required this.name,
    required this.size,
    required this.location,
    this.range,
    this.isColor = false,
    this.defaults,
  });

  final String name;

  /// 1..4 floats — `float`, `vec2`, `vec3`, `vec4`.
  final int size;

  /// Declaration order, as `impellerc` numbers it — not the reflection
  /// array's own order.
  final int location;

  /// `// @range a b` on the declaration line, when it parsed.
  final (double, double)? range;

  /// `// @color`, honoured only on a `vec3`/`vec4`.
  final bool isColor;

  /// `// @default …`, honoured only when it gave exactly [size] numbers.
  final List<double>? defaults;

  /// Whether [ShaderPaint.rendererUniforms] sets this one — same name, same
  /// size — so the inspector leaves it to the renderer rather than drawing
  /// a control for it.
  bool get rendererOwned => ShaderPaint.rendererUniforms[name] == size;
}

/// What is known about one shader: its uniforms, or why they could not be
/// read.
class SceneShaderInfo {
  const SceneShaderInfo({
    required this.key,
    this.uniforms = const [],
    this.error,
  });

  /// The pubspec's `shaders:` entry — a path relative to the package root.
  final String key;

  /// In declaration order.
  final List<SceneShaderUniform> uniforms;

  /// Why the uniforms above are incomplete or absent, or why nothing could
  /// be read at all. A shader that read cleanly carries none.
  final String? error;

  /// Every non-renderer uniform's `@default`, by name — the inspector's
  /// starting values for a layer that has not set any of its own yet.
  Map<String, List<double>> get defaults => {
    for (var u in uniforms)
      if (!u.rendererOwned && u.defaults != null) u.name: u.defaults!,
  };
}

final _declaration = RegExp(
  r'^\s*uniform\s+(?:(?:lowp|mediump|highp)\s+)?(float|vec2|vec3|vec4)\s+(\w+)\s*;(.*)$',
  multiLine: true,
);

final _tag = RegExp(r'@(\w+)([^@]*)');

class _Annotation {
  (double, double)? range;
  var isColor = false;
  List<double>? defaults;
}

/// One uniform's `// @...` tags, by name — read off its declaration line,
/// wherever [source] puts it.
Map<String, _Annotation> _readAnnotations(String source) {
  var out = <String, _Annotation>{};
  for (var match in _declaration.allMatches(source)) {
    var name = match[2]!;
    var tail = match[3] ?? '';
    var slash = tail.indexOf('//');
    if (slash < 0) continue;
    var annotation = _Annotation();
    for (var tag in _tag.allMatches(tail.substring(slash + 2))) {
      var rest = (tag[2] ?? '').trim();
      switch (tag[1]) {
        case 'range':
          var parts = rest.isEmpty
              ? const <String>[]
              : rest.split(RegExp(r'\s+'));
          if (parts.length == 2) {
            var a = double.tryParse(parts[0]);
            var b = double.tryParse(parts[1]);
            if (a != null && b != null) annotation.range = (a, b);
          }
        case 'color':
          annotation.isColor = true;
        case 'default':
          if (rest.isEmpty) break;
          var numbers = rest
              .split(RegExp(r'\s+'))
              .map(double.tryParse)
              .toList();
          if (!numbers.contains(null)) annotation.defaults = numbers.cast();
      }
    }
    out[name] = annotation;
  }
  return out;
}

/// The uniforms `impellerc` reflected in [reflectionJson], in declaration
/// order, each carrying whatever [source]'s own comments add.
///
/// A uniform that is not a plain float vector — a matrix, a sampler, an
/// integer — is left out; the inspector has nothing to draw for it, and it
/// has no [SceneShaderUniform.location] worth sorting by. Malformed JSON, or
/// one without a `uniforms` array, is an empty list rather than a throw: a
/// `.frag` mid-edit fails to compile far more often than it fails to
/// reflect, and this must degrade the same way that does.
List<SceneShaderUniform> readShaderUniforms(
  String reflectionJson,
  String source,
) {
  List<({String name, int size, int location})> entries;
  try {
    var decoded = jsonDecode(reflectionJson);
    var raw = decoded is Map ? decoded['uniforms'] : null;
    if (raw is! List) return const [];
    entries = [
      for (var item in raw)
        if (item is Map && _isFloatVector(item))
          (
            name: item['name'] as String,
            size: (item['type'] as Map)['vec_size'] as int,
            location: item['location'] as int,
          ),
    ];
  } on FormatException {
    return const [];
  }
  entries.sort((a, b) => a.location.compareTo(b.location));

  var annotations = _readAnnotations(source);
  return [
    for (var e in entries)
      SceneShaderUniform(
        name: e.name,
        size: e.size,
        location: e.location,
        range: annotations[e.name]?.range,
        isColor: e.size >= 3 && (annotations[e.name]?.isColor ?? false),
        defaults: switch (annotations[e.name]?.defaults) {
          var d? when d.length == e.size => d,
          _ => null,
        },
      ),
  ];
}

bool _isFloatVector(Map item) {
  if (item['name'] is! String || item['location'] is! int) return false;
  var type = item['type'];
  if (type is! Map || type['type_name'] != 'ShaderType::kFloat') return false;
  var columns = type['columns'];
  if (columns != null && columns != 1) return false;
  var vecSize = type['vec_size'];
  return vecSize is int && vecSize >= 1 && vecSize <= 4;
}

List<String> _sampledImageNames(String reflectionJson) {
  try {
    var decoded = jsonDecode(reflectionJson);
    var raw = decoded is Map ? decoded['sampled_images'] : null;
    if (raw is! List) return const [];
    return [
      for (var item in raw)
        if (item is Map && item['name'] is String) item['name'] as String,
    ];
  } on FormatException {
    return const [];
  }
}

/// The package's own `flutter: shaders:` entries, in the order the pubspec
/// lists them. A dependency's shaders are never offered — a scene reaches a
/// shader the same way `FragmentProgram.fromAsset` does, by an asset key
/// that must resolve in the root package's own bundle.
///
/// An unreadable or absent pubspec, or one with no `shaders:` list, is an
/// empty list; a non-string entry is dropped rather than failing the rest.
List<String> declaredShaders(String packageRoot) {
  String text;
  try {
    text = File(p.join(packageRoot, 'pubspec.yaml')).readAsStringSync();
  } on FileSystemException {
    return const [];
  }
  try {
    var doc = loadYaml(text);
    var flutter = doc is Map ? doc['flutter'] : null;
    var shaders = flutter is Map ? flutter['shaders'] : null;
    if (shaders is! List) return const [];
    return [
      for (var s in shaders)
        if (s is String) s,
    ];
  } on YamlException {
    return const [];
  }
}

/// A package's shaders, as the inspector reads them: what is declared, and
/// what is known about each one so far.
abstract interface class SceneShaders implements Listenable {
  List<String> get declared;

  /// null while [key] has never been read, or is being (re)compiled.
  SceneShaderInfo? info(String key);
}

/// Reads a project's declared shaders on demand, compiling each one through
/// [compileProjectShader] (or [compile], for a test) and caching the result
/// by content — the same key [compileProjectShader] itself caches by, so a
/// warm read costs a hash and nothing else.
class SceneShaderLibrary extends ChangeNotifier {
  SceneShaderLibrary({required this.cache, @visibleForTesting this.compile});

  final FlutterCache? cache;

  @visibleForTesting
  final Future<CompiledShader> Function(String source)? compile;

  final _packages = <String, _PackageShaders>{};

  /// The view onto one package's shaders. Cached per [packageRoot], so a
  /// caller that holds onto it sees the same compiles land as any other.
  SceneShaders forPackage(String packageRoot) {
    var key = p.normalize(p.absolute(packageRoot));
    return _packages.putIfAbsent(key, () => _PackageShaders(this, key));
  }

  Future<CompiledShader> _runCompile(String source) {
    if (compile case var override?) return override(source);
    var flutterCache = cache;
    if (flutterCache == null) {
      return Future.error(StateError('no Flutter SDK to compile with'));
    }
    return compileProjectShader(cache: flutterCache, source: source);
  }
}

/// A fixed set of shaders — a test double, or a scene rendered somewhere
/// [SceneShaderLibrary]'s live compiling has no home, such as a store-asset
/// render.
class FixedSceneShaders extends ChangeNotifier implements SceneShaders {
  FixedSceneShaders(this.infos);

  final Map<String, SceneShaderInfo> infos;

  @override
  List<String> get declared => infos.keys.toList();

  @override
  SceneShaderInfo? info(String key) => infos[key];
}

class _PackageShaders extends ChangeNotifier implements SceneShaders {
  _PackageShaders(this._library, this.packageRoot);

  final SceneShaderLibrary _library;
  final String packageRoot;

  List<String>? _declared;
  DateTime? _declaredAt;

  @override
  List<String> get declared {
    var pubspec = File(p.join(packageRoot, 'pubspec.yaml'));
    DateTime? modified;
    try {
      modified = pubspec.statSync().modified;
    } on FileSystemException {
      modified = null;
    }
    if (_declared == null || modified != _declaredAt) {
      _declared = declaredShaders(packageRoot);
      _declaredAt = modified;
    }
    return _declared!;
  }

  final _infos = <String, SceneShaderInfo>{};
  final _hashes = <String, String>{};
  final _inFlight = <String>{};

  @override
  SceneShaderInfo? info(String key) {
    var source = p.join(packageRoot, key);
    if (!File(source).existsSync()) {
      return SceneShaderInfo(key: key, error: "'$key' is not on disk");
    }
    var hash = projectShaderHash(source);
    if (_hashes[key] == hash) return _infos[key];

    var token = '$key@$hash';
    if (_inFlight.add(token)) unawaited(_load(key, source, hash, token));
    return null;
  }

  Future<void> _load(
    String key,
    String source,
    String hash,
    String token,
  ) async {
    SceneShaderInfo info;
    try {
      var compiled = await _library._runCompile(source);
      var reflectionText = File(compiled.reflection).readAsStringSync();
      var uniforms = readShaderUniforms(
        reflectionText,
        File(source).readAsStringSync(),
      );
      var samplers = _sampledImageNames(reflectionText);
      info = SceneShaderInfo(
        key: key,
        uniforms: uniforms,
        error: samplers.isEmpty
            ? null
            : 'uses a sampler (${samplers.join(', ')}) — a scene cannot feed '
                  'one yet',
      );
    } on Object catch (error) {
      info = SceneShaderInfo(key: key, error: _describe(error));
    }
    _infos[key] = info;
    _hashes[key] = hash;
    _inFlight.remove(token);
    notifyListeners();
  }
}

/// [error]'s message, trimmed to a few lines and with any scratch path a
/// compile staged its work under collapsed to a basename — the detail that
/// tells nobody anything, in the one spot it could otherwise leak into the
/// inspector.
String _describe(Object error) {
  var message = error is StateError ? error.message : '$error';
  var head = message.split('\n').take(4).join('\n');
  return head.replaceAllMapped(
    RegExp(r'\S*[/\\]staging[/\\]\S*'),
    (m) => p.basename(m[0]!),
  );
}
