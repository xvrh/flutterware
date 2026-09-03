// Disposable spike fixtures: the hard-coded "agent drafts" of the coffee
// store banner and its intro — roughly right, to be refined by direct
// manipulation. Shared by the toy shells and the tests.
import 'package:flutterware/scene_authoring.dart';

SceneDocument coffeeBannerDraft() {
  var root = FrameNode(name: 'root')
    ..width = 1024
    ..height = 500
    ..fill = const SceneColor(0xFF2B1B12);

  var glow = ShapeNode(name: 'glow', circle: true)
    ..x = 600
    ..y = -110
    ..width = 480
    ..height = 480
    ..fill = const SceneColor(0xFF4A2F1F)
    ..opacity = 0.7;

  var cup = TextNode('☕', name: 'cup')
    ..x = 690
    ..y = 110
    ..fontSize = 190;

  var headline = TextNode('Fresh coffee, faster', name: 'headline')
    ..fontSize = 54
    ..weight = SceneFontWeight.w700
    ..color = const SceneColor(0xFFFFFFFF);

  var sub =
      TextNode('Order ahead. Skip the line. Earn rewards.', name: 'subtitle')
        ..fontSize = 20
        ..color = const SceneColor(0xFFD8C9BD);

  var ctaLabel = TextNode('Get the app', name: 'ctaLabel')
    ..fontSize = 17
    ..weight = SceneFontWeight.w600
    ..color = const SceneColor(0xFFFFFFFF);

  var cta = FrameNode(name: 'cta', layout: NodeLayout.row)
    ..padding = const SceneEdges.all(16)
    ..fill = const SceneColor(0xFFE8632B)
    ..corner = 28;
  cta.children.add(ctaLabel);

  var copy = FrameNode(name: 'copy', layout: NodeLayout.column)
    ..x = 64
    ..y = 120
    ..width = 500
    ..gap = 16
    ..crossAlign = SceneCrossAxisAlignment.start;
  copy.children.addAll([headline, sub, cta]);

  // External widgets — rendered as placeholders locally, natively in the
  // guest.
  var badge = ExternalNode('DrinkBadge', name: 'badge', args: {'size': 140.0})
    ..x = 560
    ..y = 290
    ..width = 140
    ..height = 140;
  var spinner = ExternalNode('Spinner', name: 'loading', args: {'size': 40.0})
    ..x = 950
    ..y = 430
    ..width = 40
    ..height = 40;
  var order =
      ExternalNode('OrderButton', name: 'order', args: {'label': 'Order now'})
        ..x = 830
        ..y = 400
        ..width = 150
        ..height = 44;

  root.children.addAll([glow, cup, copy, badge, spinner, order]);
  return SceneDocument(root);
}

/// The motion sibling of [coffeeBannerDraft], target names matching its node
/// fields.
MotionDocument coffeeIntroDraft() {
  var doc = MotionDocument(sceneClassName: 'BannerScene');
  doc.params.add(SceneParamDecl('slideFrom', SceneParamKind.number, 24.0));

  var headlineIn = AnimateGroup('headlineIn', 'headline');
  headlineIn.tracks['opacity'] = MotionTrack(TrackKind.number, [
    MotionKey(at: Duration.zero, value: 0.0),
    MotionKey(
      at: const Duration(milliseconds: 260),
      value: 1.0,
      curve: 'easeOut',
    ),
  ]);
  headlineIn.tracks['translateY'] = MotionTrack(TrackKind.number, [
    MotionKey(at: Duration.zero, value: 24.0, paramRef: 'slideFrom'),
    MotionKey(
      at: const Duration(milliseconds: 260),
      value: 0.0,
      curve: 'easeOut',
    ),
  ]);

  var glowMood = AnimateGroup('glowMood', 'glow');
  glowMood.tracks['opacity'] = MotionTrack(TrackKind.number, [
    MotionKey(at: Duration.zero, value: 1.0),
    MotionKey(at: const Duration(milliseconds: 900), value: 0.85),
    MotionKey(at: const Duration(milliseconds: 1800), value: 1.0),
  ]);

  var badgePop = AnimateGroup('badgePop', 'badge');
  badgePop.tracks['scale'] = MotionTrack(TrackKind.number, [
    MotionKey(at: Duration.zero, value: 0.6),
    MotionKey(
      at: const Duration(milliseconds: 240),
      value: 1.0,
      curve: 'easeOutBack',
    ),
  ]);
  badgePop.args['progress'] = MotionTrack(TrackKind.number, [
    MotionKey(at: Duration.zero, value: 0.0),
    MotionKey(at: const Duration(milliseconds: 300), value: 1.0),
  ]);

  // A library asset: not in the timeline, fired on events by its own player.
  var tapPulse = AnimateGroup('tapPulse', 'cta');
  tapPulse.tracks['scale'] = MotionTrack(TrackKind.number, [
    MotionKey(at: Duration.zero, value: 1.0),
    MotionKey(at: const Duration(milliseconds: 120), value: 1.06),
    MotionKey(at: const Duration(milliseconds: 240), value: 1.0),
  ]);

  doc.groups.addAll([headlineIn, glowMood, badgePop, tapPulse]);
  doc.timeline = ParExpr([
    GroupRef('headlineIn'),
    AtExpr(const Duration(milliseconds: 400), GroupRef('badgePop')),
    GroupRef('glowMood'),
  ]);
  return doc;
}
