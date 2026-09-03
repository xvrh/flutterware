//@flutterware:scene=0.6
// Owned by the flutterware scene editor, which reads and writes this whole
// file. Hand edits are welcome inside the grammar: every node is a
// `late final` field (the field name is the node's identity), placed exactly
// once in a children list; a parameter is a `final` in the class header
// whose default is the mockup. Anything outside the grammar is refused with
// a line number rather than silently dropped.

class PromoBadge({
  final String label = 'New',
  final Color tint = const Color(0xFFE8632B),
}) {
  late final text = Text(
    label,
    fontSize: 14,
    weight: FontWeight.w700,
    color: Color(0xFFFFFFFF),
  );
  late final root = Frame(
    width: 96,
    height: 32,
    fill: tint,
    corner: 16,
    layout: NodeLayout.row,
    mainAlign: MainAxisAlignment.center,
    children: [text],
  );
}
