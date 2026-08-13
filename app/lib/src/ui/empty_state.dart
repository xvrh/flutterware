import 'package:flutter/material.dart';
import 'design/design.dart';

/// The centred placeholder a list, table, or panel shows when it has nothing to
/// display: a muted icon, a [title], an optional [message] and an optional
/// [action]. The empty arm of the load → empty/error triad alongside
/// [LoadingState] and `ErrorPanel`.
///
/// Ported from `cms/packages/admin_ui/lib/src/common/ui/empty_state.dart`.
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;
  final double minHeight;

  const EmptyState({
    super.key,
    this.icon = Icons.inbox_outlined,
    required this.title,
    this.message,
    this.action,
    this.minHeight = 160,
  });

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: minHeight),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(FwSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: FwIconSize.xl, color: context.colors.mut3),
              const Gap(FwSpacing.md),
              Text(
                title,
                style: context.type.bodyStrong,
                textAlign: TextAlign.center,
              ),
              if (message != null) ...[
                const Gap(FwSpacing.xxs),
                Text(
                  message!,
                  style: context.type.bodyMuted,
                  textAlign: TextAlign.center,
                ),
              ],
              if (action != null) ...[const Gap(FwSpacing.lg), action!],
            ],
          ),
        ),
      ),
    );
  }
}
