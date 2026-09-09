// What a model file carries, read by the studio without an engine.
//
// A 3D placement names an asset, a surface names a mesh in it, both name a
// clip in it — three strings the designer would otherwise type from memory.
// This reads a glTF's own tables and answers what there is to name: the
// nodes that carry a mesh (by the name the modeller gave the object, which
// is what the renderer finds them by), and the animations with how long
// they run. The JSON chunk of a `.glb`, or a `.gltf` file, is all it opens;
// a clip's length is the largest input time of its samplers, which the
// accessor's `max` carries and the buffer confirms when it does not.
//
// Pure Dart on the studio side; the guest never needs it. Cached by path
// and modification time, since the inspector asks on every rebuild.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

/// One clip in a model file.
class ModelClip {
  const ModelClip(this.name, this.seconds);

  final String name;

  /// How long the clip runs — its last keyframe's time.
  final double seconds;

  @override
  String toString() => '$name (${seconds.toStringAsFixed(2)}s)';
}

/// The tables of one model file the editor offers to pick from.
class ModelAssetInfo {
  const ModelAssetInfo({required this.meshes, required this.clips});

  /// The nodes that carry a mesh, by name, in the file's order — what a
  /// surface's `mesh` row names and the renderer looks up.
  final List<String> meshes;

  /// The animations, by name, with their lengths.
  final List<ModelClip> clips;

  static const empty = ModelAssetInfo(meshes: [], clips: []);
}

/// Reads [file] — a `.glb` or a `.gltf` — and reports its meshes and clips.
/// Null when the file is not a model this understands; a corrupt file
/// answers with what could be read rather than throwing.
ModelAssetInfo? readModelAsset(File file) {
  Map<String, Object?> json;
  Uint8List? bin;
  var bytes = file.readAsBytesSync();
  if (bytes.length >= 12 &&
      String.fromCharCodes(bytes.sublist(0, 4)) == 'glTF') {
    var data = ByteData.sublistView(bytes);
    var offset = 12;
    Map<String, Object?>? parsed;
    while (offset + 8 <= bytes.length) {
      var length = data.getUint32(offset, Endian.little);
      var type = data.getUint32(offset + 4, Endian.little);
      var start = offset + 8;
      var end = start + length;
      if (end > bytes.length) break;
      // 0x4E4F534A is `JSON`, 0x004E4942 is `BIN\0`.
      if (type == 0x4E4F534A) {
        parsed = jsonDecode(
          utf8.decode(bytes.sublist(start, end)),
        ) as Map<String, Object?>;
      } else if (type == 0x004E4942) {
        bin = Uint8List.sublistView(bytes, start, end);
      }
      offset = end + (end % 4 == 0 ? 0 : 4 - end % 4);
    }
    if (parsed == null) return null;
    json = parsed;
  } else {
    try {
      json = jsonDecode(utf8.decode(bytes)) as Map<String, Object?>;
    } on FormatException {
      return null;
    }
    if (json['asset'] is! Map) return null;
  }
  return _tables(json, bin, file.parent);
}

ModelAssetInfo _tables(
  Map<String, Object?> json,
  Uint8List? bin,
  Directory beside,
) {
  var nodes = (json['nodes'] as List?) ?? const [];
  var meshes = <String>[
    for (var (i, n) in nodes.indexed)
      if (n is Map && n['mesh'] != null) (n['name'] as String?) ?? 'node $i',
  ];
  var accessors = (json['accessors'] as List?) ?? const [];
  var clips = <ModelClip>[];
  for (var (i, a) in ((json['animations'] as List?) ?? const []).indexed) {
    if (a is! Map) continue;
    var seconds = 0.0;
    for (var s in (a['samplers'] as List?) ?? const []) {
      if (s is! Map || s['input'] is! int) continue;
      var input = s['input'] as int;
      if (input < 0 || input >= accessors.length) continue;
      var accessor = accessors[input] as Map;
      var known =
          _accessorMax(accessor) ??
          _accessorMaxFromBuffer(json, accessor, bin, beside);
      if (known != null && known > seconds) seconds = known;
    }
    clips.add(ModelClip((a['name'] as String?) ?? 'animation $i', seconds));
  }
  return ModelAssetInfo(meshes: meshes, clips: clips);
}

double? _accessorMax(Map accessor) {
  if (accessor['max'] case [num v, ...]) return v.toDouble();
  return null;
}

/// The largest float in a scalar float accessor, read off its buffer —
/// for an exporter that wrote no `max`.
double? _accessorMaxFromBuffer(
  Map<String, Object?> json,
  Map accessor,
  Uint8List? bin,
  Directory beside,
) {
  if (accessor['componentType'] != 5126 || accessor['type'] != 'SCALAR') {
    return null;
  }
  var views = (json['bufferViews'] as List?) ?? const [];
  var buffers = (json['buffers'] as List?) ?? const [];
  if (accessor['bufferView'] is! int) return null;
  var view = views[accessor['bufferView'] as int] as Map;
  var buffer = buffers[view['buffer'] as int] as Map;
  Uint8List? bytes;
  if (buffer['uri'] case String uri) {
    if (uri.startsWith('data:')) {
      var comma = uri.indexOf(',');
      if (comma < 0) return null;
      bytes = base64Decode(uri.substring(comma + 1));
    } else {
      var file = File(p.join(beside.path, Uri.decodeComponent(uri)));
      if (!file.existsSync()) return null;
      bytes = file.readAsBytesSync();
    }
  } else {
    bytes = bin;
  }
  if (bytes == null) return null;
  var count = accessor['count'] as int;
  var offset =
      ((view['byteOffset'] as int?) ?? 0) +
      ((accessor['byteOffset'] as int?) ?? 0);
  var stride = (view['byteStride'] as int?) ?? 4;
  if (offset + (count - 1) * stride + 4 > bytes.length) return null;
  var data = ByteData.sublistView(bytes);
  double? max;
  for (var i = 0; i < count; i++) {
    var v = data.getFloat32(offset + i * stride, Endian.little);
    if (max == null || v > max) max = v;
  }
  return max;
}

/// Every model file under [packageRoot]'s `assets/`, as the paths a
/// scene's `asset` row spells — relative to the package, forward slashes.
List<String> listModelAssets(String packageRoot) {
  var assets = Directory(p.join(packageRoot, 'assets'));
  if (!assets.existsSync()) return const [];
  var found = <String>[
    for (var f in assets.listSync(recursive: true, followLinks: false))
      if (f is File && _isModel(f.path))
        p.relative(f.path, from: packageRoot).replaceAll(r'\', '/'),
  ]..sort();
  return found;
}

bool _isModel(String path) {
  var ext = p.extension(path).toLowerCase();
  return ext == '.glb' || ext == '.gltf';
}

/// The studio's cache of model files, by path and modification time.
class ModelAssets {
  ModelAssets._();

  static final shared = ModelAssets._();

  final _byPath = <String, (DateTime, ModelAssetInfo?)>{};

  /// What [asset] (a package-relative path, as a scene spells it) holds, or
  /// null when there is no such file or it is not a model.
  ModelAssetInfo? info(String packageRoot, String asset) {
    if (asset.isEmpty) return null;
    var file = File(p.join(packageRoot, asset));
    if (!file.existsSync()) {
      _byPath.remove(file.path);
      return null;
    }
    var stamp = file.lastModifiedSync();
    var cached = _byPath[file.path];
    if (cached != null && cached.$1 == stamp) return cached.$2;
    var read = readModelAsset(file);
    _byPath[file.path] = (stamp, read);
    return read;
  }

  /// The model files the package offers. Listed on every ask: a directory
  /// listing is cheap and a new file must show without a restart.
  List<String> assets(String packageRoot) => listModelAssets(packageRoot);
}
