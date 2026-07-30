import 'package:flutter/material.dart';

import '../catalog/devices.dart';
import '../plugins/native/scenarios_results.dart';
import '../ui/tappable.dart';
import '../ui/theme.dart';
import 'framed_shot.dart';

/// One step, pushed over the flow: the frame big, its visible texts beside
/// it, previous/next to walk the run without going back — dev_studio's
/// detail page. The back arrow returns to the flow.
///
/// The widget tree dump joins the sidebar when the inspector slice lands.
class ScenarioStepPage extends StatelessWidget {
  const ScenarioStepPage({
    super.key,
    required this.steps,
    required this.step,
    required this.device,
    required this.onBack,
    required this.onOpenStep,
    this.statusFallback = Brightness.dark,
  });

  final List<ScenarioRunStep> steps;
  final ScenarioRunStep step;
  final CatalogDevice? device;
  final VoidCallback onBack;
  final void Function(ScenarioRunStep) onOpenStep;

  /// Status-chrome tint when the step declared no overlay style.
  final Brightness statusFallback;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    var position = steps.indexWhere((s) => s.index == step.index);
    var previous = position > 0 ? steps[position - 1] : null;
    var next = position >= 0 && position + 1 < steps.length
        ? steps[position + 1]
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: FwSpacing.lg,
            vertical: FwSpacing.md,
          ),
          child: Row(
            children: [
              Tappable(
                onTap: onBack,
                child: Icon(Icons.arrow_back, size: 18, color: colors.mut),
              ),
              const Gap(FwSpacing.lg),
              Expanded(
                child: Text(
                  '${step.index} · ${step.name ?? 'step'}',
                  style: context.type.heading,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Container(
                        color: colors.panel2,
                        padding: const EdgeInsets.all(FwSpacing.xl),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: FramedShot(
                            step: step,
                            device: device,
                            fallbackBrightness: statusFallback,
                          ),
                        ),
                      ),
                    ),
                    if (previous != null)
                      Positioned(
                        left: 0,
                        bottom: 0,
                        child: _StepLink(
                          previous,
                          isNext: false,
                          onTap: () => onOpenStep(previous),
                        ),
                      ),
                    if (next != null)
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: _StepLink(
                          next,
                          isNext: true,
                          onTap: () => onOpenStep(next),
                        ),
                      ),
                  ],
                ),
              ),
              const VerticalDivider(width: 1),
              SizedBox(
                width: 260,
                child: ListView(
                  padding: const EdgeInsets.all(FwSpacing.lg),
                  children: [
                    Text('VISIBLE TEXTS', style: context.type.sectionLabel),
                    const Gap(FwSpacing.md),
                    if (step.texts.isEmpty)
                      Text('No visible texts.', style: context.type.bodyMuted)
                    else
                      for (var text in step.texts)
                        Padding(
                          padding: const EdgeInsets.only(bottom: FwSpacing.xs),
                          child: SelectableText(
                            text,
                            style: context.type.bodySmall,
                          ),
                        ),
                    if (step.tags.isNotEmpty) ...[
                      const Gap(FwSpacing.lg),
                      Text('TAGS', style: context.type.sectionLabel),
                      const Gap(FwSpacing.md),
                      Text(step.tags.join(', '), style: context.type.bodySmall),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StepLink extends StatelessWidget {
  const _StepLink(this.step, {required this.isNext, required this.onTap});

  final ScenarioRunStep step;
  final bool isNext;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    return Tappable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: FwSpacing.md,
          vertical: FwSpacing.sm,
        ),
        color: colors.bg.withValues(alpha: 0.9),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!isNext)
              Icon(Icons.arrow_back_ios, size: 12, color: colors.mut),
            Text(
              '${step.index} · ${step.name ?? 'step'}',
              style: context.type.caption.copyWith(color: colors.mut),
            ),
            if (isNext)
              Icon(Icons.arrow_forward_ios, size: 12, color: colors.mut),
          ],
        ),
      ),
    );
  }
}
