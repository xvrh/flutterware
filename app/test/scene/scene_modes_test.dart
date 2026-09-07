// Tokens injected, and modes: one set of values behind the same references.
//
// Four things are checked. The editor flips a mode without touching the
// file — values follow, bindings hold, undo keeps the mode. A parent hands
// its set to a nested scene, threaded by the tool and spelled under the
// child's own formal name. The generated arguments class carries the set.
// And the demonstration the plan owes: a compiled scene rebuilt in another
// mode while its intro plays, the player carried across at the same moment.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware/scene.dart';
import 'package:flutterware/scene_authoring.dart' hide Token;
import 'package:flutterware_app/src/scene/args_codegen.dart';
import 'package:flutterware_app/src/scene/editor.dart';
import 'package:flutterware_app/src/scene/scene_file.dart';
import 'package:flutterware_app/src/scene/tokens_file.dart';
import 'package:flutterware_app/src/scene/workspace.dart';

import 'sample.scene.dart';
import 'scene_args.dart';

final _tokens = parseTokensFile('''
import 'package:flutterware/scene_authoring.dart';

final sceneTokens = [
  const Token<SceneColor>('brand', SceneColor(0xFFE8632B), modes: {'dark': SceneColor(0xFFFF8A5C)}),
  const Token<SceneColor>('ink', SceneColor(0xFF000000), modes: {'dark': SceneColor(0xFFFFFFFF), 'contrast': SceneColor(0xFF00FF00)}),
  const Token<double>('radius', 8),
];
''').tokens;

const _parent =
    '''
$sceneFileMarker
import 'package:flutterware/scene_authoring.dart';

import 'scene_args.dart';

class Card({
  final String title = 'Hello',
  final SceneTokens t = const SceneTokens(),
}) extends SceneDefinition {
  late final headline = TextNode(title, fontSize: 20, color: t.ink);
  late final badge = SceneRefNode(BadgeArgs(label: title), x: 10, y: 10);
  @override
  late final root = FrameNode(width: 200, height: 100, fill: t.brand, corner: t.radius, children: [headline, badge]);
}
''';

const _child =
    '''
$sceneFileMarker
import 'package:flutterware/scene_authoring.dart';

import 'scene_args.dart';

class Badge({
  final String label = 'New',
  final SceneTokens tk = const SceneTokens(),
}) extends SceneDefinition {
  late final text = TextNode(label, color: tk.ink);
  @override
  late final root = FrameNode(width: 60, height: 20, fill: tk.brand, children: [text]);
}
''';

SceneParse _parse(String source) => parseSceneFile(source, tokens: _tokens);

void main() {
  group('a mode in the editor', () {
    SceneEditor open() => SceneEditor(_parse(_parent).doc!);

    test("puts the mode's values behind every reference, and back", () {
      var e = open();
      expect(e.tokenModes, ['contrast', 'dark']);
      e.tokenMode = 'dark';
      expect(e.doc.root.fill, const SceneColor(0xFFFF8A5C));
      expect(
        (e.doc.nodeNamed('headline')! as TextNode).color,
        const SceneColor(0xFFFFFFFF),
      );
      expect(e.doc.root.corner, 8, reason: 'no dark value: the default');
      e.tokenMode = 'contrast';
      expect(e.doc.root.fill, const SceneColor(0xFFE8632B), reason: 'default');
      expect(
        (e.doc.nodeNamed('headline')! as TextNode).color,
        const SceneColor(0xFF00FF00),
      );
      e.tokenMode = null;
      expect(e.doc.root.fill, const SceneColor(0xFFE8632B));
      expect(() => e.tokenMode = 'sepia', throwsArgumentError);
    });

    test('is view state: not journaled, not written, kept across undo', () {
      var e = open();
      var revision = e.revision;
      e.tokenMode = 'dark';
      expect(e.revision, revision, reason: 'no journal entry');
      expect(e.canUndo, isFalse);
      expect(_emit(e.doc), contains('fill: t.brand'), reason: 'the reference');
      // An edit in dark mode keeps the binding: the value matches the mode.
      e.perform('Nudge', () => e.doc.root.x = 5);
      expect(e.doc.root.bindings['fill'], const TokenRef('brand'));
      e.undo();
      expect(e.doc.root.fill, const SceneColor(0xFFFF8A5C), reason: 'dark');
      expect(e.doc.root.x, 0);
      // Binding in dark mode takes the dark value.
      e.bindToken(e.doc.nodeNamed('headline')!, 'fill', 'brand');
      expect(e.doc.nodeNamed('headline')!.fill, const SceneColor(0xFFFF8A5C));
    });
  });

  group("a nested scene receives the parent's set", () {
    test("spelled under the child's formal name, and read back", () {
      var parsed = _parse(
        _parent.replaceAll(
          'BadgeArgs(label: title)',
          'BadgeArgs(label: title, tk: t)',
        ),
      );
      expect(parsed.refusals, isEmpty, reason: parsed.refusals.join('\n'));
      var badge = parsed.doc!.nodeNamed('badge')! as SceneRefNode;
      expect(badge.tokensArg, 'tk');
      expect(badge.args.keys, ['label'], reason: 'not an argument');
      var out = _emit(parsed.doc!);
      expect(out, contains('BadgeArgs(label: title, tk: t)'));
      expect(_emit(_parse(out).doc!), out);
    });

    test('a widget takes no set', () {
      var parsed = _parse(
        _parent.replaceAll(
          'SceneRefNode(BadgeArgs(label: title), x: 10, y: 10)',
          'ExternalNode(ChipArgs(label: title, tk: t))',
        ),
      );
      expect(parsed.refusals.single.construct, 'tokens argument');
    });

    test('threaded by the workspace when both sides have a formal', () {
      var child = SceneFile.open(
        '/badge.scene.dart',
        _child,
        tokens: _tokens,
      ).file!;
      var root = SceneFile.open(
        '/card.scene.dart',
        _parent,
        tokens: _tokens,
      ).file!;
      var workspace = SceneWorkspace(
        root,
        resolveNested: (node) => node.name == 'badge' ? child : null,
      );
      var badge = root.scene.nodeNamed('badge')! as SceneRefNode;
      expect(badge.tokensArg, 'tk');
      expect(workspace.active, root);
      expect(root.emit(), contains('BadgeArgs(label: title, tk: t)'));
      // The mode reaches the instance the parent draws.
      root.editor.tokenMode = 'dark';
      expect(badge.instance!.tokenMode, 'dark');
      expect(badge.instance!.root.fill, const SceneColor(0xFFFF8A5C));
      root.editor.tokenMode = null;
      expect(badge.instance!.root.fill, const SceneColor(0xFFE8632B));
    });

    test('the generated arguments class carries the set, off the wire', () {
      var source = emitSceneArgs(
        externals: [],
        scenes: [
          SceneClassDecl(
            'Badge',
            [SceneParamDecl('label', SceneParamKind.string, 'New')],
            'badge.scene.dart',
            tokensFormal: 'tk',
          ),
        ],
        tokens: _tokens,
      );
      expect(source, contains('this.tk = const SceneTokens()'));
      expect(source, contains('final SceneTokens tk;'));
      expect(source, contains('Badge(label: label, tk: tk)'));
      expect(source, contains("toMap() => {'label': label}"));
      expect(source, contains("label: fx.text('label') ?? label, tk: tk"));
    });
  });

  group('a compiled scene', () {
    test('takes a set, and hands it to what it nests', () {
      var light = SampleScene();
      var dark = SampleScene(tokens: SceneTokens.dark);
      expect(light.root.fill, const SceneColor(0xFF2B1B12));
      expect(dark.root.fill, const SceneColor(0xFF111111));
      expect(dark.title.color, const SceneColor(0xFFEEEEEE));
      // The nested badge got the same set through its generated arguments.
      var nested = (dark.badgeRef.declared! as SampleBadgeArgs).build().scene;
      expect(
        (nested.root.children.single as TextNode).color,
        const SceneColor(0xFFEEEEEE),
      );
      expect(SceneTokens.modes.keys, ['dark']);
    });

    test('flipped while its intro plays: the player carries across', () {
      var light = SampleScene();
      var intro = SampleIntro(light);
      var player = MotionPlayer(intro, vsync: null);
      addTearDown(player.dispose);
      player.position = const Duration(milliseconds: 130);
      var midway = light.title.fxRendered('opacity') as double;
      expect(midway, greaterThan(0));
      expect(midway, lessThan(1));

      // A theme change is a fresh instance — `late final` read its tokens
      // once — and the same motion copied onto it.
      var dark = SampleScene(tokens: SceneTokens.dark);
      var again = intro.copy(dark);
      player.retarget(again.playable);
      expect(player.position, const Duration(milliseconds: 130));
      expect(dark.root.fill, const SceneColor(0xFF111111));
      expect(dark.title.fxRendered('opacity'), midway, reason: 'same moment');
      player.position = const Duration(milliseconds: 260);
      expect(dark.title.fxRendered('opacity'), 1.0);
      expect(
        light.title.fxRendered('opacity'),
        midway,
        reason: 'the old instance is left where it was',
      );
    });

    testWidgets('and the view follows the new instance', (tester) async {
      var light = SampleScene();
      var dark = SampleScene(tokens: SceneTokens.dark);
      var intro = SampleIntro(light);
      await tester.pumpWidget(
        MaterialApp(
          home: Center(child: SceneView(light, motion: intro)),
        ),
      );
      expect(find.text('Fresh coffee, faster'), findsOneWidget);
      await tester.pumpWidget(
        MaterialApp(
          home: Center(child: SceneView(dark, motion: intro.copy(dark))),
        ),
      );
      await tester.pump();
      expect(find.text('Fresh coffee, faster'), findsOneWidget);
      var text = tester.widget<Text>(find.text('Fresh coffee, faster'));
      expect(text.style?.color, const Color(0xFFEEEEEE));
    });
  });

  test('the fixture declaration is what the sample reads', () {
    expect(
      parseTokensFile(
        File('test/scene/sample.tokens.dart').readAsStringSync(),
        symbol: 'sampleTokens',
      ).tokens.map((t) => t.name),
      ['surface', 'ink'],
    );
  });
}

String _emit(SceneDocument doc) => emitSceneFile(doc, className: 'Card');
