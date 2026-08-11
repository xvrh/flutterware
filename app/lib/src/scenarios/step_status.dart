import 'package:flutter/material.dart';

import '../plugins/native/scenarios_results.dart';
import '../ui/theme.dart';

/// How a step names itself in the flow and on its page: what the `Shot` called
/// it, `step` for an automatic capture — and `failed` for the frame a scenario
/// broke on, which nothing named because nobody asked for it.
String scenarioStepLabel(ScenarioRunStep step) =>
    step.failure != null ? 'failed' : step.name ?? 'step';

/// The transition *into* a step, as a sentence: `tap "Pay"`, `screen`,
/// `pumpWidget MyApp`. Null on a run captured before the verb was recorded,
/// and on the step a scenario broke at — a failure is not a verb that
/// finished.
///
/// What it is for: an arrow in the flow graph and a tab full of events both
/// need to name the thing that happened between two pictures, and "step 3"
/// does not.
String? scenarioStepTransition(ScenarioRunStep step) {
  if (step.verb == null) return null;
  return step.target == null ? step.verb : '${step.verb} ${step.target}';
}

/// The colour a step's label wears: the error tone for a failure, the warn
/// tone for a screen that never stopped animating, and nothing special
/// otherwise.
Color scenarioStepTone(BuildContext context, ScenarioRunStep step) {
  var colors = context.colors;
  if (step.failure != null) return colors.red;
  if (!step.settled) return colors.amber;
  return colors.mut;
}

/// What a step says about itself above its picture — the error it broke on, or
/// the note that the app was still animating when the shutter fell. Nothing at
/// all in the healthy case, which is almost every step.
class ScenarioStepNotice extends StatelessWidget {
  const ScenarioStepNotice(this.step, {super.key});

  final ScenarioRunStep step;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    var (tone, icon, message) = switch (step) {
      ScenarioRunStep(failure: var failure?) => (
        colors.red,
        Icons.error_outline,
        failure,
      ),
      ScenarioRunStep(settled: false) => (
        colors.amber,
        Icons.motion_photos_on_outlined,
        'Still animating when this was captured — the settle budget ran out '
            'with frames still scheduled. A spinner or a looping animation '
            'does that; the picture is of a moving screen.',
      ),
      ScenarioRunStep(:var strayFrames) when strayFrames > 0 => (
        colors.mut2,
        Icons.timeline,
        '$strayFrames frame${strayFrames == 1 ? '' : 's'} were drawn before '
            'this step by something other than a scenario verb — the raw '
            '`tester`. Whatever the app showed in them is missing from this '
            'flow.',
      ),
      _ => (null, null, null),
    };
    if (tone == null) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(
        FwSpacing.lg,
        0,
        FwSpacing.lg,
        FwSpacing.md,
      ),
      padding: const EdgeInsets.all(FwSpacing.md),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(context.radii.radius),
        border: Border.all(color: tone.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: tone),
          const Gap(FwSpacing.sm),
          Expanded(
            child: SelectableText(
              message!,
              style: context.type.caption.copyWith(color: colors.ink),
            ),
          ),
        ],
      ),
    );
  }
}
