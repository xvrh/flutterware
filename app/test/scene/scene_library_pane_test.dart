// A library open in the drawer: its modes, added by name, renamed and
// deleted there; and a style's pane editing one mode's style at a time.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware/scene_authoring.dart' hide Token;
import 'package:flutterware_app/src/scene/import/variables.dart';
import 'package:flutterware_app/src/scene/scene_file.dart';
import 'package:flutterware_app/src/scene/tokens_library.dart';
import 'package:flutterware_app/src/scene/ui/library_pane.dart';
import 'package:flutterware_app/src/scene/ui/token_pane.dart';
import 'package:flutterware_app/src/scene/ui/tokens_host.dart';
import 'package:flutterware_app/src/scene/workspace.dart';
import 'package:flutterware_app/src/ui/theme.dart';

const _library = '''
//@flutterware:tokens=1
import 'package:flutterware/scene_authoring.dart';

final brandTokens = [
  const Token<SceneColor>('brand', SceneColor(0xFFE8632B), modes: {'dark': SceneColor(0xFFFF8A5C)}),
  const Token<SceneTextStyle>('title', SceneTextStyle(fontSize: 54)),
];
''';

const _scene =
    '''
$sceneFileMarker
import 'package:flutterware/scene_authoring.dart';

import 'scene_args.dart';

class Card({final SceneTokens t = const SceneTokens()}) extends SceneDefinition {
  late final headline = TextNode('Hello', style: t.title);
  @override
  late final root = FrameNode(width: 200, height: 100, fill: t.brand, children: [headline]);
}
''';

void main() {
  late TokensLibrary library;
  late SceneFile file;
  late SceneWorkspace workspace;

  setUp(() {
    library = TokensLibrary.open(
      '/pkg/lib/brand.tokens.dart',
      _library,
    ).library!;
    file = SceneFile.open(
      '/pkg/lib/card.scene.dart',
      _scene,
      tokens: library.tokens,
      modes: library.modes,
    ).file!;
    workspace = SceneWorkspace(
      file,
      libraries: [library],
      tokensFor: (libs) => [for (var l in libs) ...l.tokens],
    );
  });

  tearDown(() => workspace.dispose());

  Widget host(Widget child) => MaterialApp(
    theme: appTheme,
    home: Material(child: SizedBox(height: 400, child: child)),
  );

  testWidgets('adds a mode by name, shows it, renames and deletes it', (
    tester,
  ) async {
    var editor = file.editor;
    await tester.pumpWidget(
      host(
        SceneLibraryPane(
          editor,
          library.path,
          host: SceneTokensHost(libraries: [library]),
        ),
      ),
    );
    expect(find.text('1 token differs'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('library:add-mode')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText), 'dense');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(library.modes, ['dark', 'dense']);
    expect(editor.tokenModes, ['dark', 'dense'], reason: 'the picker');
    expect(editor.tokenMode, 'dense', reason: 'the artboard shows it');
    expect(find.text('same as default everywhere'), findsOneWidget);
    // Click shows a mode on the canvas; double-click renames it.
    await tester.tap(find.byKey(const ValueKey('library:mode:dark')));
    await tester.pumpAndSettle();
    expect(editor.tokenMode, 'dark');
    expect(file.scene.root.fill, const SceneColor(0xFFFF8A5C));
    await tester.tap(find.byKey(const ValueKey('library:mode:dark')));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.byKey(const ValueKey('library:mode:dark')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText), 'night');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(library.modes, ['dense', 'night']);
    expect(editor.tokenMode, 'night', reason: 'followed the rename');
    expect(file.scene.root.fill, const SceneColor(0xFFFF8A5C));
    library.deleteMode('night');
    await tester.pumpAndSettle();
    expect(editor.tokenMode, isNull);
    expect(file.scene.root.fill, const SceneColor(0xFFE8632B));
    expect(find.text('night'), findsNothing);
  });

  testWidgets('shows the last import, and the door to the next', (
    tester,
  ) async {
    var imported = <String>[];
    await tester.pumpWidget(
      host(
        SceneLibraryPane(
          file.editor,
          library.path,
          host: SceneTokensHost(
            libraries: [library],
            importInto: (path) async => imported.add(path),
          ),
        ),
      ),
    );
    expect(find.textContaining('Nothing imported yet'), findsOneWidget);
    expect(find.text('Import variables…'), findsOneWidget);
    library.merge(
      importVariables(
        File('test/scene/fixtures/variables.json').readAsStringSync(),
      ),
      from: 'variables.json',
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('library:import-note')), findsOneWidget);
    expect(find.text('Not imported'), findsOneWidget);
    expect(
      find.textContaining('Kept, not in the design file: brand, title'),
      findsOneWidget,
    );
    await tester.tap(find.text('Import again…'));
    await tester.pumpAndSettle();
    expect(imported, [library.path]);
    // The button's done state holds a timer.
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets("a style's pane edits one mode's style at a time", (
    tester,
  ) async {
    var editor = file.editor;
    await tester.pumpWidget(
      host(
        SceneTokenPane(
          editor,
          'title',
          host: SceneTokensHost(libraries: [library]),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('style-mode:default')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('style-mode:dark')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Same as the default'), findsOneWidget);
    library.setStyle('title', const SceneTextStyle(fontSize: 40), mode: 'dark');
    await tester.pumpAndSettle();
    expect(find.text('The style in dark.'), findsOneWidget);
    expect(find.text('same as default'), findsOneWidget);
    await tester.tap(find.text('same as default'));
    await tester.pumpAndSettle();
    expect(library.named('title')!.modes, isEmpty);
  });
}
