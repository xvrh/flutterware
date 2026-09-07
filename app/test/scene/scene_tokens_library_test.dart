// A token library as a document: the editor's own, edited through doors
// and journaled, written back as the file the reader reads; shared by every
// open scene, whose readers follow an edit; and the two moves between a
// scene's parameter and the group's token.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware/scene_authoring.dart' hide Token;
import 'package:flutterware_app/src/scene/autosave.dart';
import 'package:flutterware_app/src/scene/scene_file.dart';
import 'package:flutterware_app/src/scene/tokens_file.dart';
import 'package:flutterware_app/src/scene/tokens_library.dart';
import 'package:flutterware_app/src/scene/workspace.dart';
import 'package:path/path.dart' as p;

const _library = '''
//@flutterware:tokens=1
import 'package:flutterware/scene_authoring.dart';

final brandTokens = [
  const Token<SceneColor>('brand', SceneColor(0xFFE8632B), modes: {'dark': SceneColor(0xFFFF8A5C)}),
  const Token<double>('radius', 28),
  const Token<SceneTextStyle>('title', SceneTextStyle(fontSize: 54, weight: SceneFontWeight.w700)),
];
''';

const _scene =
    '''
$sceneFileMarker
import 'package:flutterware/scene_authoring.dart';

import 'scene_args.dart';

class Card({
  final SceneColor tint = const SceneColor(0xFF112233),
  final SceneTokens t = const SceneTokens(),
}) extends SceneDefinition {
  late final headline = TextNode('Hello', style: t.title, color: t.brand);
  late final sub = TextNode('Sub', style: t.title, fontSize: 20);
  late final box = FrameNode(width: 80, height: 20, fill: tint, corner: t.radius);
  @override
  late final root = FrameNode(width: 200, height: 100, fill: t.brand, children: [headline, sub, box]);
}
''';

TokensLibrary _open() =>
    TokensLibrary.open('/pkg/lib/brand.tokens.dart', _library).library!;

SceneFile _file(TokensLibrary library) => SceneFile.open(
  '/pkg/lib/card.scene.dart',
  _scene,
  tokens: library.tokens,
).file!;

void main() {
  group('the document', () {
    test('reads the file, and writes one the reader reads back', () {
      var library = _open();
      expect(library.symbol, 'brandTokens');
      expect(library.tokens.map((t) => t.name), ['brand', 'radius', 'title']);
      expect(library.modes, ['dark']);
      var out = library.emit();
      expect(out, startsWith(sceneTokensFileMarker));
      expect(out, contains('final brandTokens = ['));
      expect(
        out.replaceAll(RegExp(r'\s+'), ' '),
        contains(
          "const Token<SceneColor>( 'brand', SceneColor(0xFFE8632B), "
          "modes: {'dark': SceneColor(0xFFFF8A5C)}, )",
        ),
      );
      var again = TokensLibrary.open(library.path, out).library!;
      expect(again.emit(), out, reason: 'canonical from the first write');
      expect(again.tokens[2].style, library.tokens[2].style);
    });

    test('adds, renames, edits, deletes — each one undo', () {
      var library = _open();
      library.add('gap', SceneParamKind.number, value: 8.0);
      expect(library.named('gap')!.value, 8.0);
      expect(
        () => library.add('gap', SceneParamKind.bool),
        throwsArgumentError,
      );
      expect(
        () => library.add('ink', SceneParamKind.color, taken: {'ink'}),
        throwsArgumentError,
        reason: 'a name another library or an export uses',
      );
      library.rename('gap', 'gutter');
      expect(library.named('gap'), isNull);
      expect(library.named('gutter')!.value, 8.0);
      library.setValue('gutter', 12.0);
      library.setValue('gutter', 4.0, mode: 'dense');
      expect(library.named('gutter')!.valueIn('dense'), 4.0);
      library.setValue('gutter', 12.0, mode: 'dense');
      expect(
        library.named('gutter')!.modes,
        isEmpty,
        reason: 'same as the default is the default',
      );
      library.setStyle('title', const SceneTextStyle(fontSize: 60));
      expect(library.named('title')!.style!.weight, isNull);
      library.delete('gutter');
      expect(library.named('gutter'), isNull);
      expect(library.isDirty, isTrue);
      library.undo();
      expect(library.named('gutter'), isNotNull);
      library.undo();
      expect(library.named('title')!.style!.weight, SceneFontWeight.w700);
      expect(library.canRedo, isTrue);
      expect(library.freeName('brand'), 'brand2');
    });

    test('declares a mode by name, renames it, deletes it — each undo', () {
      var library = _open();
      expect(library.declaredModes, isEmpty, reason: 'the file lists none');
      library.addMode('dense');
      expect(library.modes, ['dark', 'dense']);
      expect(library.differingIn('dense'), 0);
      expect(library.differingIn('dark'), 1);
      expect(() => library.addMode('dark'), throwsArgumentError);
      expect(() => library.addMode('default'), throwsArgumentError);
      expect(() => library.addMode('no way'), throwsArgumentError);
      var out = library.emit();
      expect(out, contains("const brandTokensModes = ['dark', 'dense'];"));
      var again = TokensLibrary.open(library.path, out).library!;
      expect(again.declaredModes, ['dark', 'dense']);
      library.renameMode('dark', 'night');
      expect(library.named('brand')!.modes.keys, ['night']);
      expect(library.modes, ['dense', 'night']);
      expect(() => library.renameMode('night', 'dense'), throwsArgumentError);
      library.deleteMode('night');
      expect(library.named('brand')!.modes, isEmpty);
      expect(library.modes, ['dense']);
      library.undo();
      expect(library.named('brand')!.modes.keys, ['night']);
      library.undo();
      expect(library.modes, ['dark', 'dense']);
      library.undo();
      expect(library.modes, ['dark']);
    });

    test('a style has a value per mode, whole, equal-is-default', () {
      var library = _open();
      const dark = SceneTextStyle(fontSize: 40, color: SceneColor(0xFFFFFFFF));
      library.setStyle('title', dark, mode: 'dark');
      expect(library.named('title')!.styleIn('dark'), dark);
      expect(library.named('title')!.style!.fontSize, 54, reason: 'default');
      expect(library.differingIn('dark'), 2);
      library.rename('title', 'headline');
      expect(library.named('headline')!.styleIn('dark'), dark);
      library.setStyle(
        'headline',
        library.named('headline')!.style!,
        mode: 'dark',
      );
      expect(
        library.named('headline')!.modes,
        isEmpty,
        reason: 'same as default',
      );
      library.setStyle('headline', dark, mode: 'dark');
      library.setStyle('headline', dark);
      expect(
        library.named('headline')!.modes,
        isEmpty,
        reason: 'default caught up',
      );
      var out = library.emit();
      library.setStyle(
        'headline',
        const SceneTextStyle(fontSize: 12),
        mode: 'dark',
      );
      out = library.emit();
      expect(
        out.replaceAll(RegExp(r'\s+'), ' '),
        contains("modes: {'dark': SceneTextStyle(fontSize: 12)}"),
      );
      expect(TokensLibrary.open(library.path, out).library!.emit(), out);
    });

    test('refuses a style edit on a value and a value on a style', () {
      var library = _open();
      expect(() => library.setValue('title', 3.0), throwsArgumentError);
      expect(
        () => library.setStyle('radius', const SceneTextStyle()),
        throwsArgumentError,
      );
      expect(() => library.setValue('radius', 'x'), throwsArgumentError);
    });

    test('saves what it emits, and nothing when nothing changed', () {
      var library = _open();
      var writes = <String>[];
      expect(library.save((path, source) => writes.add(source)), isEmpty);
      expect(writes, hasLength(1), reason: 'the file was not canonical');
      expect(library.isDirty, isFalse);
      expect(library.save((path, source) => writes.add(source)), isEmpty);
      expect(writes, hasLength(1));
      library.setValue('radius', 30.0);
      expect(library.isDirty, isTrue);
      library.save((path, source) => writes.add(source));
      expect(writes.last, contains("'radius', 30"));
      expect(library.matchesDisk(writes.last), isTrue);
    });

    test('adopts a version from disk as one undoable step', () {
      var library = _open();
      var refusals = library.adopt(
        _library.replaceAll("'radius', 28", "'radius', 99"),
      );
      expect(refusals, isEmpty);
      expect(library.named('radius')!.value, 99.0);
      expect(library.isDirty, isFalse);
      library.undo();
      expect(library.named('radius')!.value, 28.0);
    });
  });

  group('a workspace over a library', () {
    late TokensLibrary library;
    late SceneFile file;
    late SceneWorkspace workspace;

    setUp(() {
      library = _open();
      file = _file(library);
      workspace = SceneWorkspace(
        file,
        libraries: [library],
        tokensFor: (libs) => [for (var l in libs) ...l.tokens],
      );
    });

    test('moves every reader when a value changes, without a scene undo', () {
      var doc = file.scene;
      var revision = file.editor.revision;
      library.setValue('brand', const SceneColor(0xFF00FF00));
      expect(doc.root.fill, const SceneColor(0xFF00FF00));
      expect(
        (doc.nodeNamed('headline')! as TextNode).color,
        const SceneColor(0xFF00FF00),
      );
      expect(doc.root.bindings['fill'], const TokenRef('brand'));
      expect(file.editor.revision, revision, reason: 'undone in the library');
      expect(file.isDirty, isFalse);
      library.setValue('radius', 4.0);
      expect(doc.nodeNamed('box')!.corner, 4.0);
      // In dark mode the dark value lands.
      file.editor.tokenMode = 'dark';
      library.setValue('brand', const SceneColor(0xFF000001), mode: 'dark');
      expect(doc.root.fill, const SceneColor(0xFF000001));
    });

    test("moves a style's inherited properties and leaves overrides", () {
      var doc = file.scene;
      var headline = doc.nodeNamed('headline')! as TextNode;
      var sub = doc.nodeNamed('sub')! as TextNode;
      library.setStyle(
        'title',
        const SceneTextStyle(fontSize: 60, weight: SceneFontWeight.w900),
      );
      expect(headline.fontSize, 60);
      expect(headline.weight, SceneFontWeight.w900);
      expect(sub.fontSize, 20, reason: 'overridden');
      expect(sub.weight, SceneFontWeight.w900, reason: 'inherited');
    });

    test('drops the readers of a deleted token', () {
      library.delete('radius');
      expect(file.scene.nodeNamed('box')!.bindings['corner'], isNull);
      expect(file.scene.nodeNamed('box')!.corner, 28.0, reason: 'value kept');
    });

    test('renames: readers first, library after, alias in between', () {
      file.editor.renameTokenRefs('brand', 'accent');
      expect(file.scene.root.bindings['fill'], const TokenRef('accent'));
      library.rename('brand', 'accent');
      expect(file.scene.tokenNamed('accent'), isNotNull);
      expect(file.scene.tokenNamed('brand'), isNull);
      expect(file.emit(), contains('fill: t.accent'));
      expect(file.emit(), isNot(contains('t.brand')));
      expect(file.isDirty, isTrue, reason: "the file's text changed");
    });

    test('the autosave writes a dirty library', () async {
      var writes = <String, String>{};
      var autosave = SceneAutosave(
        write: (path, source) => writes[path] = source,
        onChanged: () {},
        quiet: const Duration(milliseconds: 10),
      );
      autosave.bind(workspace);
      library.setValue('radius', 30.0);
      expect(workspace.anyDirty, isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(writes.keys, [library.path]);
      expect(library.isDirty, isFalse);
      autosave.dispose();
    });

    test('SHARE: a parameter becomes a token of the library', () {
      var editor = file.editor;
      editor.shareParam(
        'tint',
        (name, kind, value) => library.add(name, kind, value: value),
      );
      expect(library.named('tint')!.value, const SceneColor(0xFF112233));
      expect(file.scene.paramNamed('tint'), isNull);
      expect(
        file.scene.nodeNamed('box')!.bindings['fill'],
        const TokenRef('tint'),
      );
      expect(file.emit(), contains('fill: t.tint'));
      expect(file.emit(), isNot(contains('final SceneColor tint')));
      editor.undo();
      expect(file.scene.paramNamed('tint'), isNotNull, reason: 'the rebinding');
      expect(library.named('tint'), isNotNull, reason: 'undone in the library');
    });

    test('MAKE LOCAL: a token becomes a parameter of this scene', () {
      var editor = file.editor;
      editor.tokenMode = 'dark';
      editor.localizeToken('brand');
      var param = file.scene.paramNamed('brand')!;
      expect(param.kind, SceneParamKind.color);
      expect(
        param.defaultValue,
        const SceneColor(0xFFFF8A5C),
        reason: "the mode's value; modes do not come along",
      );
      expect(file.scene.root.bindings['fill'], const ParamRef('brand'));
      expect(library.named('brand'), isNotNull, reason: 'stays for the others');
      expect(
        file.emit(),
        contains('final SceneColor brand = const SceneColor(0xFFFF8A5C)'),
      );
      expect(() => editor.localizeToken('title'), throwsArgumentError);
    });

    test('a declared mode reaches the canvas picker, and leaves it', () {
      var editor = file.editor;
      expect(editor.tokenModes, ['dark']);
      library.addMode('dense');
      expect(editor.tokenModes, ['dark', 'dense']);
      editor.tokenMode = 'dense';
      expect(
        file.scene.root.fill,
        const SceneColor(0xFFE8632B),
        reason: 'default',
      );
      library.deleteMode('dense');
      expect(editor.tokenModes, ['dark']);
      expect(editor.tokenMode, isNull, reason: 'the mode on show is gone');
      // A style's mode moves the readers in that mode.
      editor.tokenMode = 'dark';
      library.setStyle(
        'title',
        const SceneTextStyle(fontSize: 40),
        mode: 'dark',
      );
      expect((file.scene.nodeNamed('headline')! as TextNode).fontSize, 40);
      expect(
        (file.scene.nodeNamed('sub')! as TextNode).fontSize,
        20,
        reason: 'override',
      );
      editor.tokenMode = null;
      expect((file.scene.nodeNamed('headline')! as TextNode).fontSize, 54);
    });

    test('a library added later counts', () {
      var second = TokensLibrary(
        path: '/pkg/lib/store.tokens.dart',
        tokens: [SceneTokenDecl('shelf', SceneParamKind.number, 3.0)],
      );
      workspace.addLibrary(second);
      expect(file.scene.tokenNamed('shelf'), isNotNull);
      expect(workspace.libraryOf('shelf'), same(second));
      expect(workspace.tokenNames, containsAll(['brand', 'shelf']));
    });
  });

  test('a library written to disk is what the walk finds', () {
    var dir = Directory.systemTemp.createTempSync('fw_tokens_library');
    addTearDown(() => dir.deleteSync(recursive: true));
    var library = TokensLibrary(path: p.join(dir.path, 'brand.tokens.dart'));
    library.add('brand', SceneParamKind.color);
    library.save((path, source) => File(path).writeAsStringSync(source));
    var source = File(library.path).readAsStringSync();
    expect(isTokensFile(source), isTrue);
    expect(tokensSymbolFor(library.path), 'brandTokens');
    expect(parseTokensFile(source, symbol: 'brandTokens').tokens, hasLength(1));
  });
}
