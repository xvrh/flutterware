// Writes `assets/models/probe_rig.glb`: the second 3D probe's fixture.
//
// A small device with three named parts, the way a modeller would export it
// from Blender — except that Blender is not on this machine, and a fixture a
// script writes is one anybody can regenerate:
//
//   * `Body`   — a dark slab, 0.78 × 1.6 × 0.08.
//   * `Screen` — a plane on the body's +Z face with texture coordinates whose
//                origin is the top-left corner, glTF's convention. This is the
//                surface the probe binds a live widget to, by name.
//   * `Lid`    — a flap hinged along the top edge, with one animation clip,
//                `Open`, swinging it from flat to upright over two seconds.
//                The probe scrubs it by the playhead.
//
// glTF is right-handed with +Y up and +Z toward the viewer; flutter_scene's
// importer flips Z under a handedness root, so the +Z face here faces the
// engine's default camera. Run from `fixtures/probe_app`:
//
//     fvm dart run tool/make_probe_rig_glb.dart
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

void main() {
  var b = _GlbBuilder();

  // Body: a box centred at the origin.
  var body = _box(width: 0.78, height: 1.6, depth: 0.08);
  var bodyMesh = b.mesh(
    'Body',
    body,
    material: b.material('BodyMat', [0.06, 0.06, 0.07, 1], roughness: 0.6),
  );

  // Screen: a plane just in front of the +Z face, UV origin top-left.
  var screen = _plane(width: 0.69, height: 1.5, z: 0.041);
  var screenMesh = b.mesh(
    'Screen',
    screen,
    material: b.material('ScreenMat', [1, 1, 1, 1], roughness: 1, metallic: 0),
  );

  // Lid: a thin flap. Its vertices hang below the hinge, which is the node's
  // origin, so rotating the node about X swings the flap open.
  var lid = _box(width: 0.78, height: 0.3, depth: 0.02, originY: -0.15);
  var lidMesh = b.mesh(
    'Lid',
    lid,
    material: b.material('LidMat', [0.8, 0.2, 0.1, 1], roughness: 0.5),
  );

  var bodyNode = b.node('Body', mesh: bodyMesh);
  var screenNode = b.node('Screen', mesh: screenMesh);
  // Hinge on the top edge of the body's +Z face.
  var lidNode = b.node('Lid', mesh: lidMesh, translation: [0, 0.8, 0.05]);
  var root = b.node('ProbeRig', children: [bodyNode, screenNode, lidNode]);
  b.scene([root]);

  // `Open`: rotation about X, 0° → 90° (flap swings up and out), three keys.
  b.rotationClip('Open', lidNode, [
    (0.0, _quatX(0)),
    (1.0, _quatX(math.pi / 4)),
    (2.0, _quatX(math.pi / 2)),
  ]);

  var out = File('assets/models/probe_rig.glb')
    ..parent.createSync(recursive: true);
  out.writeAsBytesSync(b.build());
  stdout.writeln('wrote ${out.path} (${out.lengthSync()} bytes)');
}

List<double> _quatX(double angle) => [
  math.sin(angle / 2),
  0,
  0,
  math.cos(angle / 2),
];

class _Geometry {
  final positions = <double>[];
  final normals = <double>[];
  final uvs = <double>[];
  final indices = <int>[];
}

/// A box with per-face normals. [originY] shifts the box so its top edge sits
/// at the origin when negative half the height.
_Geometry _box({
  required double width,
  required double height,
  required double depth,
  double originY = 0,
}) {
  var g = _Geometry();
  var x = width / 2, y = height / 2, z = depth / 2;
  void face(List<List<double>> corners, List<double> normal) {
    var base = g.positions.length ~/ 3;
    for (var c in corners) {
      g.positions.addAll([c[0], c[1] + originY, c[2]]);
      g.normals.addAll(normal);
      g.uvs.addAll([0, 0]);
    }
    g.indices.addAll([base, base + 1, base + 2, base, base + 2, base + 3]);
  }

  // Counter-clockwise seen from outside, per face.
  face(
    [
      [-x, -y, z],
      [x, -y, z],
      [x, y, z],
      [-x, y, z],
    ],
    [0, 0, 1],
  ); // +Z
  face(
    [
      [x, -y, -z],
      [-x, -y, -z],
      [-x, y, -z],
      [x, y, -z],
    ],
    [0, 0, -1],
  ); // -Z
  face(
    [
      [x, -y, z],
      [x, -y, -z],
      [x, y, -z],
      [x, y, z],
    ],
    [1, 0, 0],
  ); // +X
  face(
    [
      [-x, -y, -z],
      [-x, -y, z],
      [-x, y, z],
      [-x, y, -z],
    ],
    [-1, 0, 0],
  ); // -X
  face(
    [
      [-x, y, z],
      [x, y, z],
      [x, y, -z],
      [-x, y, -z],
    ],
    [0, 1, 0],
  ); // +Y
  face(
    [
      [-x, -y, -z],
      [x, -y, -z],
      [x, -y, z],
      [-x, -y, z],
    ],
    [0, -1, 0],
  ); // -Y
  return g;
}

/// A plane facing +Z, UV (0,0) at the top-left corner as glTF specifies.
_Geometry _plane({
  required double width,
  required double height,
  required double z,
}) {
  var g = _Geometry();
  var x = width / 2, y = height / 2;
  var corners = [
    ([-x, y, z], [0.0, 0.0]), // top-left
    ([-x, -y, z], [0.0, 1.0]), // bottom-left
    ([x, -y, z], [1.0, 1.0]), // bottom-right
    ([x, y, z], [1.0, 0.0]), // top-right
  ];
  for (var (p, uv) in corners) {
    g.positions.addAll(p);
    g.normals.addAll([0, 0, 1]);
    g.uvs.addAll(uv);
  }
  g.indices.addAll([0, 1, 2, 0, 2, 3]);
  return g;
}

class _GlbBuilder {
  final _bin = BytesBuilder();
  final _bufferViews = <Map<String, Object?>>[];
  final _accessors = <Map<String, Object?>>[];
  final _materials = <Map<String, Object?>>[];
  final _meshes = <Map<String, Object?>>[];
  final _nodes = <Map<String, Object?>>[];
  final _animations = <Map<String, Object?>>[];
  final _scenes = <Map<String, Object?>>[];

  int _view(Uint8List bytes, {int? target}) {
    while (_bin.length % 4 != 0) {
      _bin.addByte(0);
    }
    _bufferViews.add({
      'buffer': 0,
      'byteOffset': _bin.length,
      'byteLength': bytes.length,
      'target': ?target,
    });
    _bin.add(bytes);
    return _bufferViews.length - 1;
  }

  int _floats(
    List<double> values,
    String type, {
    bool bounds = false,
    int? target,
  }) {
    var components = switch (type) {
      'SCALAR' => 1,
      'VEC2' => 2,
      'VEC3' => 3,
      'VEC4' => 4,
      _ => throw ArgumentError(type),
    };
    var data = Float32List.fromList(values);
    var view = _view(data.buffer.asUint8List(), target: target);
    var count = values.length ~/ components;
    List<double>? min, max;
    if (bounds) {
      min = List.filled(components, double.infinity);
      max = List.filled(components, double.negativeInfinity);
      for (var i = 0; i < values.length; i++) {
        var c = i % components;
        min[c] = math.min(min[c], values[i]);
        max[c] = math.max(max[c], values[i]);
      }
    }
    _accessors.add({
      'bufferView': view,
      'componentType': 5126,
      'count': count,
      'type': type,
      'min': ?min,
      'max': ?max,
    });
    return _accessors.length - 1;
  }

  int _indices(List<int> values) {
    var data = Uint16List.fromList(values);
    var view = _view(data.buffer.asUint8List(), target: 34963);
    _accessors.add({
      'bufferView': view,
      'componentType': 5123,
      'count': values.length,
      'type': 'SCALAR',
    });
    return _accessors.length - 1;
  }

  int material(
    String name,
    List<double> baseColor, {
    double roughness = 0.5,
    double metallic = 0,
  }) {
    _materials.add({
      'name': name,
      'pbrMetallicRoughness': {
        'baseColorFactor': baseColor,
        'metallicFactor': metallic,
        'roughnessFactor': roughness,
      },
    });
    return _materials.length - 1;
  }

  int mesh(String name, _Geometry g, {required int material}) {
    _meshes.add({
      'name': name,
      'primitives': [
        {
          'attributes': {
            'POSITION': _floats(
              g.positions,
              'VEC3',
              bounds: true,
              target: 34962,
            ),
            'NORMAL': _floats(g.normals, 'VEC3', target: 34962),
            'TEXCOORD_0': _floats(g.uvs, 'VEC2', target: 34962),
          },
          'indices': _indices(g.indices),
          'material': material,
        },
      ],
    });
    return _meshes.length - 1;
  }

  int node(
    String name, {
    int? mesh,
    List<int> children = const [],
    List<double>? translation,
  }) {
    _nodes.add({
      'name': name,
      'mesh': ?mesh,
      if (children.isNotEmpty) 'children': children,
      'translation': ?translation,
    });
    return _nodes.length - 1;
  }

  void scene(List<int> roots) => _scenes.add({'nodes': roots});

  /// One clip rotating [node], linear between [keys] of (seconds, quaternion).
  void rotationClip(String name, int node, List<(double, List<double>)> keys) {
    var input = _floats([for (var (t, _) in keys) t], 'SCALAR', bounds: true);
    var output = _floats([for (var (_, q) in keys) ...q], 'VEC4');
    _animations.add({
      'name': name,
      'samplers': [
        {'input': input, 'output': output, 'interpolation': 'LINEAR'},
      ],
      'channels': [
        {
          'sampler': 0,
          'target': {'node': node, 'path': 'rotation'},
        },
      ],
    });
  }

  Uint8List build() {
    while (_bin.length % 4 != 0) {
      _bin.addByte(0);
    }
    var bin = _bin.toBytes();
    var json = jsonEncode({
      'asset': {
        'version': '2.0',
        'generator': 'flutterware make_probe_rig_glb',
      },
      'scene': 0,
      'scenes': _scenes,
      'nodes': _nodes,
      'meshes': _meshes,
      'materials': _materials,
      'animations': _animations,
      'accessors': _accessors,
      'bufferViews': _bufferViews,
      'buffers': [
        {'byteLength': bin.length},
      ],
    });
    var jsonBytes = utf8.encode(json);
    var jsonPadded = Uint8List(((jsonBytes.length + 3) ~/ 4) * 4)
      ..fillRange(0, jsonBytes.length, 0)
      ..setAll(0, jsonBytes)
      ..fillRange(jsonBytes.length, ((jsonBytes.length + 3) ~/ 4) * 4, 0x20);

    var out = BytesBuilder();
    void u32(int v) => out.add(
      (ByteData(4)..setUint32(0, v, Endian.little)).buffer.asUint8List(),
    );
    var total = 12 + 8 + jsonPadded.length + 8 + bin.length;
    out.add(ascii.encode('glTF'));
    u32(2);
    u32(total);
    u32(jsonPadded.length);
    u32(0x4E4F534A); // JSON
    out.add(jsonPadded);
    u32(bin.length);
    u32(0x004E4942); // BIN
    out.add(bin);
    return out.toBytes();
  }
}
