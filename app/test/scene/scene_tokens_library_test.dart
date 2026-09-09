// A token library as a document: the editor's own, edited through doors
// and journaled, written back as the file the reader reads; shared by every
// open scene, whose readers follow an edit; and the two moves between a
// scene's parameter and the group's token.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware/scene_authoring.dart' hide Token;
import 'package:clock/clock.dart';
import 'package:flutterware_app/src/scene/autosave.dart';
import 'package:flutterware_app/src/scene/import/variables.dart';
import 'package:flutterware_app/src/scene/scene_file.dart';
import 'package:flutterware_app/src/scene/tokens_file.dart';
import 'package:flutterware_app/src/scene/tokens_library.dart';
import 'package:flutterware_app/src/scene/workspace.dart';
import 'package:path/path.dart' as p;

const _library = '''
//@flutterware:tokens=1
import 'package:flutterware/scene_authoring.dart';

final brandTokens = [
  const Token<SceneColor>('brand', SceneColor(0xFFE8632B)),
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
      var out = library.emit();
      expect(out, startsWith(sceneTokensFileMarker));
      expect(out, contains('final brandTokens = ['));
      expect(
        out.replaceAll(RegExp(r'\s+'), ' '),
        contains("const Token<SceneColor>('brand', SceneColor(0xFFE8632B))"),
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
      expect(library.named('gutter')!.value, 12.0);
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

    test('refuses a mode, in a token and on its own line', () {
      var library = _open();
      var opened = TokensLibrary.open(library.path, '''
$sceneTokensFileMarker
import 'package:flutterware/scene_authoring.dart';

const brandTokensModes = ['dark'];

final brandTokens = [
  const Token<SceneColor>('brand', SceneColor(0xFFE8632B), modes: {'dark': SceneColor(0xFFFF8A5C)}),
];
''');
      expect(opened.library, isNull);
      expect(opened.refusals.map((r) => r.construct), ['declaration', 'modes']);
      for (var r in opened.refusals) {
        expect(r.message, contains('SceneTokens(…)'));
      }
    });

    test('merges a design file in by name, and says what it did', () {
      var library = TokensLibrary.open('/pkg/lib/brand.tokens.dart', '''
$sceneTokensFileMarker
import 'package:flutterware/scene_authoring.dart';

final brandTokens = [
  const Token<SceneColor>('brandPrimary', SceneColor(0xFF000000)),
  const Token<double>('radiusCard', 28),
  const Token<SceneTextStyle>('brandSurface', SceneTextStyle(fontSize: 12)),
  const Token<double>('espresso', 3),
];
''').library!;
      var import = importVariables(
        File('test/scene/fixtures/variables.json').readAsStringSync(),
      );
      var note = withClock(
        Clock.fixed(DateTime(2026, 9, 7, 14, 2)),
        () => library.merge(import, from: 'variables.json'),
      );
      expect(note.when, '2026-09-07 14:02');
      expect(note.updated, 1, reason: 'brandPrimary');
      expect(note.unchanged, 1, reason: 'radiusCard is 28 there too');
      expect(
        note.added,
        import.tokens.length - 3,
        reason: 'the three the library already names',
      );
      expect(note.kept, ['espresso']);
      expect(note.notImported, hasLength(import.refusals.length + 1));
      expect(
        note.notImported.last,
        contains('"brandSurface" is a style here, the file has a color'),
      );
      var primary = library.named('brandPrimary')!;
      expect(primary.value, const SceneColor(0xFFE8632B), reason: 'theirs');
      expect(library.named('brandSurface')!.isStyle, isTrue, reason: 'kept');
      expect(library.named('espresso')!.value, 3.0);
      expect(library.importNote, same(note));
      var out = library.emit();
      expect(
        out,
        contains(
          '// Imported from variables.json on 2026-09-07 14:02 — '
          '${note.summary}.',
        ),
      );
      expect(out, contains('// Kept, not in the design file: espresso'));
      var again = TokensLibrary.open(library.path, out).library!;
      expect(again.importNote?.when, '2026-09-07 14:02');
      expect(again.importNote?.notImported, note.notImported);
      expect(again.importNote?.kept, ['espresso']);
      expect(again.emit(), out, reason: 'the note survives the round trip');
      // One journal entry.
      library.undo();
      expect(
        library.named('brandPrimary')!.value,
        const SceneColor(0xFF000000),
      );
      expect(library.importNote, isNull);
      expect(library.named('brandSecondary'), isNull);
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
      editor.localizeToken('brand');
      var param = file.scene.paramNamed('brand')!;
      expect(param.kind, SceneParamKind.color);
      expect(param.defaultValue, const SceneColor(0xFFE8632B));
      expect(file.scene.root.bindings['fill'], const ParamRef('brand'));
      expect(library.named('brand'), isNotNull, reason: 'stays for the others');
      expect(
        file.emit(),
        contains('final SceneColor brand = const SceneColor(0xFFE8632B)'),
      );
      expect(() => editor.localizeToken('title'), throwsArgumentError);
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
