import 'package:flutter/material.dart';

import 'design/design.dart';
import 'menu.dart';
import 'popover.dart';
import 'tappable.dart';
import 'theme.dart';

/// A primary action with its alternatives behind an attached chevron.
///
/// One bordered capsule, two segments: a click on the labelled part runs
/// [onPressed], the chevron opens a standard [Menu] of [entries] — the same
/// rows as every other dropdown in the app. For the bar whose one frequent
/// action deserves the room and whose variants do not: hot reload over hot
/// restart, copy over save-as.
///
/// A null [onPressed] disables the primary segment; the chevron follows the
/// entries and goes quiet only when none of them is selectable, so a menu of
/// alternatives can outlive a primary that is momentarily unavailable.
class FwSplitButton extends StatelessWidget {
  const FwSplitButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.entries = const [],
    this.tooltip,
    this.menuTooltip = 'More actions',
  });

  final String label;
  final IconData? icon;

  /// Awaited nowhere and guarded nowhere — like [MenuItem.onSelected], this is
  /// the caller's action. Null disables the primary segment.
  final VoidCallback? onPressed;

  /// The dropdown's rows. A [MenuItem] with a null `onSelected` renders
  /// disabled in place, so a variant that is momentarily unavailable stays
  /// visible rather than vanishing.
  final List<MenuEntry> entries;

  /// The primary segment's tooltip.
  final String? tooltip;

  /// The chevron's tooltip, since a bare `⌄` says nothing about what it holds.
  final String menuTooltip;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    var enabled = onPressed != null;
    var menuEnabled = entries.any(
      (entry) => entry is MenuItem && entry.onSelected != null,
    );

    Widget segment({
      required bool enabled,
      required VoidCallback? onTap,
      required Widget child,
    }) {
      return Tappable.builder(
        onTap: enabled ? onTap : null,
        builder: (context, hovered) => Container(
          padding: const EdgeInsets.symmetric(
            horizontal: FwSpacing.sm,
            vertical: 5,
          ),
          color: hovered && enabled ? colors.hoverOverlay : colors.bg,
          child: child,
        ),
      );
    }

    var primary = segment(
      enabled: enabled,
      onTap: onPressed,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: enabled ? colors.accent : colors.mut3),
            const Gap(FwSpacing.xs),
          ],
          Text(
            label,
            style: context.type.bodySmall.copyWith(
              color: enabled ? colors.accent : colors.mut3,
            ),
          ),
        ],
      ),
    );

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(context.radii.radiusSmall),
        border: Border.all(color: colors.line),
      ),
      child: IntrinsicHeight(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            tooltip == null
                ? primary
                : Tooltip(message: tooltip!, child: primary),
            VerticalDivider(width: 1, thickness: 1, color: colors.line),
            Menu(
              entries: entries,
              align: PopoverAlign.end,
              builder: (context, controller) => Tooltip(
                message: menuTooltip,
                child: segment(
                  enabled: menuEnabled,
                  onTap: controller.toggle,
                  child: Icon(
                    Icons.expand_more,
                    size: 14,
                    color: menuEnabled ? colors.accent : colors.mut3,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
