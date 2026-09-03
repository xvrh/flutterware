//@flutterware:scene=0.6
// Owned by the flutterware scene editor, which reads and writes this whole
// file. Hand edits are welcome inside the grammar: every node is a
// `late final` field (the field name is the node's identity), placed exactly
// once in a children list; a parameter is a `final` in the class header
// whose default is the mockup. Anything outside the grammar is refused with
// a line number rather than silently dropped.

class BannerScene {
  late final glow = Shape(
    x: 600,
    y: -110,
    width: 480,
    height: 480,
    fill: Color(0xFF4A2F1F),
    opacity: 0.7,
    circle: true,
  );
  late final cup = Text('☕', x: 690, y: 110, fontSize: 190);
  late final headline = Text(
    'Fresh coffee, faster',
    fontSize: 54,
    weight: FontWeight.w700,
    color: Color(0xFFFFFFFF),
  );
  late final subtitle = Text(
    'Order ahead. Skip the line. Earn rewards.',
    fontSize: 20,
    color: Color(0xFFD8C9BD),
  );
  late final ctaLabel = Text(
    'Get the app',
    fontSize: 17,
    weight: FontWeight.w600,
    color: Color(0xFFFFFFFF),
  );
  late final cta = Frame(
    fill: Color(0xFFE8632B),
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
    children: [headline, subtitle, cta],
  );
  late final badge = Ext(
    DrinkBadge,
    x: 560,
    y: 290,
    width: 140,
    height: 140,
    args: {'size': 140},
  );
  late final loading = Ext(
    Spinner,
    x: 950,
    y: 430,
    width: 40,
    height: 40,
    args: {'size': 40},
  );
  late final order = Ext(
    OrderButton,
    x: 830,
    y: 400,
    width: 150,
    height: 44,
    args: {'label': 'Order now'},
  );
  late final promo = Scene(
    PromoBadge,
    x: 64,
    y: 48,
    args: {'label': 'Now open'},
  );
  late final root = Frame(
    width: 1024,
    height: 500,
    fill: Color(0xFF2B1B12),
    children: [glow, cup, copy, badge, loading, order, promo],
  );
}

class BannerIntro(super.scene, {final double slideFrom = 24})
    extends SceneMotion<BannerScene> {
  late final headlineIn = scene.headline.animate(
    opacity: Track([
      Key(at: 0.ms, value: 0),
      Key(at: 260.ms, value: 1, curve: Curves.easeOut),
    ]),
    translateY: Track([
      Key(at: 0.ms, value: slideFrom),
      Key(at: 260.ms, value: 0, curve: Curves.easeOut),
    ]),
  );
  late final glowMood = scene.glow.animate(
    opacity: Track([
      Key(at: 0.ms, value: 1),
      Key(at: 900.ms, value: 0.85),
      Key(at: 1800.ms, value: 1),
    ]),
  );
  late final badgePop = scene.badge.animate(
    scale: Track([
      Key(at: 0.ms, value: 0.6),
      Key(at: 240.ms, value: 1, curve: Curves.easeOutBack),
    ]),
    args: {
      'progress': Track([Key(at: 0.ms, value: 0), Key(at: 300.ms, value: 1)]),
    },
  );
  late final tapPulse = scene.cta.animate(
    scale: Track([
      Key(at: 0.ms, value: 1),
      Key(at: 120.ms, value: 1.06),
      Key(at: 240.ms, value: 1),
    ]),
  );
  late final timeline = Par([headlineIn, At(400.ms, badgePop), glowMood]);
  BannerIntro copy(BannerScene scene) =>
      copyStateInto(BannerIntro(scene, slideFrom: slideFrom));
}
