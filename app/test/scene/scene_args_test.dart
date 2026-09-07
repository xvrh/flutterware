// The declaration and what it generates.
//
// Two things are checked here, and they are the whole of what stands in for
// resolving the app package: that a declaration file is read exactly — with
// a line number for anything outside its shape — and that what the tool
// writes from it is the vocabulary a scene file and a motion then spell.
//
// The third grader is elsewhere and stronger: `scene_args.dart` beside this
// test is generated, `sample.scene.dart` imports it, and the compiler
// refuses a scene naming an argument that class does not have.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware/scene_authoring.dart';
import 'package:flutterware_app/src/scene/args_codegen.dart';
import 'package:flutterware_app/src/scene/args_generate.dart';
import 'package:flutterware_app/src/scene/externals_file.dart';
import 'package:flutterware_app/src/scene/group_file.dart';
import 'package:flutterware_app/src/scene/scene_file.dart';
import 'package:flutterware_app/src/scene/tokens_file.dart';

void main() {
  group('a group declaration', () {
    test('names a widget, its arguments, their types and their defaults', () {
      var parsed = parseGroupFile('''
import 'package:flutterware/scene_authoring.dart';

final scenes = SceneGroup(widgets: [
  ExternalWidget(
    'DrinkBadge',
    args: [const Arg<double>('size', 56), const Arg<String>('label')],
    build: (a) => DrinkBadge(size: a.number('size') ?? 56),
  ),
], wrap: (child) => child);
''');
      expect(parsed.refusals, isEmpty);
      var widget = parsed.widgets.single;
      expect(widget.entry, 'DrinkBadge');
      expect(widget.args.map((a) => a.name), ['size', 'label']);
      expect(widget.args.map((a) => a.typeName), ['double', 'String']);
      expect(widget.args.map((a) => a.defaultSource), ['56', null]);
    });

    test('reads the real one beside this test', () {
      var parsed = parseGroupFile(
        File('test/scene/scenes.dart').readAsStringSync(),
      );
      expect(parsed.refusals, isEmpty);
      expect(parsed.widgets.single.entry, 'SampleChip');
      expect(parsed.libraries.single.symbol, 'sampleTokens');
    });

    test('refuses an argument with no type to check it against', () {
      var parsed = parseGroupFile('''
final scenes = SceneGroup(widgets: [
  ExternalWidget('DrinkBadge', args: [Arg('size', 56)], build: (a) => 1),
]);
''');
      expect(parsed.refusals.single.construct, 'argument type');
      expect(parsed.refusals.single.line, 2);
    });

    test('refuses a file that declares nothing', () {
      var parsed = parseGroupFile('final widgets = [];');
      expect(parsed.refusals.single.construct, 'no declaration');
    });

    test('resolves a library through the imports, and refuses one it '
        'cannot', () {
      var dir = Directory.systemTemp.createTempSync('fw_group');
      addTearDown(() => dir.deleteSync(recursive: true));
      var library = File('${dir.path}/brand.tokens.dart')
        ..writeAsStringSync('$sceneTokensFileMarker\nfinal brandTokens = [];');
      var declaration = '${dir.path}/$sceneGroupFileName';
      String? symbolAt(String path) =>
          path == library.path ? tokensSymbolFor(path) : null;
      var parsed = parseGroupFile(
        "import 'brand.tokens.dart';\n"
        'final scenes = SceneGroup(libraries: [brandTokens, storeTokens]);',
        resolveImport: importResolverFor(declaration),
        librarySymbolAt: symbolAt,
      );
      expect(parsed.libraries.single.path, library.path);
      expect(parsed.refusals.single.construct, 'library');
      expect(parsed.refusals.single.message, contains('storeTokens'));
    });

    test('attaches a library: one import, one list element, nothing else', () {
      var source =
          '''
$sceneGroupFileMarker
import 'package:flutterware/scene.dart';

final scenes = SceneGroup(widgets: []);
''';
      var attached = attachLibraryIn(
        source,
        '/pkg/lib/scenes/scenes.dart',
        '/pkg/lib/design/brand.tokens.dart',
        refuse: (r) => fail(r),
      )!;
      expect(attached, contains("import '../design/brand.tokens.dart';"));
      expect(
        attached,
        contains('SceneGroup(libraries: [brandTokens], widgets: [])'),
      );
      var again = attachLibraryIn(
        attached,
        '/pkg/lib/scenes/scenes.dart',
        '/pkg/lib/design/brand.tokens.dart',
        refuse: (r) => fail(r),
      );
      expect(again, attached, reason: 'already attached is a no-op');
      var detached = detachLibraryIn(
        attached,
        '/pkg/lib/scenes/scenes.dart',
        '/pkg/lib/design/brand.tokens.dart',
        refuse: (r) => fail(r),
      )!;
      expect(detached, isNot(contains('brand.tokens.dart')));
      expect(detached, contains('libraries: [], widgets: []'));
    });
  });

  group('the generated vocabulary', () {
    var source = emitSceneArgs(
      externals: [
        ExternalWidgetDecl('DrinkBadge', [
          ExternalArgDecl('size', 'double', '56'),
          ExternalArgDecl('label', 'String', null),
        ]),
      ],
      scenes: [
        SceneClassDecl('PromoBadge', [
          SceneParamDecl('label', SceneParamKind.string, 'New'),
        ], 'promo_badge.scene.dart'),
      ],
    );

    test('is one class per widget, typed by the declaration', () {
      expect(source, contains('class DrinkBadgeArgs extends SceneExtArgs {'));
      expect(source, contains('final double size;'));
      // No default declared, so the field is nullable and the widget's own
      // fallback is what answers.
      expect(source, contains('final String? label;'));
      expect(
        source,
        contains('const DrinkBadgeArgs({this.size = 56, this.label});'),
      );
    });

    test('gives a track slot only to what has in-between values', () {
      // `size` interpolates; a label does not, so animating one is not a
      // refusal but a name that does not exist.
      expect(
        source,
        contains('class DrinkBadgeTracks extends SceneExtTracks {'),
      );
      expect(source, contains('final MotionTrack? size;'));
      expect(source, isNot(contains('MotionTrack? label')));
    });

    test('builds an external through the declaration it came from', () {
      expect(
        source,
        contains("_external('DrinkBadge').build(SceneArgs(toMap()))"),
      );
      expect(
        source,
        contains('scenes.widgets.firstWhere((w) => w.entry == entry)'),
      );
    });

    test('builds a nested scene by calling its constructor', () {
      expect(source, contains('class PromoBadgeArgs extends SceneRefArgs {'));
      expect(
        source,
        contains('SceneDefinition build() => PromoBadge(label: label);'),
      );
    });
  });

  test('the vocabulary beside this test is what the generator writes', () {
    // The guard that keeps the two halves honest: `scene_args.dart` is
    // generated, `sample.scene.dart` imports it, and a declaration that
    // moved without a regeneration fails here rather than in whatever the
    // compiler says next.
    var result = generateSceneArgsIn('test/scene', write: false).values.single;
    expect(result.refusals, isEmpty, reason: result.refusals.join('\n'));
    expect(
      result.source,
      File('test/scene/scene_args.dart').readAsStringSync(),
      reason: 'stale — regenerate scene_args.dart',
    );
  });

  test('a scene naming an argument the widget does not declare is refused', () {
    var parsed = parseSceneFile(
      '''
$sceneFileMarker
$sceneAuthoringImport

import '$sceneArgsFileName';

class S extends SceneDefinition {
  late final badge = ExternalNode(const DrinkBadgeArgs(progress: 1));
  @override
  late final root = FrameNode(width: 100, height: 100, children: [badge]);
}
''',
      declaredArgs: {
        'DrinkBadge': {'size'},
      },
    );
    expect(parsed.ok, isFalse);
    var refusal = parsed.refusals.single;
    expect(refusal.construct, 'unknown argument');
    expect(refusal.message, contains('DrinkBadge declares no "progress"'));
    expect(refusal.message, contains('it takes size'));
    expect(refusal.line, 7);
  });
}
