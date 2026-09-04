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
import 'package:flutterware_app/src/scene/externals_file.dart';
import 'package:flutterware_app/src/scene/scene_file.dart';

void main() {
  group('a declaration file', () {
    test('names a widget, its arguments, their types and their defaults', () {
      var parsed = parseExternalsFile('''
import 'package:flutterware/scene_authoring.dart';

final sceneExternals = [
  ExternalWidget(
    'DrinkBadge',
    args: [const Arg<double>('size', 56), const Arg<String>('label')],
    build: (a) => DrinkBadge(size: a.number('size') ?? 56),
  ),
];
''');
      expect(parsed.refusals, isEmpty);
      var widget = parsed.widgets.single;
      expect(widget.entry, 'DrinkBadge');
      expect(widget.args.map((a) => a.name), ['size', 'label']);
      expect(widget.args.map((a) => a.typeName), ['double', 'String']);
      expect(widget.args.map((a) => a.defaultSource), ['56', null]);
    });

    test('reads the real one beside this test', () {
      var parsed = parseExternalsFile(
        File('test/scene/scene_externals.dart').readAsStringSync(),
      );
      expect(parsed.refusals, isEmpty);
      expect(parsed.widgets.single.entry, 'SampleChip');
    });

    test('refuses an argument with no type to check it against', () {
      var parsed = parseExternalsFile('''
final sceneExternals = [
  ExternalWidget('DrinkBadge', args: [Arg('size', 56)], build: (a) => 1),
];
''');
      expect(parsed.refusals.single.construct, 'argument type');
      expect(parsed.refusals.single.line, 2);
    });

    test('refuses a file that declares nothing', () {
      var parsed = parseExternalsFile('final widgets = [];');
      expect(parsed.refusals.single.construct, 'no declarations');
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
      externalsImport: 'scene_externals.dart',
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
        contains('sceneExternals.firstWhere((w) => w.entry == entry)'),
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
