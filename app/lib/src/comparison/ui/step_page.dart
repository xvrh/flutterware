import 'package:flutterware/comparison_report.dart';
import 'package:flutter/material.dart';

import '../../ui/tappable.dart';
import '../../ui/theme.dart';
import 'channel_lines.dart';
import 'shot_image.dart';
import 'stage.dart';
import 'state_chip.dart';

const stepPageKey = Key('comparison.step-page');
const stepBackKey = Key('comparison.step-back');

/// One step of a flow, pushed over the tree.
///
/// Its own file so it can be a preview entry: the seven shapes of finding it
/// has to render — pixels, tree only, texts only, events only, unchanged,
/// broken, one-sided — are seven different screens, and until they were drawn
/// side by side only the first had ever been looked at. See
/// `docs/superpowers/specs/2026-08-31-comparison-detail-page-design.md`.
class StepPage extends StatelessWidget {
  const StepPage({
    super.key,
    required this.item,
    required this.shots,
    required this.mode,
    required this.onMode,
    required this.onBack,
  });

  final ComparedItem item;
  final ShotPair shots;
  final StageMode mode;
  final ValueChanged<StageMode> onMode;
  final VoidCallback onBack;

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

    return Column(
      key: stepPageKey,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            FwSpacing.lg,
            FwSpacing.md,
            FwSpacing.xl,
            0,
          ),
          child: Row(
            children: [
              Tappable(
                key: stepBackKey,
                onTap: onBack,
                child: Icon(
                  Icons.arrow_back,
                  size: FwIconSize.lg,
                  color: colors.mut,
                ),
              ),
              const Gap(FwSpacing.lg),
              Expanded(child: Text(item.id, style: context.type.heading)),
              StateChip(item.state),
            ],
          ),
        ),
        if (item.note case var note?)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              FwSpacing.xl,
              FwSpacing.xs,
              FwSpacing.xl,
              0,
            ),
            child: Text(
              note,
              style: context.type.caption.copyWith(color: colors.red),
            ),
          ),
        // **The page leads with whatever changed.** When the pixels moved,
        // that is the pictures and this is the layout it has always had. When
        // they did not, two identical frames were taking 60% of the height
        // and the finding was a footnote — a `200 → 500` drawn smaller than
        // the picture that did not change. Design:
        // `docs/superpowers/specs/2026-08-31-comparison-detail-page-design.md`.
        if (!shots.settled)
          Expanded(
            child: Center(
              child: Text(
                'Loading…',
                style: context.type.body.copyWith(color: colors.mut),
              ),
            ),
          )
        else if (pixelsMoved || oneSided) ...[
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
        ] else ...[
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
      ],
    );
  }
}

/// The frames, when they are the same frame twice.
///
/// **One picture, not two.** *What does this step look like* is a fair
/// question even when the answer is *the same as before*, and a reader who has
/// just arrived from a list needs to know where they are — but a second copy
/// of it answers nothing the word `identical` does not, and the two of them
/// together were taking the space the finding needed.
///
/// Expandable, because *identical* is a claim and somebody is eventually going
/// to want to check it. It expands in place rather than being lifted to the
/// page, so neither tab has to carry a flag for it.
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
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Sized in both directions from the frame's own aspect. An
          // `AspectRatio` in a `Row` sizes from the width it is offered,
          // which here is the whole row — so the picture drew itself far
          // larger than its border and spilled out of it.
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
