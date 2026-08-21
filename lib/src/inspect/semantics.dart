/// The semantics read's wire shape — plain Dart, like `node.dart` and for the
/// same reason: `fw` and the MCP server link the client that decodes this,
/// and neither can reach `dart:ui`. The tree itself stays raw JSON here; the
/// GUI's `SemanticsSnapshotNode` gives it types where `Rect` exists.
library;

/// One reading of a guest's semantics tree, from `ext.flutterware.semantics`.
class InspectSemantics {
  const InspectSemantics({required this.entryId, required this.root});

  factory InspectSemantics.fromJson(Map<String, Object?> json) =>
      InspectSemantics(
        entryId: json['entry'] as String?,
        root: switch (json['root']) {
          Map root => root.cast<String, Object?>(),
          _ => null,
        },
      );

  /// Which entry this read is of — the settling key, exactly as
  /// `InspectTree.entryId`: a tree naming another entry is a read from before
  /// the switch, not an empty one.
  ///
  /// Null until the guest has a tree to report. Enabling semantics takes
  /// a frame, so the extension withholds the entry id rather than settling a
  /// poll on "nothing yet" — an absence with a name would read as the answer.
  final String? entryId;

  /// The root node, in `semantics_capture.dart`'s shape: rects in screen
  /// logical pixels, flags and actions by name, children in traversal order.
  final Map<String, Object?>? root;

  Map<String, Object?> toJson() => {
    if (entryId != null) 'entry': entryId,
    if (root != null) 'root': root,
  };
}
