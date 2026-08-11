import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'closure.dart';

/// Rendered pictures, filed by what made them.
///
/// Shared across every worktree on the machine and every comparison run,
/// because the key already says everything about a picture: five agents
/// branched off one commit render its previews once between them.
///
/// **The base checkout is a build fixture; this is what persists.** A
/// comparison materialises a base worktree, renders from it, and may throw the
/// worktree away — the shots outlive it, and the next comparison against that
/// commit renders nothing at all.
class ShotCache {
  ShotCache(this.root);

  /// `~/.flutterware/shots` in production; a temp directory in a test.
  final String root;

  late final ClosureMemo memo = ClosureMemo(p.join(root, 'closures'));

  /// Whether [key] has already been rendered.
  bool has(String key) => File(_pathFor(key)).existsSync();

  /// The picture filed under [key], or null when nothing is.
  Uint8List? read(String key) {
    var file = File(_pathFor(key));
    return file.existsSync() ? file.readAsBytesSync() : null;
  }

  ShotRecord? meta(String key) {
    var file = File('${_pathFor(key)}.json');
    if (!file.existsSync()) return null;
    try {
      var json = jsonDecode(file.readAsStringSync());
      return json is Map<String, Object?> ? ShotRecord.fromJson(json) : null;
    } on FormatException {
      return null;
    }
  }

  /// Files [bytes] under [key].
  ///
  /// **Written to a temporary name and renamed**, because a comparison can be
  /// killed at any moment and a half-written picture under a content key is a
  /// lie that never expires: every later run would find the key present and
  /// serve the truncated file. Rename is atomic on every filesystem this runs
  /// on.
  void write(String key, Uint8List bytes, ShotRecord record) {
    var path = _pathFor(key);
    Directory(p.dirname(path)).createSync(recursive: true);
    var staging = File('$path.part');
    staging.writeAsBytesSync(bytes, flush: true);
    File('$path.json').writeAsStringSync(jsonEncode(record.toJson()));
    staging.renameSync(path);
  }

  /// The tree taken off the same frame, filed beside it.
  ///
  /// Same key, because it is the same render: a tree that came from a
  /// different build than the picture is the exact thing
  /// `HeadlessCatalog.observe`'s one-render rule exists to prevent, and
  /// splitting the key here would reintroduce it through the back door.
  void writeTree(String key, Map<String, Object?> tree) {
    var path = '${_pathFor(key)}.tree.json';
    Directory(p.dirname(path)).createSync(recursive: true);
    File(path).writeAsStringSync(jsonEncode(tree));
  }

  Map<String, Object?>? readTree(String key) {
    var file = File('${_pathFor(key)}.tree.json');
    if (!file.existsSync()) return null;
    try {
      var json = jsonDecode(file.readAsStringSync());
      return json is Map<String, Object?> ? json : null;
    } on FormatException {
      return null;
    }
  }

  /// Two levels of fan-out, as every content-addressed store does it: a
  /// hundred thousand shots in one directory is a directory listing nothing
  /// wants to do.
  String _pathFor(String key) =>
      p.join(root, key.substring(0, 2), key.substring(2, 4), key);
}

/// What a cached picture is, beyond its bytes.
class ShotRecord {
  const ShotRecord({
    required this.format,
    required this.width,
    required this.height,
    this.entryId,
    this.complaint,
  });

  factory ShotRecord.fromJson(Map<String, Object?> json) => ShotRecord(
    format: json['format'] as String? ?? 'png',
    width: json['width'] as int? ?? 0,
    height: json['height'] as int? ?? 0,
    entryId: json['entry'] as String?,
    complaint: json['complaint'] as String?,
  );

  /// `raw` — rgba8888 rows, [width]×[height]×4 — or `png`.
  ///
  /// Raw is what a comparison stores: PNG *encoding* is ~80% of a capture's
  /// cost at 1×, the diff reads pixels rather than files, and only the handful
  /// of pictures that end up on screen are ever encoded.
  final String format;

  final int width;
  final int height;

  /// Which entry this was, for a human reading the cache directory. Not part
  /// of the key and not read by anything: the key is the identity.
  final String? entryId;

  /// What the framework said while this frame was drawn, when it drew it
  /// anyway — an overflow, a missing font.
  ///
  /// Kept beside the picture rather than recomputed, because the picture
  /// outlives the render: a cached frame is served without the guest that
  /// produced it, and "this overflows now" would otherwise be a finding that
  /// survives exactly one comparison.
  final String? complaint;

  Map<String, Object?> toJson() => {
    'format': format,
    'width': width,
    'height': height,
    'entry': ?entryId,
    'complaint': ?complaint,
  };
}
