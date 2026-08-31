import 'package:flutterware/comparison_report.dart';
import 'package:flutter/material.dart';

import '../../ui/tappable.dart';
import '../../ui/theme.dart';
import 'channel_lines.dart';
import 'shot_image.dart';
import 'stage.dart';

/// The frames and the finding, for whichever half is asking.
///
/// **One copy, and that is the point.** The two halves each had their own —
/// `StepPage` for a scenario step, `_Detail` for a preview entry — laid out
/// identically and drifting independently. Teaching the page to lead with
/// whatever changed therefore fixed the scenarios half and left the previews
/// half exactly as it was, which is the failure mode a second copy exists to
/// produce. Design:
/// `docs/superpowers/specs/2026-08-31-comparison-detail-page-design.md`.
///
/// **The page leads with whatever changed.** When the pixels moved, that is
/// the pictures and this is the layout it has always had. When they did not,
/// two identical frames were taking 60% of the height and the finding was a
/// footnote — a `200 → 500` drawn smaller than the picture that did not
/// change.
class FindingBody extends StatelessWidget {
  const FindingBody({
    super.key,
    required this.item,
    required this.shots,
    required this.mode,
    required this.onMode,
    this.whenNotRendered,
  });

  final ComparedItem item;
  final ShotPair shots;
  final StageMode mode;
  final ValueChanged<StageMode> onMode;

  /// What to draw instead of frames for an entry nothing rendered — a skipped
  /// preview has no pictures and never will, and that is not a failed decode.
  final Widget? whenNotRendered;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    var hasChannels =
        (item.tree?.changed ?? false) ||
        item.texts != null ||
        item.events != null;
    var pixelsMoved = item.pixels?.changed ?? false;
    // One side missing is its own kind of finding, and the stage already draws
    // it well: the frame labelled `base only`, the mode pills disabled, the
    // note in red. Nothing about those states needs to move.
    var oneSided = shots.base == null || shots.head == null;

    if (!shots.settled) {
      return Expanded(
        child: Center(
          child: Text(
            'Loading…',
            style: context.type.body.copyWith(color: colors.mut),
          ),
        ),
      );
    }
    if (whenNotRendered case var instead? when !shots.hasFrames) {
      return Expanded(child: instead);
    }

    if (pixelsMoved || oneSided) {
      return Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: 5,
              child: ComparisonStage(
                shots: shots,
                mode: mode,
                onMode: onMode,
                diff: item.pixels?.diff,
              ),
            ),
            if (hasChannels) Expanded(flex: 2, child: ChannelLines(item)),
          ],
        ),
      );
    }

    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _IdenticalFrames(shots: shots, mode: mode, onMode: onMode),
          Divider(height: 1, color: colors.line),
          Expanded(
            child: hasChannels
                ? ChannelLines(item)
                : Center(
                    child: Text(
                      'Nothing changed on any channel.',
                      style: context.type.body.copyWith(color: colors.mut),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// The frames, when they are the same frame twice.
///
/// **One picture, not two.** *What does this look like* is a fair question
/// even when the answer is *the same as before*, and a reader who has just
/// arrived from a list needs to know where they are — but a second copy of it
/// answers nothing the word `identical` does not, and the two of them together
/// were taking the space the finding needed.
///
/// Expandable, because *identical* is a claim and somebody is eventually going
/// to want to check it. It expands in place rather than being lifted to the
/// page, so neither half has to carry a flag for it.
class _IdenticalFrames extends StatefulWidget {
  const _IdenticalFrames({
    required this.shots,
    required this.mode,
    required this.onMode,
  });

  final ShotPair shots;
  final StageMode mode;
  final ValueChanged<StageMode> onMode;

  @override
  State<_IdenticalFrames> createState() => _IdenticalFramesState();
}

const _thumbHeight = 96.0;

class _IdenticalFramesState extends State<_IdenticalFrames> {
  var _open = false;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    if (_open) {
      return SizedBox(
        height: 360,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ComparisonStage(
                shots: widget.shots,
                mode: widget.mode,
                onMode: widget.onMode,
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  FwSpacing.xl,
                  0,
                  FwSpacing.xl,
                  FwSpacing.sm,
                ),
                child: Tappable(
                  onTap: () => setState(() => _open = false),
                  child: Text(
                    'hide the frames',
                    style: context.type.caption.copyWith(
                      color: colors.accentDark,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        FwSpacing.xl,
        FwSpacing.md,
        FwSpacing.xl,
        FwSpacing.md,
      ),
      child: Row(
        children: [
          // Sized in both directions from the frame's own aspect. An
          // `AspectRatio` in a `Row` sizes from the width it is offered, which
          // here is the whole row — so the picture drew itself far larger than
          // its border and spilled out of it.
          if (widget.shots.head ?? widget.shots.base case var shot?)
            SizedBox(
              height: _thumbHeight,
              width: _thumbHeight * shot.aspect,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: colors.line),
                ),
                child: ClipRect(child: ShotView(shot)),
              ),
            ),
          const Gap(FwSpacing.lg),
          Expanded(
            child: Text(
              'both frames are identical',
              style: context.type.caption.copyWith(color: colors.mut),
            ),
          ),
          Tappable(
            onTap: () => setState(() => _open = true),
            child: Text(
              'compare anyway',
              style: context.type.caption.copyWith(color: colors.accentDark),
            ),
          ),
        ],
      ),
    );
  }
}
