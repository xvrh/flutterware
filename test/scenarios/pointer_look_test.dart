import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware/reel.dart';
import 'package:flutterware/scene_authoring.dart';

/// The cursor's look is the pointer node's args: a reel picks the colours,
/// the size and whether a press ripples, and the stage draws what it said.
void main() {
  group('PointerArgs', () {
    test('carries the look and takes fx over it', () {
      const args = PointerArgs(
        ink: SceneColor(0xFF112233),
        size: 1.5,
        ripple: false,
      );
      expect(args.toMap(), {'ink': 0xFF112233, 'size': 1.5, 'ripple': false});
      var look = args.look;
      expect(look.ink, const Color(0xFF112233));
      // Unset is the film's own, not black.
      expect(look.paper, CursorLook.standard.paper);
      expect(look.size, 1.5);
      expect(look.ripple, isFalse);

      // What a track on `args.size` or `args.paper` does.
      var moved = args.merge(
        const SceneArgs({'size': 0.5, 'paper': 0xFFABCDEF}),
      );
      expect(moved.size, 0.5);
      expect(moved.paper, const SceneColor(0xFFABCDEF));
      expect(moved.ink, const SceneColor(0xFF112233));
    });

    test('says nothing about colours it did not set', () {
      expect(const PointerArgs().toMap(), {'size': 1.0, 'ripple': true});
    });
  });

  testWidgets('the stage draws the finger in the look the reel chose', (
    tester,
  ) async {
    const screen = Size(120, 120);
    Future<ui.Image> draw(PointerArgs args) async {
      var root = FrameNode(name: 'root')
        ..width = screen.width
        ..height = screen.height
        ..fill = const SceneColor(0xFFFFFFFF)
        ..children.add(
          ExternalNode(args, name: 'pointer')
            ..width = screen.width
            ..height = screen.height,
        );
      var stage = MountedStage(
        SceneStage(SceneDocument(root)),
        screenSize: screen,
        scale: 1,
        touch: true,
      );
      try {
        return stage.render(
          const StageFrame(
            screen: null,
            screenSize: screen,
            at: Duration.zero,
            pointer: Offset(60, 60),
            down: true,
            sincePress: 0.05,
            touch: true,
          ),
        );
      } finally {
        stage.dispose();
      }
    }

    Future<Color> pixel(ui.Image image, int x, int y) async {
      var bytes = (await image.toByteData())!;
      var i = (y * image.width + x) * 4;
      return Color.fromARGB(
        bytes.getUint8(i + 3),
        bytes.getUint8(i),
        bytes.getUint8(i + 1),
        bytes.getUint8(i + 2),
      );
    }

    await tester.runAsync(() async {
      // A pressed fingertip in pure red ink, drawn where the pointer is. The
      // standard look is a translucent dark mark, so red at the contact point
      // can only be the reel's choice.
      var red = await draw(
        const PointerArgs(
          ink: SceneColor(0xFFFF0000),
          paper: SceneColor(0xFFFF0000),
          ripple: false,
        ),
      );
      var centre = await pixel(red, 60, 60);
      expect(centre.r, greaterThan(0.9));
      expect(centre.g, lessThan(0.7));

      // Size is size: at 2× the mark covers a point the 1× mark leaves white.
      var big = await draw(
        const PointerArgs(
          ink: SceneColor(0xFFFF0000),
          paper: SceneColor(0xFFFF0000),
          size: 2,
          ripple: false,
        ),
      );
      // A pressed 1× fingertip has radius 15.6; 26 points out is white for
      // it and red for the 2× one.
      var small = await pixel(red, 86, 60);
      var large = await pixel(big, 86, 60);
      expect(small.g, greaterThan(0.9), reason: 'outside the 1× finger');
      expect(large.g, lessThan(0.7), reason: 'inside the 2× finger');
    });
  });
}
