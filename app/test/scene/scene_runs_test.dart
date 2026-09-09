// Runs: a paragraph in several stretches, each with a delta over the node's
// own style — and the grammar that spells one.
//
// The graders are the round trip, that a delta carries ONLY what it says,
// and the two things a run may not do.
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware/scene_authoring.dart';
import 'package:flutterware_app/src/scene/scene_file.dart';

const _rich =
    '''
$sceneFileMarker
import 'package:flutterware/scene_authoring.dart';

class Card() extends SceneDefinition {
  late final line = TextNode.rich([
    TextRun('Fresh '),
    TextRun('coffee', style: SceneTextStyle(weight: SceneFontWeight.w700, color: SceneColor(0xFFE8632B))),
    TextRun(', faster'),
  ], style: SceneTextStyle(fontSize: 40));
  @override
  late final root = FrameNode(children: [line]);
}
''';

SceneParse _parse(String s) => parseSceneFile(s);

void main() {
  test('a paragraph of runs round-trips, and the deltas stay deltas', () {
    var parsed = _parse(_rich);
    expect(parsed.refusals, isEmpty, reason: parsed.refusals.join('\n'));
    var t = parsed.doc!.nodeNamed('line')! as TextNode;
    expect(t.runs.map((r) => r.text), ['Fresh ', 'coffee', ', faster']);
    expect(t.text, 'Fresh coffee, faster', reason: 'the joined string');
    expect(t.fontSize, 40, reason: "the node's own style still resolves");
    // Only what the run says. A delta that carried the table's defaults for
    // everything else would override the node on every one of them.
    expect(t.runs[1].style!.values.keys, ['weight', 'color']);
    expect(t.runs[0].style, isNull);
    expect(
      emitSceneFile(parsed.doc!, className: 'Card'),
      contains('TextNode.rich(['),
    );
  });

  test('one run keeps the short spelling', () {
    var doc = SceneDocument(
      FrameNode(name: 'root')..children.add(TextNode('Hello', name: 'line')),
    );
    var out = emitSceneFile(doc, className: 'Card');
    expect(out, contains("TextNode('Hello'"));
    expect(out, isNot(contains('TextNode.rich')));
    // And writing the whole string back collapses the runs, which is what
    // typing into one field means.
    var t = doc.nodeNamed('line')! as TextNode;
    t.runs = [const TextRun('a'), const TextRun('b')];
    expect(t.text, 'ab');
    t.text = 'one';
    expect(t.runs, [const TextRun('one')]);
  });

  test('a run may not carry a paint stack', () {
    // The stack paints a whole laid-out paragraph once per pass; one that
    // applied to a stretch would have to lay that stretch out alone.
    var parsed = _parse('''
$sceneFileMarker
import 'package:flutterware/scene_authoring.dart';

class Card() extends SceneDefinition {
  late final line = TextNode.rich([
    TextRun('a', style: SceneTextStyle(layers: [FillLayer()])),
  ]);
  @override
  late final root = FrameNode(children: [line]);
}
''');
    expect(parsed.doc, isNull);
    expect(
      parsed.refusals.single.toString(),
      contains('paint stack paints the whole paragraph'),
    );
  });

  test('a run is a TextRun and its text is a literal', () {
    for (var body in [
      "TextNode.rich([TextRun('a'), 'b'])",
      'TextNode.rich([TextRun(headline)])',
      "TextNode.rich('a')",
    ]) {
      var parsed = _parse('''
$sceneFileMarker
import 'package:flutterware/scene_authoring.dart';

class Card() extends SceneDefinition {
  late final line = $body;
  @override
  late final root = FrameNode(children: [line]);
}
''');
      expect(parsed.doc, isNull, reason: body);
      expect(parsed.refusals, isNotEmpty, reason: body);
    }
  });
}
