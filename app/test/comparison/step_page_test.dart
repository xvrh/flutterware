import 'dart:ui' as ui;

import 'package:flutterware/comparison_report.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware_app/src/comparison/shot_store.dart';
import 'package:flutterware_app/src/comparison/ui/shot_image.dart';
import 'package:flutterware_app/src/comparison/ui/stage.dart';
import 'package:flutterware_app/src/comparison/ui/step_page.dart';
import 'package:flutterware_app/src/ui/theme.dart';

/// The page leads with whatever changed.
///
/// Seven shapes of finding reach this page and only one of them is a picture
/// that moved. The other six were all drawn as *a picture that moved*, which
/// on a `200 → 500` meant 415px of two identical frames over a grey line.
void main() {
  ui.Image frame() {
    var recorder = ui.PictureRecorder();
    Canvas(recorder).drawRect(
      const Rect.fromLTWH(0, 0, 40, 30),
      Paint()..color = const Color(0xff334455),
    );
    return recorder.endRecording().toImageSync(40, 30);
  }

  ShotPair pair({bool base = true, bool head = true}) => ShotPair(_NoStore())
    ..base = base ? Shot(frame()) : null
    ..head = head ? Shot(frame()) : null
    ..settled = true;

  Future<void> pump(
    WidgetTester tester,
    ComparedItem item, {
    ShotPair? shots,
  }) => tester.pumpWidget(
    MaterialApp(
      theme: appTheme,
      home: Scaffold(
        body: SizedBox(
          width: 900,
          height: 700,
          child: StepPage(
            item: item,
            shots: shots ?? pair(),
            mode: StageMode.sideBySide,
            onMode: (_) {},
            onBack: () {},
          ),
        ),
      ),
    ),
  );

  ComparedItem eventsOnly() => ComparedItem.of(
    id: 'enterText',
    baseEvents: [
      {'channel': 'network', 'title': 'POST /session', 'detail': '200'},
    ],
    headEvents: [
      {'channel': 'network', 'title': 'POST /session', 'detail': '500'},
    ],
  );

  testWidgets('a finding no picture can show does not lead with pictures', (
    tester,
  ) async {
    await pump(tester, eventsOnly());

    expect(find.text('both frames are identical'), findsOne);
    expect(find.byType(ComparisonStage), findsNothing);
    expect(find.textContaining('200 → 500'), findsOne);
  });

  // `identical` is a claim, and somebody is eventually going to check it.
  testWidgets('the frames can still be opened', (tester) async {
    await pump(tester, eventsOnly());
    await tester.tap(find.text('compare anyway'));
    await tester.pump();

    expect(find.byType(ComparisonStage), findsOne);
    expect(find.text('hide the frames'), findsOne);
  });

  testWidgets('pixels that moved still lead with the pictures', (tester) async {
    await pump(
      tester,
      ComparedItem.of(
        id: 'tap',
        pixels: const PixelDiff(
          width: 40,
          height: 30,
          changedPixels: 300,
          comparedPixels: 1200,
          sizeChanged: false,
          clusters: [DiffRect(x: 0, y: 0, width: 10, height: 10, pixels: 300)],
        ),
      ),
    );

    expect(find.byType(ComparisonStage), findsOne);
    expect(find.text('both frames are identical'), findsNothing);
  });

  // One side missing is its own finding and the stage already draws it well:
  // the frame labelled `base only`, the mode pills disabled, the note in red.
  testWidgets('a side that did not render keeps the stage', (tester) async {
    await pump(
      tester,
      ComparedItem.of(id: 'Order placed', headRendered: false),
      shots: pair(head: false),
    );

    expect(find.byType(ComparisonStage), findsOne);
    expect(find.text('both frames are identical'), findsNothing);
  });

  testWidgets('a step where nothing moved says so in words', (tester) async {
    await pump(tester, ComparedItem.of(id: 'Welcome'));

    expect(find.text('Nothing changed on any channel.'), findsOne);
  });
}

class _NoStore implements ShotStore {
  @override
  Future<Shot?> byKey(String key) async => null;

  @override
  Future<Shot?> byRef(FrameRef ref) async => null;
}
