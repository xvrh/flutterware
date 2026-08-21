import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
// ignore: implementation_imports
import 'package:flutterware/src/scenarios/aim.dart';
import 'package:flutterware_app/src/scenarios/aim_overlay.dart';
import 'package:flutterware_app/src/ui/theme.dart';

import 'app_theme.dart';

/// What a scenario's next link promises, drawn over the frame it acts on.
///
/// What this is for. The mark appears on hover, and a hover is the one
/// thing the drive loop cannot produce — the same reason `run_screen_picture`
/// exists — so in the running studio there is no way to *look* at this without
/// a hand on the mouse.
///
/// What there is to judge, and the reason for two widths: the step page draws
/// the phone at about a quarter of its logical size, so every stroke here is
/// divided by four before anybody sees it. Does the ring survive that? Does
/// the white halo keep it off a coloured button, or does it just fog the
/// picture? And the tap case is deliberately the awkward one — `tap('Flat
/// white')` resolves the *word*, so the box is the label inside a row four
/// times its height, and the question is whether the pair reads as "here" or
/// as "the wrong thing is boxed".
@Preview(name: 'Scenario aim', group: 'Scenarios', wrapper: wrapInAppTheme)
Widget scenarioAim() => const _Sheet();

@Preview(
  name: 'Scenario aim · dark',
  group: 'Scenarios',
  wrapper: wrapInDarkTheme,
)
Widget scenarioAimDark() => const _Sheet();

/// The three verbs v1 draws, at the size the step page draws them and at one
/// big enough to see what is actually being painted.
class _Sheet extends StatelessWidget {
  const _Sheet();

  /// The label inside the second row — what a text target resolves to, and
  /// four times smaller than the row that handles the tap.
  static const _label = ScenarioAim(x: 112, y: 318, width: 82, height: 22);

  @override
  Widget build(BuildContext context) => Container(
    color: context.colors.panel2,
    padding: const EdgeInsets.all(24),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var (verb, aim) in [
          ('tap', _label),
          ('longPress', _label),
          (
            'drag',
            const ScenarioAim(
              x: 112,
              y: 318,
              width: 82,
              height: 22,
              dx: 0,
              dy: -190,
            ),
          ),
        ]) ...[
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(verb, style: context.type.sectionLabel),
              const SizedBox(height: 8),
              // The big one to see what is painted, the small one because
              // that is the size it is actually seen at.
              _Phone(width: 260, verb: verb, aim: aim),
              const SizedBox(height: 12),
              _Phone(width: 110, verb: verb, aim: aim),
            ],
          ),
          const SizedBox(width: 24),
        ],
      ],
    ),
  );
}

/// The picture and the mark in the guest's own logical box, scaled down as one
/// — which is exactly what the step page's `FittedBox` does to `FramedShot`,
/// and the only arrangement in which the overlay needs no transform.
class _Phone extends StatelessWidget {
  const _Phone({required this.width, required this.verb, required this.aim});

  final double width;
  final String verb;
  final ScenarioAim aim;

  /// How much of the phone is shown — the band the mark is in. Cropped rather
  /// than shrunk, because the whole question is how the mark reads at the
  /// scale the step page draws it, and a scale chosen to fit this page on a
  /// screen would answer a different one.
  static const _band = 470.0;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    height: width * _band / 390,
    child: FittedBox(
      child: ClipRect(
        child: SizedBox(
          width: 390,
          height: _band,
          child: OverflowBox(
            alignment: Alignment.topLeft,
            maxHeight: 844,
            child: SizedBox(
              width: 390,
              height: 844,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  RawImage(image: _menu(), fit: BoxFit.fill),
                  ScenarioAimOverlay(aim: aim, verb: verb),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// A drink menu: a bar, four rows, each an icon square and two lines of text.
///
/// Drawn rather than loaded, for the reason `run_screen_picture` gives: no
/// asset, no decode, and `toImageSync` puts it in the first frame. Scaled
/// before anything is drawn, for the reason it gives too.
ui.Image _menu() {
  const width = 390.0;
  const height = 844.0;
  var recorder = ui.PictureRecorder();
  var canvas = Canvas(recorder)
    ..scale(2)
    ..drawRect(
      const Rect.fromLTWH(0, 0, width, height),
      Paint()..color = const Color(0xFFFDF7F2),
    )
    ..drawRect(
      const Rect.fromLTWH(0, 0, width, 120),
      Paint()..color = const Color(0xFF7C3A16),
    );
  for (var i = 0; i < 4; i++) {
    var top = 160.0 + i * 140;
    canvas
      ..drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(24, top, 342, 84),
          const Radius.circular(14),
        ),
        Paint()..color = Colors.white,
      )
      ..drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(40, top + 14, 56, 56),
          const Radius.circular(12),
        ),
        // The third row is the tapped one, and it is the accent-ish colour on
        // purpose: a mark that only reads on white is a mark that does not.
        Paint()
          ..color = i == 1 ? const Color(0xFF2563EB) : const Color(0xFFEADFD4),
      )
      // The label, and the line under it.
      ..drawRect(
        Rect.fromLTWH(112, top + 18, 82, 22),
        Paint()..color = const Color(0xFF44322A),
      )
      ..drawRect(
        Rect.fromLTWH(112, top + 50, 180, 12),
        Paint()..color = const Color(0xFFC9BAB0),
      );
  }
  return recorder.endRecording().toImageSync(
    (width * 2).round(),
    (height * 2).round(),
  );
}
