// The tree as an editor: rename in place, move by dragging, and the doors
// behind both.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware/scene_authoring.dart';
import 'package:flutterware_app/src/scene/editor.dart';
import 'package:flutterware_app/src/scene/fixtures.dart';
import 'package:flutterware_app/src/scene/ui/shortcuts.dart';
import 'package:flutterware_app/src/scene/ui/tree_panel.dart';
import 'package:flutterware_app/src/ui/theme.dart';

void main() {
  group('rename', () {
    test('a rename follows into the groups animating the node', () {
      var editor = SceneEditor(
        coffeeBannerDraft(),
        motions: {'BannerIntro': coffeeIntroDraft()},
      );
      var headline = editor.doc.nodeNamed('headline')!;
      editor.select(headline);
      editor.rename(headline, 'title');
      expect(headline.name, 'title');
      expect(editor.doc.nodeNamed('headline'), isNull);
      expect(
        editor.motions['BannerIntro']!.groupNamed('headlineIn')!.target,
        'title',
      );
      expect(editor.selectionNames, ['title'], reason: 'selection follows');
      editor.undo();
      expect(editor.doc.nodeNamed('headline'), isNotNull);
      expect(
        editor.motions['BannerIntro']!.groupNamed('headlineIn')!.target,
        'headline',
      );
    });

    test('a taken or invalid name is refused, and says why', () {
      var editor = SceneEditor(coffeeBannerDraft());
      var glow = editor.doc.nodeNamed('glow')!;
      expect(() => editor.rename(glow, 'cup'), throwsArgumentError);
      expect(() => editor.rename(glow, 'not a name'), throwsArgumentError);
      expect(glow.name, 'glow');
      expect(editor.canUndo, isFalse);
    });
  });

  group('reparent', () {
    late SceneEditor editor;
    setUp(() {
      editor = SceneEditor(coffeeBannerDraft());
      editor.doc.root.measured = const SceneRect(0, 0, 1024, 500);
      editor.doc.nodeNamed('copy')!.measured = const SceneRect(
        64,
        120,
        500,
        200,
      );
      editor.doc.nodeNamed('glow')!.measured = const SceneRect(
        600,
        -110,
        480,
        480,
      );
    });

    test('into a free frame keeps the place on the canvas', () {
      var glow = editor.doc.nodeNamed('glow')!;
      var cta = editor.doc.nodeNamed('cta')! as FrameNode;
      cta.measured = const SceneRect(64, 260, 150, 50);
      // cta is a row: position becomes order.
      editor.reparent([glow], cta);
      expect(editor.doc.parentOf(glow), same(cta));
      expect((glow.x, glow.y), (0.0, 0.0));
      editor.undo();
      expect(editor.doc.parentOf(glow), same(editor.doc.root));
      expect((glow.x, glow.y), (600.0, -110.0));
    });

    test('before a sibling reorders; a frame never enters itself', () {
      var glow = editor.doc.nodeNamed('glow')!;
      var badge = editor.doc.nodeNamed('badge')!;
      var root = editor.doc.root;
      editor.reparent([glow], root, index: root.children.indexOf(badge));
      expect(root.children.indexOf(glow), root.children.indexOf(badge) - 1);
      var copy = editor.doc.nodeNamed('copy')! as FrameNode;
      var cta = editor.doc.nodeNamed('cta')! as FrameNode;
      expect(
        editor.canReparent(copy, cta),
        isFalse,
        reason: 'cta is inside copy',
      );
      expect(editor.canReparent(root, cta), isFalse);
      editor.reparent([copy], cta);
      expect(editor.doc.parentOf(cta), same(copy), reason: 'refused silently');
    });
  });

  group('on screen', () {
    late SceneEditor editor;

    Future<void> pump(WidgetTester tester) async {
      tester.view.physicalSize = const Size(400, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      editor = SceneEditor(coffeeBannerDraft());
      // Inside the editing scope, as it is in the workspace: the scope's
      // own letters and Backspace must not reach the editor while a field
      // has the keyboard.
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme,
          home: Material(
            child: EditorShortcuts(editor, child: SceneTreePanel(editor)),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets("the rename field keeps the scope's letters and Backspace", (
      tester,
    ) async {
      await pump(tester);
      var nodes = editor.doc.walk().length;
      await tester.tap(find.text('glow'));
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tap(find.text('glow'));
      await tester.pump();
      expect(find.byType(TextField), findsOneWidget);
      // Typed through the platform, like a real keyboard: the letters t and
      // s are also tool chords, and Backspace is delete-node.
      await tester.enterText(find.byType(TextField), 'toasts');
      await tester.pump();
      for (var key in [
        LogicalKeyboardKey.keyT,
        LogicalKeyboardKey.keyS,
        LogicalKeyboardKey.backspace,
      ]) {
        await tester.sendKeyEvent(key);
        await tester.pump();
      }
      expect(editor.tool, SceneTool.select, reason: 'no tool switched');
      expect(editor.doc.walk().length, nodes, reason: 'nothing deleted');
      expect(find.byType(TextField), findsOneWidget, reason: 'still editing');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      // The Backspace reached the field, which is the whole point.
      expect(editor.doc.nodeNamed('toast'), isNotNull);
    });

    testWidgets('double-click renames in place; Escape backs out', (
      tester,
    ) async {
      await pump(tester);
      await tester.tap(find.text('glow'));
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tap(find.text('glow'));
      await tester.pump();
      expect(find.byType(TextField), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'halo');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(editor.doc.nodeNamed('halo'), isNotNull);
      expect(find.byType(TextField), findsNothing);

      await tester.tap(find.text('cup'));
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tap(find.text('cup'));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'mug');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(editor.doc.nodeNamed('cup'), isNotNull);
      expect(find.byType(TextField), findsNothing);
      await tester.pump(kDoubleTapTimeout);
    });

    testWidgets('the field has the keyboard at once, and Enter commits', (
      tester,
    ) async {
      await pump(tester);
      await tester.tap(find.text('glow'));
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tap(find.text('glow'));
      await tester.pump();
      await tester.pump();
      var field = tester.widget<TextField>(find.byType(TextField));
      expect(field.focusNode!.hasFocus, isTrue, reason: 'no click needed');
      // The name is selected whole, so typing replaces it.
      expect(field.controller!.selection.extentOffset, 'glow'.length);
      await tester.enterText(find.byType(TextField), 'halo');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(editor.doc.nodeNamed('halo'), isNotNull);
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('a taken name is refused in the field', (tester) async {
      await pump(tester);
      await tester.tap(find.text('glow'));
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tap(find.text('glow'));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'cup');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(find.byType(TextField), findsOneWidget, reason: 'still editing');
      expect(find.textContaining('already taken'), findsOneWidget);
      expect(editor.doc.nodeNamed('glow'), isNotNull);
      await tester.pump(kDoubleTapTimeout);
    });

    testWidgets('dragging a row onto a frame moves the node inside it', (
      tester,
    ) async {
      await pump(tester);
      var glow = editor.doc.nodeNamed('glow')!;
      var copy = editor.doc.nodeNamed('copy')! as FrameNode;
      var from = tester.getCenter(find.text('glow'));
      var to = tester.getCenter(find.text('copy'));
      var gesture = await tester.startGesture(
        from,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump(const Duration(milliseconds: 100));
      await gesture.moveTo(from + const Offset(0, 20));
      await tester.pump();
      await gesture.moveTo(to);
      await tester.pump();
      await gesture.up();
      await tester.pump();
      expect(editor.doc.parentOf(glow), same(copy));
      expect(copy.children.last, same(glow));
      expect(editor.selectionNames, ['glow']);
      expect(editor.undoLabel, 'Move glow');
    });
  });
}
