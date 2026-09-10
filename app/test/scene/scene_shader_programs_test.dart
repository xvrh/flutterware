// The program cache and the per-draw shader pool. Plain `test()`s with real
// async: `FragmentProgram.fromAsset` never completes under `testWidgets`'
// FakeAsync without `runAsync`.
import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware/real_work.dart';
import 'package:flutterware/scene.dart' show precacheSceneShaders;
import 'package:flutterware/scene_authoring.dart';
import 'package:flutterware/src/scene/shader_programs.dart'
    hide precacheSceneShaders;

const probe = 'test/scene/shaders/probe.frag';
const bare = 'test/scene/shaders/probe_bare.frag';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('programs', () {
    late SceneShaderPrograms programs;
    setUp(() => programs = SceneShaderPrograms());

    test(
      'a program is null until its load lands, and listeners hear it land',
      () async {
        var heard = 0;
        programs.addListener(() => heard++);
        expect(programs.program(probe), isNull);
        expect(programs.pending, [probe]);
        await programs.load(probe);
        expect(programs.program(probe), isNotNull);
        expect(programs.pending, isEmpty);
        expect(heard, 1);
      },
    );

    test('a load in flight is real work a harness waits for', () async {
      var before = RealWork.pending;
      programs.program(probe);
      expect(RealWork.pending, before + 1);
      await programs.load(probe);
      expect(RealWork.pending, before);
    });

    test(
      'a missing asset stays null, says why, and is not asked for again',
      () async {
        var printed = <String?>[];
        var original = debugPrint;
        debugPrint = (message, {wrapWidth}) => printed.add(message);
        addTearDown(() => debugPrint = original);

        await programs.load('no/such.frag');
        expect(programs.program('no/such.frag'), isNull);
        expect(programs.errorFor('no/such.frag'), isNotNull);
        expect(programs.pending, isEmpty);
        expect(printed, hasLength(1));
      },
    );

    test('settle names what is still loading when time runs out', () async {
      var gate = Completer<ui.FragmentProgram>();
      var slow = SceneShaderPrograms(loader: (_) => gate.future);
      slow.program('slow.frag');
      expect(await slow.settle(timeout: const Duration(milliseconds: 20)), [
        'slow.frag',
      ]);
      gate.complete(await ui.FragmentProgram.fromAsset(probe));
      expect(await slow.settle(timeout: const Duration(seconds: 1)), isEmpty);
    });
  });

  group('slots', () {
    late ui.FragmentProgram program;
    setUpAll(() async => program = await ui.FragmentProgram.fromAsset(probe));

    late List<String?> printed;
    setUp(() {
      printed = [];
      var original = debugPrint;
      debugPrint = (message, {wrapWidth}) => printed.add(message);
      addTearDown(() => debugPrint = original);
      SceneShaderPrograms.instance.reset();
    });

    test('one slot per pass and line, the same one frame after frame', () {
      var slots = SceneShaderSlots();
      var a = slots.slot(program, probe, 0, 0);
      expect(slots.slot(program, probe, 0, 0), same(a));
      expect(slots.slot(program, probe, 0, 1).shader, isNot(same(a.shader)));
      expect(slots.slot(program, probe, 1, 0).shader, isNot(same(a.shader)));
      slots.dispose();
    });

    test('a slot whose program changed is a new shader', () async {
      var slots = SceneShaderSlots();
      var a = slots.slot(program, probe, 0, 0);
      var other = await ui.FragmentProgram.fromAsset(bare);
      expect(slots.slot(other, bare, 0, 0).shader, isNot(same(a.shader)));
      slots.dispose();
    });

    test('an undeclared uniform, or one of the wrong size, is skipped', () {
      var slots = SceneShaderSlots();
      var skipped = slots
          .slot(program, probe, 0, 0)
          .setUniforms(
            const ShaderPaint(
              probe,
              uniforms: {
                'uTint': [1, 0, 0],
                'uMissing': [1],
                'uMode': [1, 2],
              },
            ),
            size: const ui.Size(10, 10),
            color: const ui.Color(0xFF000000),
            seconds: 0,
          );
      expect(skipped, unorderedEquals(['uMissing', 'uMode']));
      slots.dispose();
    });

    test('one float is set on a float and refused by a wider uniform', () {
      var slots = SceneShaderSlots();
      var skipped = slots
          .slot(program, probe, 0, 0)
          .setUniforms(
            const ShaderPaint(
              probe,
              uniforms: {
                'uMode': [2],
                'uTint': [1],
              },
            ),
            size: const ui.Size(10, 10),
            color: const ui.Color(0xFF000000),
            seconds: 0,
          );
      expect(skipped, ['uTint']);
      slots.dispose();
    });

    test('a skipped uniform is reported once per asset and name', () {
      var slots = SceneShaderSlots();
      for (var line = 0; line < 3; line++) {
        slots
            .slot(program, probe, 0, line)
            .setUniforms(
              const ShaderPaint(
                probe,
                uniforms: {
                  'uMissing': [1],
                },
              ),
              size: const ui.Size(10, 10),
              color: const ui.Color(0xFF000000),
              seconds: 0,
            );
      }
      expect(printed, hasLength(1));
      expect(printed.single, contains('uMissing'));
      slots.dispose();
    });

    test('a renderer uniform declared at another size is left alone', () async {
      var slots = SceneShaderSlots();
      var other = await ui.FragmentProgram.fromAsset(bare);
      expect(
        () => slots
            .slot(other, bare, 0, 0)
            .setUniforms(
              const ShaderPaint(
                bare,
                uniforms: {
                  'uTint': [0, 1, 0],
                },
              ),
              size: const ui.Size(10, 10),
              color: const ui.Color(0xFF000000),
              seconds: 1,
            ),
        returnsNormally,
      );
      slots.dispose();
    });

    test('an author value for a renderer uniform loses to the renderer', () {
      var slots = SceneShaderSlots();
      var skipped = slots
          .slot(program, probe, 0, 0)
          .setUniforms(
            const ShaderPaint(
              probe,
              uniforms: {
                'uTime': [9],
              },
            ),
            size: const ui.Size(10, 10),
            color: const ui.Color(0xFF000000),
            seconds: 0,
          );
      expect(skipped, isEmpty); // not an error — just not the author's to set
      slots.dispose();
    });
  });

  test('precache loads every shader a scene paints with', () async {
    var doc = SceneDocument(
      FrameNode(name: 'root')
        ..width = 100
        ..height = 100
        ..children.addAll([
          TextNode(
            'T',
            name: 't',
            style: SceneTextStyle(
              layers: [
                FillLayer(paint: ShaderPaint(probe)),
                FillLayer(paint: ShaderPaint('')),
              ],
            ),
          ),
          TextNode('U', name: 'u'),
        ]),
    );
    await precacheSceneShaders(doc);
    expect(SceneShaderPrograms.instance.program(probe), isNotNull);
    expect(sceneShaderAssets(doc), {probe});
  });
}
