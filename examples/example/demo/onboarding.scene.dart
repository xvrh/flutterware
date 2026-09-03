//@flutterware:scene=0.5
// Owned by the flutterware scene editor, which reads and writes this whole
// file. Hand edits are welcome inside the grammar: every node is a
// `late final` field (the field name is the node's identity), placed exactly
// once in a children list; a parameter is a `final` in the class header
// whose default is the mockup. Anything outside the grammar is refused with
// a line number rather than silently dropped.

class Onboarding({
  final String title = 'Skip the queue',
  final String body = 'Order before you arrive and pick it up from the counter. Every tenth coffee is on us.',
  final String cta = 'Get started',
  final Color tint = const Color(0xFFE8632B),
}) {
  late final cup = Text('☕', fontSize: 96);
  late final art = Frame(
    width: 200,
    height: 200,
    fill: Color(0xFFF3E9E1),
    corner: 100,
    layout: NodeLayout.row,
    mainAlign: MainAxisAlignment.center,
    children: [cup],
  );
  late final heading = Text(
    title,
    fontSize: 30,
    weight: FontWeight.w700,
    color: Color(0xFF1B1210),
  );
  late final copy = Text(body, color: Color(0xFF6B5A52));
  late final ctaLabel = Text(
    cta,
    y: 13.579370847176051,
    fontSize: 17,
    weight: FontWeight.w600,
    color: Color(0xFFFFFFFF),
  );
  late final ctaBox = Frame(
    width: double.infinity,
    fill: tint,
    corner: 28,
    layout: NodeLayout.row,
    padding: 16,
    mainAlign: MainAxisAlignment.center,
    crossAlign: CrossAxisAlignment.start,
    children: [ctaLabel],
  );
  late final root = Frame(
    width: double.infinity,
    height: double.infinity,
    fill: Color(0xFFFFFBF8),
    layout: NodeLayout.column,
    gap: 24,
    padding: 32,
    mainAlign: MainAxisAlignment.center,
    crossAlign: CrossAxisAlignment.start,
    children: [art, heading, copy, ctaBox],
  );
}
