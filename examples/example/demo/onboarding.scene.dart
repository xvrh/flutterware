//@flutterware:scene=0.5
// Target two of three: an onboarding screen, authored on a phone and meant
// to run inside the app on whatever screen it is given.
//
// Everything dynamic arrives as a parameter, the way it would at runtime.
// The authored size is a phone; the question this target exists to ask is
// what happens on a screen that is not that phone.

class Onboarding({
  final String title = 'Skip the queue',
  // One literal, on one line: the grammar takes a single string literal for
  // a default, and adjacent-string concatenation is refused.
  final String body = 'Order before you arrive and pick it up from the counter. Every tenth coffee is on us.',
  final String cta = 'Get started',
  final Color tint = const Color(0xFFE8632B),
}) {
  late final art = Shape(
    width: 200,
    height: 200,
    fill: Color(0xFFF3E9E1),
    circle: true,
  );
  late final cup = Text('☕', fontSize: 96);
  late final artStack = Frame(
    width: 200,
    height: 200,
    layout: NodeLayout.row,
    mainAlign: MainAxisAlignment.center,
    crossAlign: CrossAxisAlignment.center,
    children: [cup],
  );
  late final heading = Text(
    title,
    fontSize: 30,
    weight: FontWeight.w700,
    color: Color(0xFF1B1210),
  );
  late final copy = Text(body, fontSize: 16, color: Color(0xFF6B5A52));
  late final ctaLabel = Text(
    cta,
    fontSize: 17,
    weight: FontWeight.w600,
    color: Color(0xFFFFFFFF),
  );
  late final ctaBox = Frame(
    width: 310,
    fill: tint,
    corner: 28,
    layout: NodeLayout.row,
    mainAlign: MainAxisAlignment.center,
    padding: 16,
    children: [ctaLabel],
  );
  late final column = Frame(
    x: 40,
    y: 140,
    width: 310,
    layout: NodeLayout.column,
    gap: 24,
    crossAlign: CrossAxisAlignment.start,
    children: [art, heading, copy, ctaBox],
  );
  late final root = Frame(
    width: 390,
    height: 844,
    fill: Color(0xFFFFFBF8),
    children: [column, artStack],
  );
}
