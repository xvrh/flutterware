//@flutterware:scene=0.5
// Target two of three: an onboarding screen, authored once and run inside
// the app on whatever screen it is given.
//
// Everything dynamic arrives as a parameter, the way it would at runtime.
// The root fills both axes, so the phone decides the size and the column
// decides the arrangement — there are no authored coordinates in this file.
//
// Two things the grammar taught while this was written: a parameter default
// is one string literal, so the body copy sits on one long line; and a
// comment inside the class is refused, because the editor rewrites the file
// and would drop it. That is why these notes are up here.
//
// `width: double.infinity` is fill. The button takes the width the screen
// leaves it, on every phone, without anybody typing a number.

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
    width: double.infinity,
    fill: tint,
    corner: 28,
    layout: NodeLayout.row,
    mainAlign: MainAxisAlignment.center,
    padding: 16,
    children: [ctaLabel],
  );
  late final root = Frame(
    width: double.infinity,
    height: double.infinity,
    fill: Color(0xFFFFFBF8),
    layout: NodeLayout.column,
    mainAlign: MainAxisAlignment.center,
    crossAlign: CrossAxisAlignment.start,
    gap: 24,
    padding: 32,
    children: [art, heading, copy, ctaBox],
  );
}
