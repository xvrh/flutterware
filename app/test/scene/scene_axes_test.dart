// A face's axes where the editor meets them: what can be animated, and what
// each key is called.
//
// The table cannot answer either question for an axis — the tags come from
// the font — so this is the seam, and it is the seam a menu and a lane both
// read through.
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware/scene_authoring.dart';
import 'package:flutterware_app/src/assets/model/font_axes.dart';
import 'package:flutterware_app/src/scene/type_axes.dart';

const _archivo = [
  FontAxis('wght', min: 100, def: 600, max: 900),
  FontAxis('wdth', min: 62, def: 100, max: 125),
];

List<FontAxis> _lookup(String family) =>
    family == 'Archivo' ? _archivo : const [];

void main() {
  test('a variable family adds one animatable key per axis', () {
    var t = TextNode('x', style: const SceneTextStyle(fontFamily: 'Archivo'));
    var offered = sceneAnimatableProps(t, _lookup);
    var axes = offered.where((s) => sceneAxisTag(s.name) != null).toList();
    expect(axes.map((s) => s.name), ['axes.wght', 'axes.wdth']);
    expect(axes.first.kind, TrackKind.number);
    // The range and the resting value are the FONT's. The resting one is
    // what nobody could have guessed: Archivo's weight rests at 600.
    expect(axes.first.softMin, 100);
    expect(axes.first.softMax, 900);
    expect(axes.first.identity, 600);
    // And the table's own rows are still all there.
    expect(offered.map((s) => s.name), containsAll(['fontSize', 'color']));
  });

  test('a static family, an unset one and no lookup add nothing', () {
    var offered = [
      sceneAnimatableProps(
        TextNode('x', style: const SceneTextStyle(fontFamily: 'Roboto')),
        _lookup,
      ),
      sceneAnimatableProps(TextNode('x'), _lookup),
      sceneAnimatableProps(
        TextNode('x', style: const SceneTextStyle(fontFamily: 'Archivo')),
        null,
      ),
      sceneAnimatableProps(FrameNode(name: 'f'), _lookup),
    ];
    for (var props in offered) {
      expect(props.where((s) => sceneAxisTag(s.name) != null), isEmpty);
    }
  });

  test('a key is named with a word where there is room for one', () {
    expect(sceneKeyLabel('axes.wght'), 'Weight');
    expect(sceneKeyLabel('axes.wdth'), 'Width');
    // A tag the registry does not name is shown as itself, which is what a
    // type designer calls it anyway.
    expect(sceneKeyLabel('axes.ARCD'), 'ARCD');
    expect(sceneKeyLabel('args.size'), 'size');
    expect(sceneKeyLabel('fontSize'), 'fontSize');
  });
}
