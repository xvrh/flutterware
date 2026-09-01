//@flutterware:motion=0.1
// Owned by the flutterware motion editor, which reads and writes this whole
// file. Hand edits are welcome inside the grammar: a group is a `late final`
// field animating one scene node (the field name is the group's identity),
// the `timeline` field is what plays, a group left out of it is a library
// asset, and `copy` is derived — the editor rewrites it. Anything outside
// the grammar is refused with a line number rather than silently dropped.

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
