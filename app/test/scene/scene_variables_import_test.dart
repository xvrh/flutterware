// A design file's variables become `scene_tokens.dart`: every variable a
// token with its modes, every refusal named, and the written file is one
// the tokens reader reads back to the same declarations.
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
    expect(import.tokens.map((t) => t.name), [
      'brandPrimary',
      'brandSurface',
      'textOnBrand',
      'radiusCard',
      'spacing2x',
      'copyCTA',
      'showBadge',
      'cardSurface',
    ]);
    expect(import.tokens.map((t) => t.kind), [
      SceneParamKind.color,
      SceneParamKind.color,
      SceneParamKind.color,
      SceneParamKind.number,
      SceneParamKind.number,
      SceneParamKind.string,
      SceneParamKind.bool,
      SceneParamKind.color,
    ]);
    var primary = import.tokens.first;
    expect(primary.source, 'Colors · Brand/Primary');
    expect(primary.value, const SceneColor(0xFFE8632B));
    expect(import.tokens[3].value, 28.0);
    expect(import.tokens[4].value, 16.5);
    expect(import.tokens[5].value, 'Order now');
    expect(import.tokens[6].value, true);
  });

  test('modes are named across collections and carried per token', () {
    expect(import.modeNames, ['light', 'darkMode', 'defaultMode']);
    var primary = import.tokens.first;
    expect(primary.modes.keys, ['light', 'darkMode']);
    expect(primary.modes['darkMode'], const SceneColor(0xFFFF804D));
    expect(primary.modes['light'], primary.value, reason: 'the default mode');
    expect(import.tokens[3].modes, {'defaultMode': 28.0});
  });

  test('an alias resolves in the same-named mode, else the default', () {
    var onBrand = import.tokens[2];
    expect(onBrand.modes['light'], const SceneColor(0xFFFFFFFF));
    expect(onBrand.modes['darkMode'], const SceneColor(0xFF2B1B12));
    // Layout has no Dark mode: its alias into Colors reads Colors' default.
    expect(import.tokens.last.modes, {
      'defaultMode': const SceneColor(0xFFFFFFFF),
    });
  });

  test('what cannot be a token is refused by name, with the reason', () {
    expect(import.refusals.map((r) => r.what), [
      'Colors · Brand/Primary ',
      'Colors · 🎨',
    ]);
    expect(import.refusals.first.reason, contains('"brandPrimary"'));
    expect(import.refusals.first.reason, contains('Colors · Brand/Primary'));
    expect(import.refusals.last.reason, contains('identifier'));
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

  test('the written file reads back to the same tokens, modes included', () {
    var source = emitted();
    expect(source, contains('// Imported from variables.json on '));
    expect(source, contains('// Not imported:'));
    var parsed = parseTokensFile(source);
    expect(parsed.refusals, isEmpty, reason: parsed.refusals.join('\n'));
    expect(parsed.tokens.map((t) => t.name), import.tokens.map((t) => t.name));
    var primary = parsed.tokens.first;
    expect(primary.value, const SceneColor(0xFFE8632B));
    expect(primary.modes, {
      'light': const SceneColor(0xFFE8632B),
      'darkMode': const SceneColor(0xFFFF804D),
    });
    expect(parsed.tokens[5].value, 'Order now');
    expect(parsed.tokens[6].value, true);
  });

  test('the generated class carries one static set per mode', () {
    var decls = parseTokensFile(emitted()).tokens;
    var source = emitSceneArgs(externals: [], scenes: [], tokens: decls);
    expect(source, contains('static const darkMode = SceneTokens('));
    expect(source, contains('brandPrimary: SceneColor(0xFFFF804D)'));
    expect(source, contains('textOnBrand: SceneColor(0xFF2B1B12)'));
    expect(source, contains('static const defaultMode = SceneTokens('));
    expect(source, contains('radiusCard: 28.0'));
    expect(source, contains("'darkMode': darkMode"));
    expect(source, contains("'light': light"));
    expect(source, contains('static const modes = <String, SceneTokens>{'));
  });

  test('a hand-written declaration reads modes too, and refuses bad ones', () {
    var parsed = parseTokensFile('''
final sceneTokens = [
  Token<double>('gap', 8, modes: {'dense': 4, 'wide': 12}),
  Token<double>('bad', 8, modes: {'1x': 4}),
  Token<Foo>('opaque', foo, modes: {'dark': bar}),
];
''');
    expect(parsed.tokens.single.modes, {'dense': 4.0, 'wide': 12.0});
    expect(parsed.refusals.map((r) => r.construct), [
      'mode name',
      'token type',
    ], reason: "the app's own object is an export, not a library value");
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
  late final label = TextNode(tokens.copyCTA, color: tokens.textOnBrand);
  @override
  late final root = FrameNode(width: 200, height: 100, fill: tokens.brandPrimary, corner: tokens.radiusCard, children: [label]);
}
''');
      var result = generateSceneArgsIn(dir.path).values.single;
      expect(result.refusals, isEmpty, reason: result.refusals.join('\n'));
      expect(result.wrote, isTrue);
      expect(result.source, contains('class SceneTokens {'));
      expect(result.source, contains('static const darkMode = SceneTokens('));
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
