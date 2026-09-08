// Styles: a text style is a token that bundles the text subset of the
// table, applied whole and overridden per property.
//
// The file's rule is the one the plan decided (§4.3): what the node spells
// beside `style:` is an override, what it leaves out is inherited, and a
// property spelled equal to the style's is inherited — there is no flag.
// So the graders here are the round trip on both sides of that line, the
// constructor resolving the same way a parsed node does, and the editor's
// three doors: apply, override (any edit), reset.
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware/scene_authoring.dart' hide Token;
import 'package:flutterware_app/src/scene/args_codegen.dart';
import 'package:flutterware_app/src/scene/editor.dart';
import 'package:flutterware_app/src/scene/scene_file.dart';
import 'package:flutterware_app/src/scene/tokens_file.dart';

const _declaration = '''
import 'package:flutterware/scene_authoring.dart';

final sceneTokens = [
  const Token<SceneColor>('ink', SceneColor(0xFF111111)),
  const Token<SceneTextStyle>(
    'title',
    SceneTextStyle(fontSize: 54, weight: SceneFontWeight.w700, align: SceneTextAlign.center),
  ),
  const Token<SceneTextStyle>('body', SceneTextStyle(fontSize: 20, color: SceneColor(0xFFD8C9BD), maxLines: 2)),
];
''';

final _tokens = parseTokensFile(_declaration).tokens;

const _scene =
    '''
$sceneFileMarker
import 'package:flutterware/scene_authoring.dart';

import 'scene_args.dart';

class Card({final SceneTokens t = const SceneTokens()}) extends SceneDefinition {
  late final headline = TextNode('Hello', style: t.title, color: t.ink);
  late final sub = TextNode('Sub', style: t.body, fontSize: 24);
  late final plain = TextNode('Plain', fontSize: 12);
  @override
  late final root = FrameNode(width: 200, height: 100, children: [headline, sub, plain]);
}
''';

SceneParse _parse(String source) => parseSceneFile(source, tokens: _tokens);

String _emit(SceneDocument doc) => emitSceneFile(doc, className: 'Card');

void main() {
  group('the declaration', () {
    test('reads a style token, each field a literal of its kind', () {
      var parsed = parseTokensFile(_declaration);
      expect(parsed.refusals, isEmpty, reason: parsed.refusals.join('\n'));
      var title = parsed.tokens[1];
      expect(title.isStyle, isTrue);
      expect(title.isOpaque, isFalse);
      expect(title.typeName, 'SceneTextStyle');
      expect(title.style!.fontSize, 54);
      expect(title.style!.weight, SceneFontWeight.w700);
      expect(title.style!.align, SceneTextAlign.center);
      expect(title.style!.color, isNull);
      expect(parsed.tokens[2].style!.maxLines, 2);
      expect(parsed.tokens[2].style!.values.keys, [
        'fontSize',
        'color',
        'maxLines',
      ]);
    });

    test('refuses a field that is not one; a style is whole per mode', () {
      var parsed = parseTokensFile('''
final sceneTokens = [
  Token<SceneTextStyle>('a', SceneTextStyle(kerning: 2)),
  Token<SceneTextStyle>('b', SceneTextStyle(fontSize: 10), modes: {'dark': SceneTextStyle(fontSize: 12, color: SceneColor(0xFFFFFFFF))}),
  Token<SceneTextStyle>('c', SceneTextStyle(fontSize: 10), modes: {'dark': 3}),
];
''');
      expect(parsed.refusals.map((r) => r.construct), ['style', 'token value']);
      var b = parsed.tokens.single;
      expect(
        b.styleIn('dark'),
        const SceneTextStyle(fontSize: 12, color: SceneColor(0xFFFFFFFF)),
      );
      expect(b.styleIn('sepia'), b.style, reason: 'no value there: default');
      expect(b.styleIn(null), b.style);
    });

    test('is a const field on the generated class', () {
      var source = emitSceneArgs(externals: [], scenes: [], tokens: _tokens);
      expect(source, contains('final SceneTextStyle title;'));
      var flat = source.replaceAll(RegExp(r'\s+'), ' ');
      expect(
        flat,
        contains(
          'this.title = const SceneTextStyle( fontSize: 54.0, '
          'weight: SceneFontWeight.w700, align: SceneTextAlign.center, )',
        ),
      );
      expect(flat, contains('color: SceneColor(0xFFD8C9BD), maxLines: 2'));
    });
  });

  group('a style in a mode', () {
    final tokens = parseTokensFile('''
final sceneTokens = [
  const Token<SceneColor>('ink', SceneColor(0xFF111111)),
  const Token<SceneTextStyle>(
    'title',
    SceneTextStyle(fontSize: 54, weight: SceneFontWeight.w700, align: SceneTextAlign.center),
    modes: {'dark': SceneTextStyle(fontSize: 40, weight: SceneFontWeight.w900, color: SceneColor(0xFFFFFFFF))},
  ),
  const Token<SceneTextStyle>('body', SceneTextStyle(fontSize: 20, color: SceneColor(0xFFD8C9BD), maxLines: 2)),
];
''').tokens;

    SceneEditor open() =>
        SceneEditor(parseSceneFile(_scene, tokens: tokens).doc!);

    test('the mode switch moves what was inherited, and back', () {
      var e = open();
      var headline = e.doc.nodeNamed('headline')! as TextNode;
      var sub = e.doc.nodeNamed('sub')! as TextNode;
      e.tokenMode = 'dark';
      expect(headline.fontSize, 40);
      expect(headline.weight, SceneFontWeight.w900);
      expect(
        headline.color,
        const SceneColor(0xFF111111),
        reason: 'bound to ink on its own: the binding wins over the style',
      );
      expect(sub.fontSize, 24, reason: 'body has no dark style');
      e.tokenMode = null;
      expect(headline.fontSize, 54);
      expect(headline.weight, SceneFontWeight.w700);
    });

    test('an override survives the switch; the file follows the mode', () {
      var e = open();
      var headline = e.doc.nodeNamed('headline')! as TextNode;
      e.perform('Size', () => headline.fontSize = 30);
      e.tokenMode = 'dark';
      expect(headline.fontSize, 30, reason: 'an override');
      expect(headline.weight, SceneFontWeight.w900, reason: 'inherited');
      var dark = _emit(e.doc);
      expect(dark, contains('fontSize: 30'));
      expect(dark, isNot(contains('weight:')), reason: 'inherited in dark');
      e.tokenMode = null;
      expect(_emit(e.doc), isNot(contains('weight:')));
    });

    test('the generated set carries the whole style of the mode', () {
      var source = emitSceneArgs(externals: [], scenes: [], tokens: tokens);
      var flat = source.replaceAll(RegExp(r'\s+'), ' ');
      expect(
        flat,
        contains(
          'static const dark = SceneTokens( title: SceneTextStyle( '
          'fontSize: 40.0, weight: SceneFontWeight.w900, '
          'color: SceneColor(0xFFFFFFFF), ), );',
        ),
      );
    });

    test('a declared mode no token differs in is a static too', () {
      var source = emitSceneArgs(
        externals: [],
        scenes: [],
        tokens: tokens,
        modes: const ['dense'],
      );
      expect(source, contains('static const dense = SceneTokens();'));
      expect(source, contains("'dark': dark, 'dense': dense"));
    });
  });

  group('a text taking a style', () {
    test('inherits what it does not spell, overrides what it does', () {
      var parsed = _parse(_scene);
      expect(parsed.refusals, isEmpty, reason: parsed.refusals.join('\n'));
      var doc = parsed.doc!;
      var headline = doc.nodeNamed('headline')! as TextNode;
      expect(headline.bindings[styleBindingKey], const StyleRef('title'));
      expect(headline.fontSize, 54);
      expect(headline.weight, SceneFontWeight.w700);
      expect(headline.align, SceneTextAlign.center);
      expect(headline.color, const SceneColor(0xFF111111), reason: 'override');
      expect(headline.bindings['color'], const TokenRef('ink'));
      var sub = doc.nodeNamed('sub')! as TextNode;
      expect(sub.fontSize, 24, reason: "its own, over the style's 20");
      expect(sub.color, const SceneColor(0xFFD8C9BD));
      expect(sub.maxLines, 2);
      expect(inheritsFromStyle(doc, sub, 'fontSize'), isFalse);
      expect(inheritsFromStyle(doc, sub, 'color'), isTrue);
      expect(inheritsFromStyle(doc, headline, 'color'), isFalse);
    });

    test(
      'round-trips: inherited absent, overrides spelled, equal is inherited',
      () {
        var parsed = _parse(_scene);
        var out = _emit(parsed.doc!);
        expect(out, contains('style: t.title.copyWith(color: t.ink)'));
        expect(
          out,
          contains("TextNode('Sub', style: t.body.copyWith(fontSize: 24))"),
        );
        expect(out, isNot(contains('weight: SceneFontWeight.w700')));
        expect(_emit(_parse(out).doc!), out);
        // Overridden back to the style's own value: the override disappears.
        var sub = parsed.doc!.nodeNamed('sub')! as TextNode;
        sub.fontSize = 20;
        expect(_emit(parsed.doc!), contains("TextNode('Sub', style: t.body)"));
        // A value equal to the TABLE default but not the style's is spelled:
        // the style is the baseline, not the default.
        var headline = parsed.doc!.nodeNamed('headline')! as TextNode;
        headline.weight = SceneFontWeight.w400;
        expect(_emit(parsed.doc!), contains('weight: SceneFontWeight.w400'));
      },
    );

    test('takes its own style, and refuses what is not one', () {
      // A literal is a node's OWN type, and legal: it is the only way to
      // spell a treatment nothing else shares (master plan §4.5).
      var parsed = _parse(
        _scene.replaceAll(
          'style: t.title',
          'style: SceneTextStyle(fontSize: 10)',
        ),
      );
      expect(parsed.refusals, isEmpty, reason: parsed.refusals.join('\n'));
      expect((parsed.doc!.nodeNamed('headline')! as TextNode).fontSize, 10);
      parsed = _parse(_scene.replaceAll('style: t.title', 'style: 12'));
      expect(parsed.refusals.single.construct, 'style');
      parsed = _parse(_scene.replaceAll('style: t.title', 'style: t.ink'));
      expect(parsed.refusals.single.construct, 'token type');
      parsed = _parse(_scene.replaceAll('style: t.title', 'style: t.nope'));
      expect(parsed.refusals.single.construct, 'unknown token');
    });
  });

  group('in the editor', () {
    SceneEditor open() => SceneEditor(_parse(_scene).doc!);

    test('apply writes the style; any edit overrides; reset comes back', () {
      var e = open();
      var plain = e.doc.nodeNamed('plain')! as TextNode;
      e.applyStyle(plain, 'title');
      expect(plain.fontSize, 54);
      expect(plain.weight, SceneFontWeight.w700);
      expect(plain.bindings[styleBindingKey], const StyleRef('title'));
      e.perform('Size', () => plain.fontSize = 60);
      expect(
        plain.bindings[styleBindingKey],
        const StyleRef('title'),
        reason: 'never detached',
      );
      expect(inheritsFromStyle(e.doc, plain, 'fontSize'), isFalse);
      expect(
        _emit(e.doc),
        contains("TextNode('Plain', style: t.title.copyWith(fontSize: 60))"),
      );
      e.resetToStyle(plain, 'fontSize');
      expect(plain.fontSize, 54);
      expect(_emit(e.doc), contains("TextNode('Plain', style: t.title)"));
      e.detachStyle(plain);
      expect(plain.bindings[styleBindingKey], isNull);
      expect(plain.fontSize, 54, reason: 'the values stay');
      var out = _emit(e.doc).replaceAll(RegExp(r'\s+'), ' ');
      expect(
        out,
        contains(
          "TextNode( 'Plain', style: SceneTextStyle( fontSize: 54, "
          'weight: SceneFontWeight.w700, align: SceneTextAlign.center, ), )',
        ),
      );
    });

    test('a style is refused on a frame, and as a property binding', () {
      var e = open();
      expect(() => e.applyStyle(e.doc.root, 'title'), throwsArgumentError);
      expect(
        () => e.bindToken(e.doc.nodeNamed('plain')!, 'color', 'title'),
        throwsArgumentError,
      );
      expect(
        () => e.applyStyle(e.doc.nodeNamed('plain')!, 'ink'),
        throwsArgumentError,
      );
    });

    test('readers, and a style gone from the declaration', () {
      var e = open();
      expect(e.readersOfToken('title').map((r) => '${r.$1.name}.${r.$2}'), [
        'headline.style',
      ]);
      e.doc.tokens.removeWhere((t) => t.name == 'title');
      e.perform('Touch', () {});
      expect(e.doc.nodeNamed('headline')!.bindings[styleBindingKey], isNull);
      expect(
        (e.doc.nodeNamed('headline')! as TextNode).fontSize,
        54,
        reason: 'kept',
      );
    });
  });

  test('a compiled text resolves a delta, then the style, then default', () {
    const style = SceneTextStyle(fontSize: 20, weight: SceneFontWeight.w600);
    var t = TextNode('x', style: style.copyWith(fontSize: 30));
    expect(t.fontSize, 30);
    expect(t.weight, SceneFontWeight.w600);
    expect(t.color, const SceneColor(0xFF1A1A1A));
    expect(TextNode('y').fontSize, 16);
  });

  test('a style carries the paint stack, inherited and overridden', () {
    // The stack is a style property like every other, and the one the panel
    // could not say that about: it draws its own list with its own header,
    // so it does not fit in a property row and had no marker at all.
    const stack = [
      StrokeLayer(width: 8, paint: SolidPaint(SceneColor(0xFF120720))),
      FillLayer(),
    ];
    var t = TextNode('Hi', name: 'headline');
    var doc = SceneDocument(FrameNode(name: 'root')..children.add(t))
      ..tokens.add(
        const SceneTokenDecl.style('display', SceneTextStyle(layers: stack)),
      );
    var editor = SceneEditor(doc);
    editor.applyStyle(t, 'display');
    expect(t.layers, hasLength(2), reason: 'the style wrote its stack');
    expect(inheritsFromStyle(doc, t, 'layers'), isTrue);
    t.layers = [...t.layers, const FillLayer(dx: 2)];
    expect(
      inheritsFromStyle(doc, t, 'layers'),
      isFalse,
      reason: 'a list is compared by contents, not by identity',
    );
    editor.resetToStyle(t, 'layers');
    expect(inheritsFromStyle(doc, t, 'layers'), isTrue);
  });

  test('the wire spells a style apart from a token', () {
    expect(const StyleRef('title').toWire(), 'style:title');
    expect(SceneBinding.fromWire('style:title'), const StyleRef('title'));
    expect('${const StyleRef('title')}', 'tokens.title');
  });
}
