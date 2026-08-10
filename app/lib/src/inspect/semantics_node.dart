import 'dart:ui';

/// One node of a captured semantics tree — what `semantics_capture.dart`
/// writes in the guest, whichever host asked: a scenario step's
/// `.semantics.json`, or the catalog's live `ext.flutterware.semantics` read.
/// Rects are in the screen's logical coordinates, the space the screenshot
/// overlay paints in.
class SemanticsSnapshotNode {
  SemanticsSnapshotNode({
    required this.rect,
    required this.label,
    required this.value,
    required this.hint,
    required this.tooltip,
    this.identifier = '',
    this.textDirection = '',
    required this.flags,
    required this.actions,
    required this.children,
  });

  factory SemanticsSnapshotNode.fromJson(Map<String, Object?> json) {
    var rect = (json['rect']! as Map).cast<String, num>();
    return SemanticsSnapshotNode(
      rect: Rect.fromLTWH(
        rect['x']!.toDouble(),
        rect['y']!.toDouble(),
        rect['width']!.toDouble(),
        rect['height']!.toDouble(),
      ),
      label: json['label'] as String? ?? '',
      value: json['value'] as String? ?? '',
      hint: json['hint'] as String? ?? '',
      tooltip: json['tooltip'] as String? ?? '',
      identifier: json['identifier'] as String? ?? '',
      textDirection: json['textDirection'] as String? ?? '',
      flags: (json['flags'] as List?)?.cast<String>() ?? const [],
      actions: (json['actions'] as List?)?.cast<String>() ?? const [],
      children: [
        for (var child in json['children'] as List? ?? const [])
          SemanticsSnapshotNode.fromJson(
            (child as Map).cast<String, Object?>(),
          ),
      ],
    );
  }

  final Rect rect;
  final String label;
  final String value;
  final String hint;
  final String tooltip;

  /// The `Semantics(identifier: …)` handle — a test id, not spoken words.
  final String identifier;

  /// `ltr`/`rtl` when the node declares one.
  final String textDirection;

  final List<String> flags;
  final List<String> actions;
  final List<SemanticsSnapshotNode> children;

  /// What a row leads with: the words assistive tech reads, else what kind of
  /// thing this is. A node with neither is structure, shown dimly.
  String get headline => label.isNotEmpty
      ? '"$label"'
      : value.isNotEmpty
      ? '"$value"'
      : tooltip.isNotEmpty
      ? '"$tooltip"'
      : role ?? '(group)';

  /// The role flags worth a badge, in the reader's vocabulary.
  static const _roles = {
    'isButton': 'button',
    'isTextField': 'text field',
    'isHeader': 'header',
    'isLink': 'link',
    'isSlider': 'slider',
    'isImage': 'image',
    'isKeyboardKey': 'key',
  };

  String? get role {
    for (var MapEntry(key: flag, value: name) in _roles.entries) {
      if (flags.contains(flag)) return name;
    }
    return null;
  }
}
