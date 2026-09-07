// The bridge's fidelity contract: the pure core mirrors Flutter's value
// vocabulary, and this file is what keeps the mirror honest — every enum
// order pinned index-by-index, and all 13 curves compared against the
// framework across sampled inputs (the ports are algorithm-identical, so
// equality is exact, not approximate).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware/scene.dart';
import 'package:flutterware/scene_authoring.dart';

void main() {
  test('font weights convert by index and agree on the numeric value', () {
    expect(SceneFontWeight.values.length, FontWeight.values.length);
    for (var w in SceneFontWeight.values) {
      expect(w.flutter, FontWeight.values[w.index]);
      expect(w.flutter.value, w.value);
    }
  });

  test('cross-axis alignment order matches Flutter', () {
    expect(
      SceneCrossAxisAlignment.values.map((v) => v.name),
      CrossAxisAlignment.values.map((v) => v.name),
    );
    for (var v in SceneCrossAxisAlignment.values) {
      expect(v.flutter.name, v.name);
    }
  });

  test('main-axis alignment order matches Flutter', () {
    expect(
      SceneMainAxisAlignment.values.map((v) => v.name),
      MainAxisAlignment.values.map((v) => v.name),
    );
    for (var v in SceneMainAxisAlignment.values) {
      expect(v.flutter.name, v.name);
    }
  });

  test('colors and rects round-trip through the bridge', () {
    const argb = 0xB34A64D0;
    expect(const SceneColor(argb).flutter.toARGB32(), argb);
    expect(const Color(argb).scene.argb, argb);
    const rect = SceneRect(3.5, -2, 120, 44.25);
    expect(rect.flutter, const Rect.fromLTWH(3.5, -2, 120, 44.25));
    expect(rect.flutter.scene, rect);
  });

  test('all 13 curves evaluate exactly as Flutter does', () {
    var flutterCurves = <String, Curve>{
      'linear': Curves.linear,
      'ease': Curves.ease,
      'easeIn': Curves.easeIn,
      'easeOut': Curves.easeOut,
      'easeInOut': Curves.easeInOut,
      'easeInBack': Curves.easeInBack,
      'easeOutBack': Curves.easeOutBack,
      'easeInCubic': Curves.easeInCubic,
      'easeOutCubic': Curves.easeOutCubic,
      'decelerate': Curves.decelerate,
      'fastOutSlowIn': Curves.fastOutSlowIn,
      'bounceOut': Curves.bounceOut,
      'elasticOut': Curves.elasticOut,
    };
    expect(sceneCurvesByName.keys.toSet(), flutterCurves.keys.toSet());
    for (var entry in sceneCurvesByName.entries) {
      var flutter = flutterCurves[entry.key]!;
      for (var i = 0; i <= 100; i++) {
        var t = i / 100;
        expect(
          entry.value.transform(t),
          flutter.transform(t),
          reason: '${entry.key} diverges at t=$t',
        );
      }
    }
  });
}
