// Tokens: the package's shared values, declared once by hand and read by
// every scene through a formal recognised by its type.
//
// Three graders: the declaration file is read exactly, with a line for
// anything outside its shape; what is generated from it is the class a scene
// spells `tokens.brand` against; and a scene reading a token round-trips —
// the formal by type, the reference spelled back, an undeclared name refused.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware/scene.dart';
import 'package:flutterware/scene_authoring.dart' hide Token;
import 'package:flutterware_app/src/scene/args_codegen.dart';
import 'package:flutterware_app/src/scene/editor.dart';
import 'package:flutterware_app/src/scene/group_file.dart';
import 'package:flutterware_app/src/scene/scene_file.dart';
import 'package:flutterware_app/src/scene/tokens_file.dart';
import 'package:flutterware_app/src/scene/ui/inspector.dart';
import 'package:flutterware_app/src/scene/ui/swatches.dart';
import 'package:flutterware_app/src/ui/theme.dart';

const _declaration = '''
import 'package:flutter/material.dart' show ButtonStyle, FilledButton;
import 'package:flutterware/scene_authoring.dart';

import 'shop.dart' as app;

final sceneTokens = [
  const Token<SceneColor>('brand', SceneColor(0xFFE8632B)),
  const Token<double>('radius', 28),
  Token<String>('cta', 'Order now'),
  const Token<bool>('compact', false),
  Token<ButtonStyle>('ctaStyle', FilledButton.styleFrom()),
  Token<app.Decor>('decor', app.decor),
];
''';

final _tokens = parseTokensFile(_declaration).tokens;

const _scene =
    '''
$sceneFileMarker
import 'package:flutterware/scene_authoring.dart';

import 'scene_args.dart';

class Card({
  final String title = 'Hello',
  final SceneTokens t = const SceneTokens(),
}) extends SceneDefinition {
  late final headline = TextNode(title, fontSize: 20, color: t.brand);
  late final box = FrameNode(x: 40, width: 80, height: 20, corner: t.radius);
  @override
  late final root = FrameNode(width: 200, height: 100, children: [headline, box]);
}
''';

SceneParse _parse(String source) => parseSceneFile(source, tokens: _tokens);

String _emit(SceneDocument doc) => emitSceneFile(doc, className: 'Card');

void main() {
  group('the declaration file', () {
    test('names each token, its kind and its value', () {
      var parsed = parseTokensFile(_declaration);
      expect(parsed.refusals, isEmpty);
      expect(parsed.tokens.map((t) => t.name).take(4), [
        'brand',
        'radius',
        'cta',
        'compact',
      ]);
      expect(parsed.tokens.map((t) => t.kind).take(4), [
        SceneParamKind.color,
        SceneParamKind.number,
        SceneParamKind.string,
        SceneParamKind.bool,
      ]);
      expect(parsed.tokens[0].value, const SceneColor(0xFFE8632B));
      expect(parsed.tokens[1].value, 28.0);
    });

    test('refuses a token with no type, a bad value, a duplicate', () {
      var parsed = parseTokensFile('''
final sceneTokens = [
  Token('brand', 1),
  Token<double>('radius', 'wide'),
  Token<double>('gap', 4),
  Token<double>('gap', 8),
];
''');
      expect(parsed.refusals.map((r) => r.construct), [
        'token type',
        'token value',
        'duplicate name',
      ]);
      expect(parsed.refusals.map((r) => r.line), [2, 3, 5]);
      expect(parsed.tokens.map((t) => t.name), ['gap']);
    });

    test('refuses a file that declares nothing', () {
      expect(
        parseTokensFile('final things = [];').refusals.single.construct,
        'no declarations',
      );
    });
  });

  group('the generated class', () {
    var source = emitSceneArgs(externals: [], scenes: [], tokens: _tokens);

    test('is a const with one typed field per token, valued as declared', () {
      expect(source, contains('class SceneTokens {'));
      expect(source, contains('final SceneColor brand;'));
      expect(source, contains('final double radius;'));
      expect(source, contains('final String cta;'));
      expect(source, contains('final bool compact;'));
      expect(source, contains('this.brand = const SceneColor(0xFFE8632B)'));
      expect(source, contains('this.radius = 28.0'));
      expect(source, contains("this.cta = 'Order now'"));
    });

    test('is absent when nothing is declared', () {
      expect(
        emitSceneArgs(externals: [], scenes: [], tokens: const []),
        isNot(contains('SceneTokens')),
      );
    });
  });

  group('a scene reading tokens', () {
    test('binds the property, takes the value and keeps the formal name', () {
      var parsed = _parse(_scene);
      expect(parsed.refusals, isEmpty);
      var doc = parsed.doc!;
      expect(doc.tokensFormal, 't');
      expect(doc.tokens.map((t) => t.name), contains('brand'));
      var headline = doc.nodeNamed('headline')! as TextNode;
      expect(headline.bindings['color'], const TokenRef('brand'));
      expect(headline.color, const SceneColor(0xFFE8632B));
      var box = doc.nodeNamed('box')!;
      expect(box.bindings['corner'], const TokenRef('radius'));
      expect(box.corner, 28);
    });

    test('round-trips, the reference spelled back through the formal', () {
      var parsed = _parse(_scene);
      var out = _emit(parsed.doc!);
      expect(out, contains('final SceneTokens t = const SceneTokens()'));
      expect(out, contains('color: t.brand'));
      expect(out, contains('corner: t.radius'));
      expect(_emit(_parse(out).doc!), out);
    });

    test('the formal appears when the first token is read', () {
      var doc = _parse(
        _scene
            .replaceAll('color: t.brand', '')
            .replaceAll('corner: t.radius', 'corner: 4'),
      ).doc!;
      // Declared by the author but reading nothing: kept, as written.
      expect(_emit(doc), contains('final SceneTokens t = const SceneTokens()'));
      doc.tokensFormal = null;
      expect(_emit(doc), isNot(contains('SceneTokens')));
      expect(_emit(doc), isNot(contains("import 'scene_args.dart'")));
      var editor = SceneEditor(doc);
      editor.bindToken(doc.nodeNamed('box')!, 'corner', 'radius');
      var out = _emit(doc);
      expect(out, contains('final SceneTokens tokens = const SceneTokens()'));
      expect(out, contains('corner: tokens.radius'));
      expect(out, contains("import 'scene_args.dart'"));
    });

    test('refuses a token nobody declared, and one of the wrong kind', () {
      var parsed = _parse(_scene.replaceAll('t.brand', 't.accent'));
      expect(parsed.doc, isNull);
      expect(parsed.refusals.single.construct, 'unknown token');
      expect(parsed.refusals.single.message, contains('"brand"'));
      parsed = _parse(_scene.replaceAll('t.brand', 't.radius'));
      expect(parsed.refusals.single.construct, 'token type');
    });

    test('refuses a tokens formal in a package with no declaration', () {
      var parsed = parseSceneFile(_scene);
      expect(parsed.doc, isNull);
      expect(parsed.refusals.first.construct, 'tokens formal');
      expect(parsed.refusals.first.message, contains('no token library'));
    });

    test('a nested argument may read a token', () {
      var parsed = _parse(
        _scene.replaceAll(
          'late final box = FrameNode(x: 40, width: 80, height: 20, corner: t.radius);',
          'late final box = SceneRefNode(BadgeArgs(label: t.cta), x: 40);',
        ),
      );
      expect(parsed.refusals, isEmpty);
      var box = parsed.doc!.nodeNamed('box')! as SceneRefNode;
      expect(box.bindings['args.label'], const TokenRef('cta'));
      expect(box.args['label'], 'Order now');
      expect(_emit(parsed.doc!), contains('BadgeArgs(label: t.cta)'));
    });
  });

  group('in the editor', () {
    SceneEditor open() => SceneEditor(_parse(_scene).doc!);

    test('binding takes the value; unbinding keeps it', () {
      var e = open();
      var root = e.doc.root;
      e.bindToken(root, 'fill', 'brand');
      expect(root.fill, const SceneColor(0xFFE8632B));
      expect(root.bindings['fill'], const TokenRef('brand'));
      expect(
        e.readersOfToken('brand').map((r) => r.$1.name),
        unorderedEquals(['headline', 'root']),
      );
      e.unbind(root, 'fill');
      expect(root.bindings['fill'], isNull);
      expect(root.fill, const SceneColor(0xFFE8632B));
    });

    test('a kind mismatch and an unknown token are refused', () {
      var e = open();
      expect(
        () => e.bindToken(e.doc.root, 'fill', 'radius'),
        throwsArgumentError,
      );
      expect(
        () => e.bindToken(e.doc.root, 'fill', 'accent'),
        throwsArgumentError,
      );
    });

    test('editing a token-bound property detaches it, not the token', () {
      var e = open();
      var box = e.doc.nodeNamed('box')!;
      e.perform('Nudge', () => box.corner = 4);
      expect(box.bindings['corner'], isNull, reason: 'detached');
      expect(box.corner, 4);
      expect(e.doc.tokenNamed('radius')!.value, 28.0, reason: 'untouched');
      // The other reader is untouched too.
      expect(
        (e.doc.nodeNamed('headline')! as TextNode).bindings['color'],
        const TokenRef('brand'),
      );
    });

    test('a token that disappears from the declaration drops its readers', () {
      var e = open();
      e.doc.tokens.removeWhere((t) => t.name == 'brand');
      e.perform('Touch', () {});
      expect(e.doc.nodeNamed('headline')!.bindings['color'], isNull);
      expect(_emit(e.doc), isNot(contains('t.brand')));
    });

    test('undo restores a binding', () {
      var e = open();
      var box = e.doc.nodeNamed('box')!;
      e.perform('Nudge', () => box.corner = 4);
      e.undo();
      expect(
        e.doc.nodeNamed('box')!.bindings['corner'],
        const TokenRef('radius'),
      );
    });
  });

  testWidgets("the inspector offers the tokens of a property's kind", (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var editor = SceneEditor(_parse(_scene).doc!);
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme,
        home: Scaffold(
          body: AnimatedBuilder(
            animation: editor.listenable,
            builder: (context, _) => Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 320,
                height: 900,
                child: SceneInspector(editor),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    // Nothing selected: the inspector is on the root, whose fill is free.
    await tester.tapAt(
      tester.getCenter(find.byType(SceneSwatches).first),
      buttons: kSecondaryButton,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('TOKENS'), findsOneWidget);
    expect(find.text('brand'), findsOneWidget);
    expect(
      find.text('#E8632B'),
      findsOneWidget,
      reason: 'the value rides along',
    );
    expect(find.text('radius'), findsNothing, reason: 'a number is not a fill');
    await tester.tap(find.text('brand'));
    await tester.pump();
    await tester.pump();
    expect(editor.doc.root.fill, const SceneColor(0xFFE8632B));
    expect(editor.doc.root.bindings['fill'], const TokenRef('brand'));
    expect(find.text('fill ← tokens.brand'), findsOneWidget);
    await tester.pump(kDoubleTapTimeout);
  });

  group('an opaque token', () {
    test('is read as a name and a type, its imports kept', () {
      var parsed = parseTokensFile(_declaration);
      expect(parsed.refusals, isEmpty);
      var style = parsed.tokens.firstWhere((t) => t.name == 'ctaStyle');
      expect(style.isOpaque, isTrue);
      expect(style.type, 'ButtonStyle');
      expect(style.value, isNull);
      expect(
        parsed.tokens.firstWhere((t) => t.name == 'decor').type,
        'app.Decor',
      );
      expect(parsed.imports, [
        "import 'package:flutter/material.dart' show ButtonStyle, FilledButton;",
        "import 'shop.dart' as app;",
      ]);
    });

    test('is a getter on the generated class, typed as declared', () {
      var source = emitSceneArgs(
        externals: [],
        scenes: [],
        tokens: _tokens,
        declarationImports: parseTokensFile(_declaration).imports,
      );
      expect(
        source,
        contains(
          "ButtonStyle get ctaStyle => _token('ctaStyle')! as ButtonStyle;",
        ),
      );
      expect(
        source,
        contains("app.Decor get decor => _token('decor')! as app.Decor;"),
      );
      expect(
        source,
        contains('scenes.tokens.firstWhere((t) => t.name == name).value'),
      );
      expect(source, contains("import 'scenes.dart';"));
      expect(
        source,
        contains(
          "import 'package:flutter/material.dart' show ButtonStyle, FilledButton;",
        ),
      );
      expect(source, contains("import 'shop.dart' as app;"));
      // A value token is still a const field.
      expect(source, contains('this.radius = 28.0'));
    });

    test("fills an external argument of the app's own type", () {
      var externals = parseGroupFile('''
import 'package:flutter/material.dart' show ButtonStyle;
import 'package:flutterware/scene_authoring.dart';

final scenes = SceneGroup(widgets: [
  ExternalWidget(
    'OrderButton',
    args: [const Arg<String>('label', 'Go'), const Arg<ButtonStyle>('style')],
    build: (a) => 1,
  ),
]);
''');
      expect(externals.refusals, isEmpty);
      expect(externals.widgets.single.args.last.typeName, 'ButtonStyle');
      var source = emitSceneArgs(
        externals: externals.widgets,
        scenes: [],
        declarationImports: externals.imports,
      );
      expect(source, contains('final ButtonStyle? style;'));
      expect(source, contains('style: style)'), reason: 'no fx reader');
      expect(source, isNot(contains('MotionTrack? style')));
      expect(
        source,
        contains("import 'package:flutter/material.dart' show ButtonStyle;"),
      );
    });

    test('an opaque argument with a default is refused', () {
      var parsed = parseGroupFile('''
final scenes = SceneGroup(widgets: [
  ExternalWidget('B', args: [Arg<ButtonStyle>('style', x)], build: (a) => 1),
]);
''');
      expect(parsed.refusals.single.construct, 'opaque default');
    });

    test('round-trips through an external argument as a name', () {
      var source = _scene.replaceAll(
        'late final box = FrameNode(x: 40, width: 80, height: 20, corner: t.radius);',
        "late final box = ExternalNode(OrderButtonArgs(label: 'Go', style: t.ctaStyle), x: 40);",
      );
      var parsed = _parse(source);
      expect(parsed.refusals, isEmpty);
      var box = parsed.doc!.nodeNamed('box')! as ExternalNode;
      expect(box.bindings['args.style'], const TokenRef('ctaStyle'));
      expect(box.args['style'], {'token': 'ctaStyle'});
      var out = _emit(parsed.doc!);
      expect(out, contains("OrderButtonArgs(label: 'Go', style: t.ctaStyle)"));
      expect(_emit(_parse(out).doc!), out);
    });

    test('cannot fill a property of the canvas', () {
      var parsed = _parse(_scene.replaceAll('t.radius', 't.ctaStyle'));
      expect(parsed.refusals.single.construct, 'token type');
      expect(parsed.refusals.single.message, contains('ButtonStyle'));
    });

    test(
      'binds and unbinds in the editor; a lost token clears the argument',
      () {
        var e = SceneEditor(_parse(_scene).doc!);
        var box = ExternalNode.read('OrderButton', name: 'button', args: {});
        e.perform('Add', () => e.doc.root.children.add(box));
        expect(
          () => e.bindToken(e.doc.root, 'fill', 'ctaStyle'),
          throwsArgumentError,
        );
        e.bindToken(box, 'args.style', 'ctaStyle');
        expect(box.args['style'], {'token': 'ctaStyle'});
        expect(_emit(e.doc), contains('style: t.ctaStyle'));
        e.unbind(box, 'args.style');
        expect(
          box.args.containsKey('style'),
          isFalse,
          reason: 'nothing to keep',
        );
        e.bindToken(box, 'args.style', 'ctaStyle');
        e.doc.tokens.removeWhere((t) => t.name == 'ctaStyle');
        e.perform('Touch', () {});
        expect(box.bindings['args.style'], isNull);
        expect(box.args.containsKey('style'), isFalse);
      },
    );

    test('the guest resolves the name to the declared object', () {
      var style = Object();
      var args = resolveTokenArgs(
        SceneArgs({
          'label': 'Go',
          'style': tokenMarker('ctaStyle'),
          'x': tokenMarker('gone'),
        }),
        {'ctaStyle': style},
      );
      expect(args.raw('style'), same(style));
      expect(args.text('label'), 'Go');
      expect(args.raw('x'), isNull, reason: "the widget's own fallback");
    });
  });

  test('the wire spells a token apart from an item reference', () {
    expect(const TokenRef('brand').toWire(), 'token:brand');
    expect(SceneBinding.fromWire('token:brand'), const TokenRef('brand'));
    expect(SceneBinding.fromWire('lines.item'), const ItemRef('lines', 'item'));
    expect('${const TokenRef('brand')}', 'tokens.brand');
  });
}
