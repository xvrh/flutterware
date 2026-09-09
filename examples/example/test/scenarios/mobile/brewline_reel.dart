import 'dart:ui';

import 'package:flutterware/reel.dart';
import 'package:flutterware/scene_authoring.dart';

/// The shop's own reel: how a Brewline scenario is cut when it is rendered
/// with `--reel=true`.
///
/// An edit is a pure function from a [Take] — the beats of a dry run, as
/// types, with the cues the scenario said — to a [Reel]: a scene for the
/// picture and a motion for the timing. This one knows the shop: its colours,
/// its copy, and two cues of its own that the scenario emits and nothing
/// else understands ([Callout], [Receipt]). Everything it draws is a scene
/// node and everything it moves is a motion track, so it composes with the
/// editor's vocabulary rather than adding one.
///
/// What it does with a take, in order:
///
/// - the app sits in a rounded device on a roast-brown ground, under the
///   wordmark, and *arrives*: scaled up from 94% over the opening hold;
/// - every `s.title` is a lower third, faded in and out;
/// - every tap pushes the camera in on the target, starting **before** the
///   press — the edit read the take, so it knows what is about to happen;
/// - a [Callout] is a pill hung above the *next* tap's target, gone when the
///   finger lands;
/// - typing pushes in on the field for as long as the words go in;
/// - the cart is frozen for a beat with the price called out — a **freeze**:
///   the picture stops, cursor and all;
/// - the confirmation is **held** — the app keeps running, which is what a
///   freeze cannot do;
/// - the [Receipt] closes: the device dims, the thanks and the order come up,
///   and the last frame holds.
class BrewlineReel extends ScenarioReelEdit {
  const BrewlineReel();

  static const _ground = SceneColor(0xFF2B1D14);
  static const _cream = SceneColor(0xFFF3E9DF);
  static const _latte = SceneColor(0xFFD8C9BD);
  static const _accent = SceneColor(0xFFE6B980);
  static const _band = SceneColor(0xD92B1D14);

  static const _margin = 40.0;
  static const _header = 120.0;
  static const _zoom = 1.5;
  static const _pushIn = Duration(milliseconds: 420);
  static const _titleFor = Duration(milliseconds: 2000);

  @override
  Reel edit(Take take) {
    var screen = take.screen;
    var w = screen.width;
    var h = screen.height;

    // The picture. The camera is what a push-in scales; the device is what
    // clips it to rounded corners and never moves, so the frame stays put
    // while the app inside it comes closer.
    var camera = FrameNode(name: 'camera', clip: true)
      ..width = w
      ..height = h
      ..children.addAll([
        ExternalNode(const ScreenArgs(), name: 'screen')
          ..width = w
          ..height = h,
        ExternalNode(const PointerArgs(), name: 'pointer')
          ..width = w
          ..height = h,
      ]);
    var device = FrameNode(name: 'device', clip: true, corner: 36)
      ..x = _margin
      ..y = _header
      ..width = w
      ..height = h
      ..borderColor = const SceneColor(0x33FFFFFF)
      ..borderWidth = 2
      ..children.add(camera);
    var wordmark = TextNode('Brewline', name: 'wordmark')
      ..x = _margin
      ..y = 34
      ..fontSize = 34
      ..weight = SceneFontWeight.w800
      ..color = _cream;
    var tagline =
        TextNode('Your coffee, ready before you are.', name: 'tagline')
          ..x = _margin
          ..y = 80
          ..fontSize = 15
          ..color = _latte;
    var root = FrameNode(name: 'root')
      ..width = w + 2 * _margin
      ..height = h + _header + _margin
      ..fill = _ground
      ..children.addAll([device, wordmark, tagline]);

    var motion = MotionDocument(sceneClassName: 'BrewlineReel');
    var placed = <TimelineExpr>[];
    void at(Duration when, AnimateGroup group) {
      motion.groups.add(group);
      placed.add(AtExpr(when, group));
    }

    var b = ReelBuilder(take);
    var beats = take.beats;

    // The device arrives over the opening hold, the wordmark a breath later.
    at(
      Duration.zero,
      AnimateGroup(device, name: 'arrive')
        ..tracks['scale'] = MotionTrack([
          MotionKey(
            at: Duration.zero,
            value: 0.94,
            curve: SceneCurves.easeOutCubic,
          ),
          MotionKey(at: const Duration(milliseconds: 700), value: 1.0),
        ])
        ..tracks['opacity'] = MotionTrack([
          MotionKey(at: Duration.zero, value: 0.0, curve: SceneCurves.easeOut),
          MotionKey(at: const Duration(milliseconds: 500), value: 1.0),
        ]),
    );
    for (var (i, node) in [wordmark, tagline].indexed) {
      at(
        Duration(milliseconds: 200 + 120 * i),
        AnimateGroup(node, name: '${node.name}In')
          ..tracks['opacity'] = MotionTrack([
            MotionKey(
              at: Duration.zero,
              value: 0.0,
              curve: SceneCurves.easeOut,
            ),
            MotionKey(at: const Duration(milliseconds: 400), value: 1.0),
          ])
          ..tracks['translateY'] = MotionTrack([
            MotionKey(
              at: Duration.zero,
              value: -12.0,
              curve: SceneCurves.easeOutCubic,
            ),
            MotionKey(at: const Duration(milliseconds: 400), value: 0.0),
          ]),
      );
    }

    var captions = 0;
    var callouts = 0;
    Receipt? receipt;
    for (var (i, beat) in beats.indexed) {
      switch (beat) {
        case Said(cue: ScenarioTitle(:var text)):
          // A lower third on the root, outside the camera: a caption does
          // not zoom with the app it is captioning. Unless the next tap
          // lands under it — then it is an upper third, because the take
          // already says where the finger is going.
          var n = captions++;
          var next = beats.skip(i + 1).whereType<Tapped>().firstOrNull;
          var low = (next?.target?.center.dy ?? 0) > h * 0.72;
          var top = low ? _header + 20 : _header + h - 96;
          var band = ShapeNode(name: 'band$n', corner: 12)
            ..x = _margin + 16
            ..y = top
            ..width = w - 32
            ..height = 60
            ..fill = _band;
          var caption = TextNode(text, name: 'caption$n', maxLines: 1)
            ..x = _margin + 28
            ..y = top + 16
            ..width = w - 56
            ..fontSize = 20
            ..weight = SceneFontWeight.w700
            ..color = _cream;
          root.children.addAll([band, caption]);
          var when = b.reelTimeOf(beat.at) ?? b.reel;
          for (var node in [band, caption]) {
            at(
              when,
              AnimateGroup(node, name: '${node.name}Fade')
                ..tracks['opacity'] = MotionTrack(_fade(_titleFor)),
            );
          }
          at(
            when,
            AnimateGroup(caption, name: 'caption${n}Rise')
              ..tracks['translateY'] = MotionTrack([
                MotionKey(
                  at: Duration.zero,
                  value: 10.0,
                  curve: SceneCurves.easeOutCubic,
                ),
                MotionKey(at: const Duration(milliseconds: 350), value: 0.0),
              ]),
          );
          b.say(ScenarioTitle(text), over: _titleFor, at: when);

        case Said(cue: Callout(:var text)):
          // Hung above the next tap's target, which the take already knows.
          var next = beats.skip(i + 1).whereType<Tapped>().firstOrNull;
          var target = next?.target;
          if (next == null || target == null) break;
          var n = callouts++;
          var width = 16.0 * text.length + 28;
          var x = (target.center.dx - width / 2).clamp(12.0, w - width - 12);
          var y = target.top - 56;
          var pill = FrameNode(name: 'callout$n', corner: 18)
            ..x = x
            ..y = y
            ..width = width
            ..height = 36
            ..fill = _accent;
          var label =
              TextNode(
                  text,
                  name: 'calloutText$n',
                  align: SceneTextAlign.center,
                )
                ..x = x
                ..y = y + 8
                ..width = width
                ..fontSize = 15
                ..weight = SceneFontWeight.w700
                ..color = _ground;
          camera.children.addAll([pill, label]);
          // The screen it points at has just settled — the previous tap's
          // dwell — and the viewer needs longer than a dwell to read it, so
          // that pause is *held*: the app keeps running for another 600ms.
          // Shown from the dwell's start until the finger lands on the
          // target, which is the press phase of the next tap in reel time.
          var prev = beats.take(i).whereType<Tapped>().lastOrNull;
          var dwell = prev?.phase(PhaseKind.dwell);
          if (prev != null) {
            b.hold(const Duration(milliseconds: 600), after: prev);
          }
          var shown = (dwell == null ? null : b.reelTimeOf(dwell.at)) ?? b.reel;
          var press = next.phase(PhaseKind.press) ?? next.phases.first;
          var until =
              (press.at - next.at) + _timeAfterPlaying(b, beats, i, next);
          var over = until - shown;
          if (over <= Duration.zero) over = const Duration(milliseconds: 600);
          for (var node in [pill, label]) {
            at(
              shown,
              AnimateGroup(node, name: '${node.name}Pop')
                ..tracks['opacity'] = MotionTrack(
                  _fade(over, edge: const Duration(milliseconds: 200)),
                )
                ..tracks['scale'] = MotionTrack([
                  MotionKey(
                    at: Duration.zero,
                    value: 0.6,
                    curve: SceneCurves.easeOutBack,
                  ),
                  MotionKey(at: const Duration(milliseconds: 300), value: 1.0),
                ]),
            );
          }

        case Said(cue: Receipt r):
          receipt = r;

        case Tapped(:var target?):
          // In before the press, out just after it: the screen a tap opens
          // should arrive at its own size, not magnified around a button
          // that is no longer there.
          var press = beat.phase(PhaseKind.press) ?? beat.phases.first;
          var start = b.reel + (press.at - beat.at) - _pushIn;
          if (start < Duration.zero) start = Duration.zero;
          at(
            start,
            _push(
              camera,
              screen,
              target.center,
              release:
                  (press.end - beat.at) +
                  b.reel -
                  start +
                  const Duration(milliseconds: 150),
              name: 'push$i',
            ),
          );
          b.playBeat(beat);
          // The cart, frozen: the picture stops — cursor and all — while the
          // price is read.
          if (beat.label?.contains('addToCart') ?? false) {
            _priceTag(root, screen, b, take, at);
          }
          // The confirmation, held: the app keeps running through it.
          if (beat.label?.contains('placeOrder') ?? false) {
            b.hold(const Duration(milliseconds: 1400), after: beat);
          }

        case Typed(:var field?):
          at(
            b.reel,
            _push(
              camera,
              screen,
              field.center,
              release: beat.duration - _pushIn,
              name: 'typing',
              zoom: 1.35,
            ),
          );
          b.playBeat(beat);

        case _:
          b.playBeat(beat);
      }
    }

    // The close: the device dims, the receipt comes up, the frame holds.
    var thanks =
        TextNode(
            receipt == null ? take.scenario : 'Thanks, ${receipt.name}.',
            name: 'thanks',
            align: SceneTextAlign.center,
          )
          ..x = _margin
          ..y = _header + h * 0.30
          ..width = w
          ..fontSize = 36
          ..weight = SceneFontWeight.w800
          ..color = _cream;
    var order =
        TextNode(
            receipt == null ? '' : '${receipt.order} · ${receipt.price}',
            name: 'order',
            align: SceneTextAlign.center,
          )
          ..x = _margin
          ..y = _header + h * 0.30 + 56
          ..width = w
          ..fontSize = 20
          ..color = _accent;
    var footer =
        TextNode('brewline.app', name: 'footer', align: SceneTextAlign.center)
          ..x = _margin
          ..y = _header + h - 60
          ..width = w
          ..fontSize = 16
          ..color = _latte;
    root.children.addAll([thanks, order, footer]);
    var close = b.reel;
    at(
      close,
      AnimateGroup(device, name: 'dim')
        ..tracks['opacity'] = MotionTrack([
          MotionKey(
            at: Duration.zero,
            value: 1.0,
            curve: SceneCurves.easeInOut,
          ),
          MotionKey(at: const Duration(milliseconds: 600), value: 0.1),
        ])
        ..tracks['scale'] = MotionTrack([
          MotionKey(
            at: Duration.zero,
            value: 1.0,
            curve: SceneCurves.easeInOut,
          ),
          MotionKey(at: const Duration(milliseconds: 600), value: 0.96),
        ]),
    );
    for (var (i, node) in [thanks, order, footer].indexed) {
      at(
        close + Duration(milliseconds: 250 + 150 * i),
        AnimateGroup(node, name: '${node.name}In')
          ..tracks['opacity'] = MotionTrack([
            MotionKey(
              at: Duration.zero,
              value: 0.0,
              curve: SceneCurves.easeOut,
            ),
            MotionKey(at: const Duration(milliseconds: 450), value: 1.0),
          ])
          ..tracks['translateY'] = MotionTrack([
            MotionKey(
              at: Duration.zero,
              value: 16.0,
              curve: SceneCurves.easeOutCubic,
            ),
            MotionKey(at: const Duration(milliseconds: 450), value: 0.0),
          ]),
      );
    }
    b.freeze(const Duration(milliseconds: 2200));

    motion.timeline = ParExpr(placed);
    var scene = SceneDocument(root);
    return b.build(
      stage: SceneStage(scene, motion: BoundMotion.bind(motion, scene)),
    );
  }

  /// A push-in on [toward], held until [release] and then let go.
  static AnimateGroup _push(
    FrameNode camera,
    Size screen,
    Offset toward, {
    required Duration release,
    required String name,
    double zoom = _zoom,
  }) {
    var off = cameraOffset(screen: screen, toward: toward, zoom: zoom);
    var back = release < _pushIn ? _pushIn : release;
    var over = back + _pushIn;
    List<MotionKey> keys(double rest, double moved) => [
      MotionKey(
        at: Duration.zero,
        value: rest,
        curve: SceneCurves.easeOutCubic,
      ),
      MotionKey(at: _pushIn, value: moved),
      MotionKey(at: back, value: moved, curve: SceneCurves.easeInOut),
      MotionKey(at: over, value: rest),
    ];
    return AnimateGroup(camera, name: name)
      ..tracks['scale'] = MotionTrack(keys(1.0, zoom))
      ..tracks['translateX'] = MotionTrack(keys(0.0, off.dx))
      ..tracks['translateY'] = MotionTrack(keys(0.0, off.dy));
  }

  /// The price, called out over a frozen cart.
  static void _priceTag(
    FrameNode root,
    Size screen,
    ReelBuilder b,
    Take take,
    void Function(Duration when, AnimateGroup group) at,
  ) {
    var receipt = take.beats
        .whereType<Said>()
        .map((s) => s.cue)
        .whereType<Receipt>()
        .firstOrNull;
    if (receipt == null) return;
    const freeze = Duration(milliseconds: 1100);
    var tag = FrameNode(name: 'priceTag', corner: 30)
      ..x = _margin + screen.width / 2 - 110
      ..y = _header + screen.height / 2 - 30
      ..width = 220
      ..height = 60
      ..fill = _accent;
    var price =
        TextNode(receipt.price, name: 'priceText', align: SceneTextAlign.center)
          ..x = tag.x
          ..y = tag.y + 12
          ..width = tag.width
          ..fontSize = 28
          ..weight = SceneFontWeight.w800
          ..color = _ground;
    root.children.addAll([tag, price]);
    for (var node in [tag, price]) {
      at(
        b.reel,
        AnimateGroup(node, name: '${node.name}Pop')
          ..tracks['opacity'] = MotionTrack(
            _fade(freeze, edge: const Duration(milliseconds: 180)),
          )
          ..tracks['scale'] = MotionTrack([
            MotionKey(
              at: Duration.zero,
              value: 0.5,
              curve: SceneCurves.elasticOut,
            ),
            MotionKey(at: const Duration(milliseconds: 500), value: 1.0),
          ]),
      );
    }
    b.freeze(freeze);
  }

  /// Where [next] will start in reel time, given that every beat between
  /// [i] and it is played whole — which this edit does.
  static Duration _timeAfterPlaying(
    ReelBuilder b,
    List<Beat> beats,
    int i,
    Beat next,
  ) {
    var reel = b.reel;
    for (var beat in beats.skip(i + 1)) {
      if (identical(beat, next)) return reel;
      if (beat is! Said) reel += beat.duration;
    }
    return reel;
  }

  static List<MotionKey> _fade(
    Duration over, {
    Duration edge = const Duration(milliseconds: 350),
  }) => [
    MotionKey(at: Duration.zero, value: 0.0, curve: SceneCurves.easeOut),
    MotionKey(at: edge, value: 1.0),
    MotionKey(at: over - edge, value: 1.0, curve: SceneCurves.easeIn),
    MotionKey(at: over, value: 0.0),
  ];
}

/// "Look here next": a pill the edit hangs over the next thing tapped.
class Callout implements ScenarioCueData {
  const Callout(this.text);

  final String text;

  @override
  Map<String, Object?> toJson() => {'text': text};

  @override
  String toString() => 'callout: $text';
}

/// What was ordered, for the close.
class Receipt implements ScenarioCueData {
  const Receipt({required this.name, required this.order, required this.price});

  final String name;
  final String order;
  final String price;

  @override
  Map<String, Object?> toJson() => {
    'name': name,
    'order': order,
    'price': price,
  };

  @override
  String toString() => 'receipt: $order for $name, $price';
}
