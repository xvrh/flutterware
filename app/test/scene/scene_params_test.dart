// The parameter doors: declare, rename, retype, delete, set the mockup, and
// connect a property to a parameter. Every refusal here is a file that would
// not have compiled.
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware/scene_authoring.dart';
import 'package:flutterware_app/src/scene/editor.dart';
import 'package:flutterware_app/src/scene/scene_file.dart';

const _source =
    '''
$sceneFileMarker
import 'package:flutterware/scene_authoring.dart';

class Card({
  final String title = 'Hello',
  final SceneColor accent = const SceneColor(0xFF112233),
}) extends SceneDefinition {
  late final headline = TextNode(title, fontSize: 20, color: accent);
  late final box = FrameNode(x: 40, width: 80, height: 20, fill: accent);
  @override
  late final root = FrameNode(width: 200, height: 100, children: [headline, box]);
}
''';

SceneEditor open() => SceneEditor(parseSceneFile(_source).doc!);

String emit(SceneEditor e) => emitSceneFile(e.doc, className: 'Card');

void main() {
  test('add declares a parameter at the kind\'s zero, or a chosen mockup', () {
    var e = open();
    e.addParam('slide', SceneParamKind.number);
    e.addParam('cta', SceneParamKind.string, defaultValue: 'Go');
    expect(e.doc.paramNamed('slide')!.defaultValue, 0.0);
    expect(emit(e), contains("final String cta = 'Go'"));
    expect(emit(e), contains('final double slide = 0'));
  });

  test('a name a node or parameter already has is refused', () {
    var e = open();
    expect(() => e.addParam('box', SceneParamKind.number), throwsArgumentError);
    expect(
      () => e.addParam('title', SceneParamKind.number),
      throwsArgumentError,
    );
    expect(
      () => e.addParam('1bad', SceneParamKind.number),
      throwsArgumentError,
    );
    expect(e.freeParamName('title'), 'title2');
  });

  test('rename follows every reader', () {
    var e = open();
    e.renameParam('accent', 'tint');
    var box = e.doc.nodeNamed('box')!;
    var headline = e.doc.nodeNamed('headline')!;
    expect(box.bindings['fill'], const ParamRef('tint'));
    expect(headline.bindings['color'], const ParamRef('tint'));
    var out = emit(e);
    expect(out, contains('final SceneColor tint'));
    expect(out, contains('fill: tint'));
    expect(out, isNot(contains('accent')));
    expect(parseSceneFile(out).refusals, isEmpty);
  });

  test('setting the mockup reaches every reader', () {
    var e = open();
    e.setParamDefault('accent', const SceneColor(0xFFABCDEF));
    expect(e.doc.nodeNamed('box')!.fill, const SceneColor(0xFFABCDEF));
    expect(
      (e.doc.nodeNamed('headline')! as TextNode).color,
      const SceneColor(0xFFABCDEF),
    );
    expect(() => e.setParamDefault('accent', 'red'), throwsArgumentError);
  });

  test('delete and retype refuse while something reads the parameter', () {
    var e = open();
    expect(() => e.deleteParam('accent'), throwsArgumentError);
    expect(
      () => e.retypeParam('accent', SceneParamKind.string),
      throwsArgumentError,
    );
    expect(e.readersOf('accent').map((r) => '${r.$1.name}.${r.$2}'), [
      'headline.color',
      'box.fill',
    ]);
    e.unbind(e.doc.nodeNamed('headline')!, 'color');
    e.unbind(e.doc.nodeNamed('box')!, 'fill');
    e.retypeParam('accent', SceneParamKind.string);
    expect(e.doc.paramNamed('accent')!.kind, SceneParamKind.string);
    e.deleteParam('accent');
    expect(e.doc.paramNamed('accent'), isNull);
    // The values stayed where they were.
    expect(e.doc.nodeNamed('box')!.fill, const SceneColor(0xFF112233));
  });

  test('bind takes the parameter\'s default and refuses a kind mismatch', () {
    var e = open();
    var box = e.doc.nodeNamed('box')!;
    e.addParam('slide', SceneParamKind.number, defaultValue: 24.0);
    e.bind(box, 'x', 'slide');
    expect(box.x, 24);
    expect(box.bindings['x'], const ParamRef('slide'));
    expect(() => e.bind(box, 'x', 'title'), throwsArgumentError);
    expect(() => e.bind(box, 'layout', 'slide'), throwsArgumentError);
    expect(emit(e), contains('x: slide'));
  });

  test('promote makes a parameter of the value a property holds', () {
    var e = open();
    var box = e.doc.nodeNamed('box')!;
    var name = e.promote(box, 'x');
    expect(name, 'x');
    expect(e.doc.paramNamed('x')!.defaultValue, 40.0);
    expect(box.bindings['x'], const ParamRef('x'));
    var out = emit(e);
    expect(out, contains('final double x = 40'));
    expect(out, contains('x: x'));
    expect(parseSceneFile(out).refusals, isEmpty);
    // One undo entry takes both the declaration and the binding back.
    e.undo();
    expect(e.doc.paramNamed('x'), isNull);
    expect(box.bindings.containsKey('x'), isFalse);
    expect(box.x, 40);
  });

  test('move reorders the constructor', () {
    var e = open();
    e.moveParam('accent', 0);
    expect(e.doc.params.map((p) => p.name), ['accent', 'title']);
    expect(emit(e), matches(RegExp(r'accent.*\n.*title', dotAll: false)));
  });
}
