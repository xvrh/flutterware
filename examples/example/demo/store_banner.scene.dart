//@flutterware:scene=0.5
// Target one of three: a store banner whose copy is a typed hole, so one
// scene is exported once per language.
//
// The mockup is English. What an export loop fills in is the parameters
// below; nothing else about the scene changes between languages.

class StoreBanner({
  final String headline = 'Fresh coffee, faster',
  final String subtitle = 'Order ahead. Skip the line. Earn rewards.',
  final String cta = 'Get the app',
  final Color tint = const Color(0xFFE8632B),
}) {
  late final title = Text(
    headline,
    fontSize: 54,
    weight: FontWeight.w700,
    color: Color(0xFFFFFFFF),
  );
  late final sub = Text(subtitle, fontSize: 20, color: Color(0xFFD8C9BD));
  late final ctaLabel = Text(
    cta,
    fontSize: 17,
    weight: FontWeight.w600,
    color: Color(0xFFFFFFFF),
  );
  late final ctaBox = Frame(
    fill: tint,
    corner: 28,
    layout: NodeLayout.row,
    padding: 16,
    children: [ctaLabel],
  );
  late final copy = Frame(
    x: 64,
    y: 120,
    width: 500,
    layout: NodeLayout.column,
    gap: 16,
    crossAlign: CrossAxisAlignment.start,
    children: [title, sub, ctaBox],
  );
  late final glow = Shape(
    x: 620,
    y: -90,
    width: 460,
    height: 460,
    fill: Color(0xFF4A2F1F),
    opacity: 0.7,
    circle: true,
  );
  late final cup = Text('☕', x: 700, y: 120, fontSize: 180);
  late final root = Frame(
    width: 1024,
    height: 500,
    fill: Color(0xFF2B1B12),
    children: [glow, cup, copy],
  );
}
