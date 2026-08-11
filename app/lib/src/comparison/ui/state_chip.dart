import 'package:flutter/material.dart';

import '../../ui/theme.dart';
import '../channels.dart';

/// What a verdict looks like, in one place.
///
/// Colour is the fastest thing on the screen and the least precise: red means
/// three different things here — something broke, something was already broken,
/// something went away — so every chip carries its word too. A reader scanning
/// for red finds the rows worth looking at; a reader who needs to know which
/// red reads two more characters.
extension ComparedStateLook on ComparedState {
  Color colorIn(BuildContext context) {
    var colors = context.colors;
    return switch (this) {
      ComparedState.broke || ComparedState.failed => colors.red,
      ComparedState.wasBroken => colors.warningText,
      ComparedState.added => colors.grn,
      ComparedState.removed => colors.red,
      ComparedState.changed => colors.amber,
      ComparedState.same || ComparedState.skipped => colors.mut,
    };
  }

  /// How it reads in a row. `wasBroken` is the one that does not spell itself.
  String get word => switch (this) {
    ComparedState.broke => 'broke',
    ComparedState.failed => 'failed',
    ComparedState.wasBroken => 'was broken',
    ComparedState.added => 'added',
    ComparedState.removed => 'removed',
    ComparedState.changed => 'changed',
    ComparedState.same => 'same',
    ComparedState.skipped => 'skipped',
  };

  /// True for the states worth drawing attention to. [ComparedState.same] and
  /// [ComparedState.skipped] are the answer "nothing to see", and a list that
  /// shouts it is a list nobody reads to the end.
  bool get isFinding =>
      this != ComparedState.same && this != ComparedState.skipped;
}

/// A verdict, as a small filled label.
class StateChip extends StatelessWidget {
  const StateChip(this.state, {super.key, this.count});

  final ComparedState state;

  /// How many rows are in this state, when the chip is standing for a group.
  final int? count;

  @override
  Widget build(BuildContext context) {
    var color = state.colorIn(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: FwSpacing.sm,
        vertical: 1,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(context.radii.radiusSmall),
      ),
      child: Text(
        count == null ? state.word : '$count ${state.word}',
        style: context.type.micro.copyWith(color: color),
      ),
    );
  }
}
