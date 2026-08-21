import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:flutterware_app/src/comparison/frame_ref.dart';
import 'package:flutterware_app/src/comparison/pixel_diff.dart';
import 'package:flutterware_app/src/comparison/shot_store.dart';
import 'package:flutterware_app/src/comparison/ui/shot_image.dart';
import 'package:flutterware_app/src/comparison/ui/stage.dart';

import 'app_theme.dart';

/// The comparison stage over a staged pair of frames: a button that moved
/// 12px down and changed shade, and a badge that appeared.
///
/// What this is for. The stage only ever appears after a comparison run,
/// which prices a look at it in minutes; here the two frames are drawn on a
/// canvas and the diff is written by hand to match, so every mode — the boxes
/// on the head half, the slider's boundary, the pills' hover — is one preview
/// away. The pills are live: pick a mode and it switches.
class _NoStore implements ShotStore {
  const _NoStore();

  @override
  Future<Shot?> byKey(String key) async => null;

  @override
  Future<Shot?> byRef(FrameRef ref) async => null;
}

@Preview(name: 'Comparison stage', group: 'Comparison', wrapper: wrapInAppTheme)
Widget comparisonStage() => const _Demo();

@Preview(
  name: 'Comparison stage · pixels',
  group: 'Comparison',
  wrapper: wrapInAppTheme,
)
Widget comparisonStagePixels() => const _Demo(mode: StageMode.pixels);

@Preview(
  name: 'Comparison stage · dark',
  group: 'Comparison',
  wrapper: wrapInDarkTheme,
)
Widget comparisonStageDark() => const _Demo();

class _Demo extends StatefulWidget {
  const _Demo({this.mode = StageMode.sideBySide});

  final StageMode mode;

  @override
  State<_Demo> createState() => _DemoState();
}

class _DemoState extends State<_Demo> {
  late var _mode = widget.mode;

  late final _shots = ShotPair(const _NoStore())
    ..base = Shot(_frame(head: false))
    ..head = Shot(_frame(head: true))
    ..settled = true;

  /// Written to match what [_frame] draws: the button's old and new places as
  /// one union box, the badge as its own.
  static const _diff = PixelDiff(
    width: 390,
    height: 280,
    changedPixels: 6300,
    comparedPixels: 390 * 280,
    sizeChanged: false,
    clusters: [
      DiffRect(x: 24, y: 200, width: 120, height: 48, pixels: 6100),
      DiffRect(x: 348, y: 20, width: 16, height: 16, pixels: 200),
    ],
  );

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 860,
    height: 480,
    child: ComparisonStage(
      shots: _shots,
      mode: _mode,
      onMode: (mode) => setState(() => _mode = mode),
      diff: _diff,
    ),
  );

  @override
  void dispose() {
    _shots.dispose();
    super.dispose();
  }
}

/// A little app screen: header, three lines of "text", a primary button. The
/// head moves the button down 12px, darkens it, and grows a badge.
ui.Image _frame({required bool head}) {
  var recorder = ui.PictureRecorder();
  var canvas = Canvas(recorder);
  void bar(Rect rect, Color color) => canvas.drawRRect(
    RRect.fromRectAndRadius(rect, const Radius.circular(6)),
    Paint()..color = color,
  );

  canvas
    ..drawRect(
      const Rect.fromLTWH(0, 0, 390, 280),
      Paint()..color = const Color(0xffffffff),
    )
    ..drawRect(
      const Rect.fromLTWH(0, 0, 390, 56),
      Paint()..color = const Color(0xff1f2937),
    );
  bar(const Rect.fromLTWH(16, 22, 120, 12), const Color(0xffe5e7eb));
  bar(const Rect.fromLTWH(24, 88, 340, 12), const Color(0xffd1d5db));
  bar(const Rect.fromLTWH(24, 116, 300, 12), const Color(0xffd1d5db));
  bar(const Rect.fromLTWH(24, 144, 260, 12), const Color(0xffd1d5db));
  if (head) {
    canvas.drawCircle(
      const Offset(356, 28),
      7,
      Paint()..color = const Color(0xffef4444),
    );
  }
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      Rect.fromLTWH(24, head ? 212 : 200, 120, 36),
      const Radius.circular(8),
    ),
    Paint()..color = head ? const Color(0xff1d4ed8) : const Color(0xff3b82f6),
  );
  return recorder.endRecording().toImageSync(390, 280);
}
