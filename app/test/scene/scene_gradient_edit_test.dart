// What an edit to a paint does, as arithmetic: a converted paint keeps what
// it can, stops stay in order and two at least, and an angle is one number
// for a line through the middle.
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware/scene_authoring.dart';
import 'package:flutterware_app/src/scene/gradient_edit.dart';

const _red = SceneColor(0xFFFF0000);
const _green = SceneColor(0xFF00FF00);
const _blue = SceneColor(0xFF0000FF);

void main() {
  group('changing what a pass is painted with', () {
    test('a colour becomes a gradient that fades out of it', () {
      expect(
        convertPaint(const SolidPaint(_red), ScenePaintKind.linear, own: _blue),
        const LinearPaint(colors: [_red, SceneColor(0x00FF0000)]),
      );
    });

    test('the text colour becomes a gradient out of the text colour', () {
      expect(
        convertPaint(null, ScenePaintKind.radial, own: _blue),
        const RadialPaint(colors: [_blue, SceneColor(0x000000FF)]),
      );
    });

    test(
      'a gradient keeps its colours and stops through a change of shape',
      () {
        expect(
          convertPaint(
            const LinearPaint(
              colors: [_red, _green, _blue],
              stops: [0, 0.2, 1],
            ),
            ScenePaintKind.sweep,
            own: _blue,
          ),
          const SweepPaint(colors: [_red, _green, _blue], stops: [0, 0.2, 1]),
        );
      },
    );

    test(
      'a gradient becomes its first colour, and anything the text colour',
      () {
        var g = const RadialPaint(colors: [_green, _blue]);
        expect(
          convertPaint(g, ScenePaintKind.solid, own: _red),
          const SolidPaint(_green),
        );
        expect(convertPaint(g, ScenePaintKind.text, own: _red), isNull);
      },
    );

    test('the same kind is the same paint, untouched', () {
      const g = LinearPaint(
        colors: [_red, _blue],
        begin: SceneAlignment.topLeft,
      );
      expect(
        identical(convertPaint(g, ScenePaintKind.linear, own: _red), g),
        isTrue,
      );
      expect(ScenePaintKind.of(g), ScenePaintKind.linear);
      expect(ScenePaintKind.of(null), ScenePaintKind.text);
    });

    test('a shader converts like no paint: into the text colour, out of nothing kept', () {
      expect(
        ScenePaintKind.of(const ShaderPaint('a.frag')),
        ScenePaintKind.shader,
      );
      expect(
        convertPaint(
          const ShaderPaint('a.frag'),
          ScenePaintKind.solid,
          own: _blue,
        ),
        const SolidPaint(_blue),
      );
      expect(
        convertPaint(const SolidPaint(_red), ScenePaintKind.shader, own: _blue),
        const ShaderPaint(''),
      );
    });
  });

  group('stops', () {
    const g = LinearPaint(colors: [_red, _blue]);

    test('a colour at a point is the one the gradient paints there', () {
      expect(colorAt(g, 0), _red);
      expect(colorAt(g, 1), _blue);
      expect(colorAt(g, 0.5), SceneColor.lerp(_red, _blue, 0.5));
    });

    test('an added stop changes nothing until it is moved or recoloured', () {
      var edit = addStop(g, 0.5);
      expect(edit.gradient.colors, [
        _red,
        SceneColor.lerp(_red, _blue, 0.5),
        _blue,
      ]);
      expect(edit.gradient.stops, [0, 0.5, 1]);
      expect(edit.index, 1);
    });

    test('a stop moved past its neighbour is re-sorted, and followed', () {
      var three = const LinearPaint(colors: [_red, _green, _blue]);
      var edit = moveStop(three, 0, 0.8);
      expect(edit.gradient.colors, [_green, _red, _blue]);
      expect(edit.gradient.stops, [0.5, 0.8, 1]);
      expect(edit.index, 1);
    });

    test('a moved stop lands on a round number', () {
      expect(moveStop(g, 0, 0.123456).gradient.stops!.first, 0.123);
    });

    test('recolouring leaves an even spread unwritten', () {
      var edit = recolorStop(g, 1, _green);
      expect(edit.gradient.colors, [_red, _green]);
      expect(edit.gradient.stops, isNull);
    });

    test('a stop is removed down to two, and no further', () {
      var three = const LinearPaint(colors: [_red, _green, _blue]);
      var edit = removeStop(three, 2);
      expect(edit.gradient.colors, [_red, _green]);
      expect(edit.gradient.stops, [0, 0.5]);
      expect(edit.index, 1);
      expect(identical(removeStop(g, 0).gradient, g), isTrue);
    });

    test(
      'removing the middle of an even spread leaves an even spread unwritten',
      () {
        var three = const LinearPaint(colors: [_red, _green, _blue]);
        var edit = removeStop(three, 1);
        expect(edit.gradient.colors, [_red, _blue]);
        expect(edit.gradient.stops, isNull);
      },
    );

    test('shape survives every stop edit', () {
      const r = RadialPaint(colors: [_red, _blue], radius: 0.4);
      expect((addStop(r, 0.3).gradient as RadialPaint).radius, 0.4);
    });
  });

  group("a linear gradient's angle", () {
    test('is 180 for the default, which runs top to bottom', () {
      expect(linearAngle(const LinearPaint(colors: [_red, _blue])), 180);
    });

    test('spells the named ends where there are some', () {
      var across = withLinearAngle(
        const LinearPaint(colors: [_red, _blue]),
        90,
      );
      expect(across.begin, SceneAlignment.centerLeft);
      expect(across.end, SceneAlignment.centerRight);
      var corner = withLinearAngle(
        const LinearPaint(colors: [_red, _blue]),
        45,
      );
      expect(corner.begin, SceneAlignment.bottomLeft);
      expect(corner.end, SceneAlignment.topRight);
    });

    test('reads back what was written, and keeps the stops', () {
      const g = LinearPaint(colors: [_red, _blue], stops: [0.1, 0.9]);
      var turned = withLinearAngle(g, 30);
      expect(linearAngle(turned), 30);
      expect(turned.stops, [0.1, 0.9]);
      expect(linearAngle(withLinearAngle(g, -30)), 330);
    });
  });
}
