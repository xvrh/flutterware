import 'address.dart';

/// What a job hands back.
///
/// The overhaul plan's revised thesis is that the real asks are *commands that
/// produce artifacts* — "screenshot this entry", "run this suite", "give me the
/// widget tree". So an artifact is the return type of doing work, not a side
/// effect of it: the CLI prints [path], MCP returns an image block, the GUI
/// shows a thumbnail. One object, three renderings.
///
/// [address] is required. An artifact that cannot say what it is *of* is not
/// reproducible, and a screenshot without its resolved axes is exactly the
/// under-specification the entry model warned about.
class Artifact {
  static const png = 'image/png';
  static const plainText = 'text/plain';
  static const json = 'application/json';
  static const widgetTree = 'application/vnd.flutterware.widget-tree+json';

  Artifact({
    required this.kind,
    required this.address,
    this.path,
    this.text,
    this.meta = const {},
  }) {
    if (path == null && text == null) {
      throw ArgumentError(
        'An artifact needs somewhere to live: give it a path, inline text, or '
        'both.',
      );
    }
  }

  /// A MIME type where one fits — see the constants above.
  final String kind;

  /// What this is an artifact of, axes included.
  final Address address;

  /// Where it was written, when it was written. Relative to the worktree root
  /// so the value survives being read on another machine.
  final String? path;

  /// The content itself, for artifacts small enough that making the reader open
  /// a file is worse than carrying it.
  final String? text;

  /// Anything the producer wants the reader to know: timings, compile stats,
  /// exit codes. Never load-bearing — a reader that ignores it still works.
  final Map<String, Object?> meta;

  Map<String, Object?> toJson() => {
    'kind': kind,
    'address': address.toString(),
    if (path != null) 'path': path,
    if (text != null) 'text': text,
    if (meta.isNotEmpty) 'meta': meta,
  };

  static Artifact fromJson(Map<String, Object?> json) => Artifact(
    kind: json['kind']! as String,
    address: Address.parse(json['address']! as String),
    path: json['path'] as String?,
    text: json['text'] as String?,
    meta: (json['meta'] as Map?)?.cast<String, Object?>() ?? const {},
  );

  @override
  String toString() => 'Artifact($kind, $address, ${path ?? 'inline'})';
}
