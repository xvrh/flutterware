// A design file's variables become `scene_tokens.dart`: every variable a
// token at its collection's default value, every refusal named — the other
// modes among them — and the written file is one the tokens reader reads
// back to the same declarations.
//
// The fixture is shaped after the variables endpoint's answer — collections
// with modes, values by mode, aliases within and across collections, a
// deleted variable, a name that is no identifier, a duplicate once
// identifiers are made.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware/scene_authoring.dart' hide Token;
import 'package:flutterware_app/src/scene/args_codegen.dart';
import 'package:flutterware_app/src/scene/args_generate.dart';
import 'package:flutterware_app/src/scene/group_file.dart';
import 'package:flutterware_app/src/scene/import/variables.dart';
import 'package:flutterware_app/src/scene/scene_file.dart';
import 'package:flutterware_app/src/scene/tokens_file.dart';
import 'package:flutterware_app/src/scene/tokens_library.dart';

void main() {
  var json = File('test/scene/fixtures/variables.json').readAsStringSync();
  var import = importVariables(json);

  test('every usable variable is a token, named as an identifier', () {
    // A STRING and a BOOLEAN variable are refused, not imported: a library
    // is a design system, and copy and flags are not design.
    expect(import.tokens.map((t) => t.name), [
      'brandPrimary',
      'brandSurface',
      'textOnBrand',
      'radiusCard',
      'spacing2x',
      'cardSurface',
    ]);
    expect(import.tokens.map((t) => t.kind), [
      SceneParamKind.color,
      SceneParamKind.color,
      SceneParamKind.color,
      SceneParamKind.number,
      SceneParamKind.number,
      SceneParamKind.color,
    ]);
    var primary = import.tokens.first;
    expect(primary.source, 'Colors · Brand/Primary');
    expect(primary.value, const SceneColor(0xFFE8632B));
    expect(import.tokens[3].value, 28.0);
    expect(import.tokens[4].value, 16.5);
    expect(
      import.refusals.map((r) => r.what),
      containsAll(['Layout · Copy/CTA', 'Layout · Show badge']),
    );
  });

  test("every mode but the collection's default is refused by name", () {
    expect(
      import.refusals.map((r) => r.what),
      containsAllInOrder(['Colors · Dark mode']),
    );
    var mode = import.refusals.first;
    expect(mode.reason, contains('only the default mode is imported'));
    expect(mode.reason, contains('SceneTokens(…)'));
  });

  test("an alias resolves in the target collection's default mode", () {
    expect(import.tokens[2].value, const SceneColor(0xFFFFFFFF));
    // Layout's alias into Colors reads Colors' default.
    expect(import.tokens.last.value, const SceneColor(0xFFFFFFFF));
  });

  test('what cannot be a token is refused by name, with the reason', () {
    expect(
      import.refusals.map((r) => r.what),
      containsAllInOrder(['Colors · Brand/Primary ', 'Colors · 🎨']),
    );
    var duplicate = import.refusals.firstWhere(
      (r) => r.what == 'Colors · Brand/Primary ',
    );
    expect(duplicate.reason, contains('"brandPrimary"'));
    expect(duplicate.reason, contains('Colors · Brand/Primary'));
    expect(
      import.refusals.firstWhere((r) => r.what == 'Colors · 🎨').reason,
      contains('identifier'),
    );
    // Deleted-but-referenced is not a refusal: it is not a variable any more.
    expect(
      import.tokens.map((t) => t.source),
      isNot(contains('Colors · Old/Accent')),
    );
  });

  /// A fresh library with the import merged in — the file the CLI writes.
  String emitted({String symbol = sceneTokensSymbol}) {
    var library = TokensLibrary(
      path:
          '/pkg/lib/${symbol == sceneTokensSymbol ? 'scene' : 'imported'}'
          '$sceneTokensFileSuffix',
    );
    library.merge(import, from: 'variables.json');
    return library.emit();
  }

  test('the written file reads back to the same tokens', () {
    var source = emitted();
    expect(source, contains('// Imported from variables.json on '));
    expect(source, contains('// Not imported:'));
    var parsed = parseTokensFile(source);
    expect(parsed.refusals, isEmpty, reason: parsed.refusals.join('\n'));
    expect(
      parsed.tokens.map((t) => t.name).toSet(),
      import.tokens.map((t) => t.name).toSet(),
    );
    expect(
      parsed.tokens.map((t) => t.name),
      // Grouped by kind, the sheet's order — the palette, then the scale —
      // with the file's order kept inside each.
      [
        'brandPrimary',
        'brandSurface',
        'textOnBrand',
        'cardSurface',
        'radiusCard',
        'spacing2x',
      ],
      reason: 'the emitter writes the order the library page draws',
    );
    SceneTokenDecl named(String name) =>
        parsed.tokens.firstWhere((t) => t.name == name);
    expect(named('brandPrimary').value, const SceneColor(0xFFE8632B));
    expect(named('radiusCard').value, 28.0);
  });

  test('the generated class is one set, with a constructor to build more', () {
    var decls = parseTokensFile(emitted()).tokens;
    var source = emitSceneArgs(externals: [], scenes: [], tokens: decls);
    var flat = source.replaceAll(RegExp(r'\s+'), ' ');
    expect(flat, contains('this.brandPrimary = const SceneColor(0xFFE8632B)'));
    expect(flat, contains('this.radiusCard = 28.0'));
    expect(flat, contains('final SceneColor brandPrimary;'));
    expect(source, isNot(contains('static const')));
    expect(source, isNot(contains('static const modes')));
  });

  test('a hand-written declaration refuses a mode and an opaque value', () {
    var parsed = parseTokensFile('''
final sceneTokens = [
  Token<double>('gap', 8, modes: {'dense': 4, 'wide': 12}),
  Token<double>('kept', 8),
  Token<Foo>('opaque', foo),
];
''');
    expect(parsed.tokens.single.name, 'kept');
    expect(parsed.refusals.map((r) => r.construct), [
      'modes',
      'token type',
    ], reason: "the app's own object is an export, not a library value");
    expect(parsed.refusals.first.message, contains('SceneTokens(…)'));
  });

  test(
    'the imported file, beside a scene reading it, generates and parses',
    () {
      var dir = Directory.systemTemp.createTempSync('fw_tokens_import');
      addTearDown(() => dir.deleteSync(recursive: true));
      File('${dir.path}/imported.tokens.dart')
          .writeAsStringSync(emitted(symbol: 'importedTokens'));
      File('${dir.path}/$sceneGroupFileName').writeAsStringSync('''
$sceneGroupFileMarker
import 'package:flutterware/scene.dart';

import 'imported.tokens.dart';

final scenes = SceneGroup(libraries: [importedTokens]);
''');
      File('${dir.path}/card.scene.dart').writeAsStringSync('''
$sceneFileMarker
import 'package:flutterware/scene_authoring.dart';

import 'scene_args.dart';

class Card({final SceneTokens tokens = const SceneTokens()}) extends SceneDefinition {
  late final label = TextNode('Order now', color: tokens.textOnBrand);
  @override
  late final root = FrameNode(width: 200, height: 100, fill: tokens.brandPrimary, corner: tokens.radiusCard, children: [label]);
}
''');
      var result = generateSceneArgsIn(dir.path).values.single;
      expect(result.refusals, isEmpty, reason: result.refusals.join('\n'));
      expect(result.wrote, isTrue);
      expect(result.source, contains('class SceneTokens {'));
      expect(result.source, contains('brandPrimary'));
      expect(result.source, contains('class CardArgs extends SceneRefArgs'));
      var decls = parseTokensFile(
        File('${dir.path}/imported.tokens.dart').readAsStringSync(),
        symbol: 'importedTokens',
      ).tokens;
      var parsed = parseSceneFile(
        File('${dir.path}/card.scene.dart').readAsStringSync(),
        tokens: decls,
      );
      expect(parsed.refusals, isEmpty, reason: parsed.refusals.join('\n'));
      var root = parsed.doc!.root;
      expect(root.fill, const SceneColor(0xFFE8632B));
      expect(root.corner, 28);
      expect(root.bindings['fill'], const TokenRef('brandPrimary'));
      expect((parsed.doc!.nodeNamed('label')! as TextNode).text, 'Order now');
    },
  );

  test('not the variables endpoint: refused as a whole', () {
    expect(
      importVariables('not json').refusals.single.reason,
      contains('not JSON'),
    );
    expect(
      importVariables('{"document": {}}').refusals.single.reason,
      contains('variables endpoint'),
    );
  });
}
