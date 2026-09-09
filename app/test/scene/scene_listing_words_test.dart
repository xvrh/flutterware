// What the scene index says it found.
//
// The listing used to describe a folder as `1 library · 3 widgets · 3
// exports`: three counts of three internal nouns, one of which names the
// direction a value travels rather than what it is. These are the sentences
// that replaced it, and each clause has to disappear cleanly when it has
// nothing to say — the empty cases are where a composed string goes wrong.
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware/scene_authoring.dart';
import 'package:flutterware_app/src/scene/args_generate.dart';
import 'package:flutterware_app/src/scene/discovery.dart';
import 'package:flutterware_app/src/scene/externals_file.dart';
import 'package:flutterware_app/src/scene/ui/listing_words.dart';

SceneEntry _scene(String name) => SceneEntry(
  path: '/pkg/demo/${name.toLowerCase()}.scene.dart',
  className: name,
  age: DateTime(2026, 9, 9),
);

SceneGroupEntry _group(List<String> scenes) =>
    SceneGroupEntry(directory: '/pkg/demo', scenes: [...scenes.map(_scene)]);

GroupVocabulary _vocabulary({
  List<String> libraries = const [],
  int widgets = 0,
  int values = 0,
}) => GroupVocabulary(
  widgets: [
    for (var i = 0; i < widgets; i++) ExternalWidgetDecl('W$i', const []),
  ],
  exports: [
    for (var i = 0; i < values; i++)
      SceneTokenDecl('v$i', SceneParamKind.number, 0.0),
  ],
  libraries: [
    for (var name in libraries)
      GroupLibrary(
        SceneLibraryEntry(path: '/pkg/demo/$name.tokens.dart'),
        const [],
      ),
  ],
  imports: const [],
);

void main() {
  group('what a folder holds', () {
    test('reads as a sentence when it holds everything', () {
      expect(
        groupSummary(
          _group(['StoreBanner', 'PromoBadge']),
          _vocabulary(libraries: ['brand'], widgets: 3, values: 3),
        ),
        '2 scenes · reads brandTokens · 3 widgets and 3 values from the app',
      );
    });

    test('a fresh folder says only that it is empty', () {
      expect(groupSummary(_group([]), _vocabulary()), 'No scenes yet');
    });

    test('a clause with nothing to say is gone, not zeroed', () {
      // `0 libraries · 0 widgets · 0 exports` was the old failure mode: three
      // counts that say the folder is fine and read as though it is broken.
      expect(
        groupSummary(_group(['Card']), _vocabulary(widgets: 1)),
        '1 scene · 1 widget from the app',
      );
      expect(
        groupSummary(_group(['Card']), _vocabulary(values: 2)),
        '1 scene · 2 values from the app',
      );
      expect(
        groupSummary(_group(['Card']), _vocabulary(libraries: ['brand', 'ui'])),
        '1 scene · reads brandTokens, uiTokens',
      );
    });
  });

  test('who reads a library', () {
    expect(readBy(const []), 'read by nothing yet');
    expect(readBy(const ['demo']), 'read by demo');
    expect(readBy(const ['demo', 'marketing']), 'read by demo, marketing');
  });
}
