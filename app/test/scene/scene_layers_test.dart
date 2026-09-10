// The paint stack, through the grammar that spells it: a stack round-trips,
// every default is omitted, and each thing off the allowlist is refused by
// name rather than dropped.
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware/scene_authoring.dart';
import 'package:flutterware_app/src/scene/scene_file.dart';
import 'package:flutterware_app/src/scene/tokens_file.dart';

String _emit(List<TextLayer> layers) {
  var doc = SceneDocument(
    FrameNode(name: 'root')
      ..width = 100
      ..height = 100
      ..children.add(
        TextNode(
          'T',
          name: 't',
          style: SceneTextStyle(layers: layers),
        ),
      ),
  );
  return emitSceneFile(doc, className: 'Card');
}

List<TextLayer> _read(String source) {
  var parsed = parseSceneFile(source);
  expect(parsed.refusals, isEmpty, reason: parsed.refusals.join('\n'));
  return (parsed.doc!.root.children.single as TextNode).layers;
}

/// A scene whose one text carries [layers] verbatim, for the refusal cases.
String _scene(String layers) =>
    '''
$sceneFileMarker
import 'package:flutterware/scene_authoring.dart';

class Card extends SceneDefinition {
  late final t = TextNode('T', style: SceneTextStyle(layers: $layers));
  @override
  late final root = FrameNode(width: 100, height: 100, children: [t]);
}
''';

void main() {
  group('a paint stack', () {
    test('round-trips through the file, back to front', () {
      var layers = <TextLayer>[
        const FillLayer(
          paint: SolidPaint(SceneColor(0xFFFF2D95)),
          blur: 28,
          opacity: 0.9,
        ),
        const StrokeLayer(
          width: 14,
          join: SceneStrokeJoin.miter,
          paint: SolidPaint(SceneColor(0xFF120720)),
          dx: -1,
          dy: 2,
        ),
        const FillLayer(
          paint: LinearPaint(
            colors: [SceneColor(0xFFFFF3B0), SceneColor(0xFFFFB020)],
            stops: [0, 1],
            begin: SceneAlignment.centerLeft,
            end: SceneAlignment.centerRight,
          ),
        ),
      ];
      var out = _emit(layers);
      expect(_read(out), layers);
      expect(_emit(_read(out)), out, reason: 'emit ∘ parse is the identity');
    });

    test('writes nothing a default already says', () {
      var out = _emit(const [FillLayer(), StrokeLayer(width: 6)]);
      expect(out, contains('layers: [FillLayer(), StrokeLayer(width: 6)]'));
      expect(out, isNot(contains('join:')), reason: 'round is the default');
      expect(out, isNot(contains('opacity:')));
      expect(out, isNot(contains('blur:')));
    });

    test('an empty stack is the default, and is not written at all', () {
      expect(_emit(const []), isNot(contains('layers')));
      expect(_emit(const []), isNot(contains('style:')));
    });

    test('a fill with no paint takes the text’s own colour', () {
      // Null paint is the whole point of a stack that serves several
      // colours: the layer says how, the text says which.
      var layers = _read(_scene('[FillLayer()]'));
      expect(layers.single.paint, isNull);
    });

    test('refuses a pass that is not one, and names what is', () {
      var parsed = parseSceneFile(_scene('[GlowLayer()]'));
      expect(parsed.refusals.single.construct, 'layers');
      expect(parsed.refusals.single.message, contains('StrokeLayer'));
    });

    test('refuses a stack that is not a list', () {
      var parsed = parseSceneFile(_scene('FillLayer()'));
      expect(parsed.refusals.single.construct, 'layers');
      expect(parsed.refusals.single.message, contains('back to front'));
    });

    test('refuses a paint off the allowlist, and an unknown field', () {
      var parsed = parseSceneFile(_scene('[FillLayer(paint: Colors.red)]'));
      expect(parsed.refusals.single.construct, 'paint');
      parsed = parseSceneFile(_scene('[FillLayer(glow: 2)]'));
      expect(parsed.refusals.single.construct, 'layers');
      expect(parsed.refusals.single.message, contains('no "glow"'));
    });

    test('a stroke keeps its join and reads a negative offset', () {
      var layers = _read(
        _scene('[StrokeLayer(width: 9, join: SceneStrokeJoin.bevel, dy: -3)]'),
      );
      expect(
        layers.single,
        const StrokeLayer(width: 9, join: SceneStrokeJoin.bevel, dy: -3),
      );
    });

    test('refuses a gradient of one colour, and stops that do not fit', () {
      var parsed = parseSceneFile(
        _scene(
          '[FillLayer(paint: LinearPaint(colors: [SceneColor(0xFFFF0000)]))]',
        ),
      );
      expect(parsed.refusals.single.construct, 'paint');
      expect(parsed.refusals.single.message, contains('two colours'));
      parsed = parseSceneFile(
        _scene(
          '[FillLayer(paint: LinearPaint(colors: '
          '[SceneColor(0xFFFF0000), SceneColor(0xFF0000FF)], stops: [0]))]',
        ),
      );
      expect(parsed.refusals.single.construct, 'paint');
      expect(parsed.refusals.single.message, contains('one stop per colour'));
    });

    test('a radial gradient round-trips, and writes no default', () {
      var layers = <TextLayer>[
        const FillLayer(
          paint: RadialPaint(
            colors: [SceneColor(0xFFFFFFFF), SceneColor(0xFFFF2D95)],
            center: SceneAlignment(0.5, -0.25),
            radius: 1.2,
          ),
        ),
      ];
      var out = _emit(layers);
      expect(_read(out), layers);
      expect(_emit(_read(out)), out);
      // The formatter wraps `RadialPaint(colors: […])` onto its own line at
      // this nesting depth, so the check is by piece rather than one
      // contiguous substring: the colours are there and no default field is.
      var plain = _emit(const [
        FillLayer(
          paint: RadialPaint(
            colors: [SceneColor(0xFFFFFFFF), SceneColor(0xFF000000)],
          ),
        ),
      ]);
      expect(plain, contains('RadialPaint('));
      expect(
        plain,
        contains('colors: [SceneColor(0xFFFFFFFF), SceneColor(0xFF000000)]'),
      );
      expect(plain, isNot(contains('stops:')));
      expect(plain, isNot(contains('center:')));
      expect(plain, isNot(contains('radius:')));
    });

    test('a sweep gradient round-trips, and writes no default', () {
      var layers = <TextLayer>[
        const StrokeLayer(
          width: 6,
          paint: SweepPaint(
            colors: [SceneColor(0xFFFF2D95), SceneColor(0xFF00E5FF)],
            startAngle: 45,
            endAngle: 300,
          ),
        ),
      ];
      var out = _emit(layers);
      expect(_read(out), layers);
      expect(_emit(_read(out)), out);
      // The formatter wraps `SweepPaint(…)` onto its own lines at this
      // nesting depth (the same trap as RadialPaint above), so the check is
      // by piece rather than one contiguous substring: both angles are
      // written, with their values, and the round-trip identity checks above
      // already pin the semantics.
      expect(out, contains('startAngle: 45'));
      expect(out, contains('endAngle: 300'));
      expect(
        _emit(const [
          FillLayer(
            paint: SweepPaint(
              colors: [SceneColor(0xFFFF2D95), SceneColor(0xFF00E5FF)],
            ),
          ),
        ]),
        isNot(contains('Angle')),
      );
    });
  });

  group('a style token', () {
    test('declares a whole treatment, stack and all', () {
      var parsed = parseTokensFile('''
final sceneTokens = [
  const Token<SceneTextStyle>('display', SceneTextStyle(
    fontSize: 132,
    layers: [
      StrokeLayer(width: 12, paint: SolidPaint(SceneColor(0xFF120720))),
      FillLayer(paint: SolidPaint(SceneColor(0xFFFFC400))),
    ],
  )),
];
''');
      expect(parsed.refusals, isEmpty, reason: parsed.refusals.join('\n'));
      var style = parsed.tokens.single.style!;
      expect(style.fontSize, 132);
      expect(style.layers, [
        const StrokeLayer(width: 12, paint: SolidPaint(SceneColor(0xFF120720))),
        const FillLayer(paint: SolidPaint(SceneColor(0xFFFFC400))),
      ]);
    });

    test('a node bound to it inherits the stack, and overriding is whole', () {
      var declaration = '''
final sceneTokens = [
  const Token<SceneTextStyle>('display', SceneTextStyle(
    layers: [FillLayer(paint: SolidPaint(SceneColor(0xFFFFC400)))],
  )),
];
''';
      var tokens = parseTokensFile(declaration).tokens;
      var parsed = parseSceneFile('''
$sceneFileMarker
import 'package:flutterware/scene_authoring.dart';

import 'scene_args.dart';

class Card({final SceneTokens t = const SceneTokens()}) extends SceneDefinition {
  late final a = TextNode('A', style: t.display);
  late final b = TextNode('B', style: t.display.copyWith(layers: [StrokeLayer(width: 3)]));
  @override
  late final root = FrameNode(width: 100, height: 100, children: [a, b]);
}
''', tokens: tokens);
      expect(parsed.refusals, isEmpty, reason: parsed.refusals.join('\n'));
      var doc = parsed.doc!;
      expect((doc.nodeNamed('a')! as TextNode).layers, [
        const FillLayer(paint: SolidPaint(SceneColor(0xFFFFC400))),
      ], reason: 'inherited');
      expect((doc.nodeNamed('b')! as TextNode).layers, [
        const StrokeLayer(width: 3),
      ], reason: 'anonymous lists cannot merge: an override replaces');
      var out = emitSceneFile(doc, className: 'Card', imports: parsed.imports);
      expect(
        out,
        contains("TextNode('A', style: t.display)"),
        reason: 'absent',
      );
      expect(out, contains('layers: [StrokeLayer(width: 3)]'));
    });
  });
}
