import 'package:flutterware/comparison_report.dart';
import 'package:flutter/material.dart';

import '../../ui/tappable.dart';
import '../../ui/theme.dart';
import '../rules.dart';
import 'finding_body.dart';
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
    this.onRule,
  });

  final ComparedItem item;
  final ShotPair shots;
  final StageMode mode;
  final ValueChanged<StageMode> onMode;
  final VoidCallback onBack;

  /// See [ChannelLines.onRule].
  final ValueChanged<ComparisonRule>? onRule;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;

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
        FindingBody(
          item: item,
          shots: shots,
          mode: mode,
          onMode: onMode,
          onRule: onRule,
        ),
      ],
    );
  }
}
