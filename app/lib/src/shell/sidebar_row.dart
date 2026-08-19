import 'package:flutter/material.dart';
import 'package:flutterware/plugins.dart';

import '../plugins/native_plugin.dart';
import '../ui/menu.dart';
import '../ui/popover.dart';
import '../ui/tappable.dart';
import '../ui/theme.dart';

/// How much of the rail a status may claim before it ellipsises.
///
/// At the default width a constant: the sidebar is 232 wide, and this leaves a
/// readable name beside the longest status any plugin writes today — the asset
/// inspector's "10 assets · 347 kB · 2 problems". On a rail dragged narrower
/// it tightens; see [_statusCap].
const _statusMaxWidth = 100.0;

/// What the status may actually take in a row [available] wide, of which
/// [reserved] is already spoken for by the row's other fixtures.
///
/// The status is deliberately not a flex child — an allotment parks it at
/// whatever fraction of the row the flex math lands on, which is the floating
/// misalignment this file exists to prevent. The price of laying it out at its
/// own width is that nothing shrinks it when the rail is dragged near its
/// minimum, so this cap does: at most the constant, at most 60% of the row so
/// a word of the name survives beside a long status, and never past what the
/// fixtures leave — the bound that keeps the row from overflowing outright.
double _statusCap(double available, double reserved) {
  var cap = available - reserved;
  if (cap > available * 0.6) cap = available * 0.6;
  if (cap > _statusMaxWidth) cap = _statusMaxWidth;
  return cap < 0 ? 0 : cap;
}

/// The one row shape the sidebar's top level uses — Overview, Changes, and a
/// row per plugin. A filled selection, no border, so selecting never changes
/// anyone's size.
///
/// The status is pinned to the row's right edge, so down the rail the statuses
/// form a column whatever the labels say. It takes its own width up to
/// [_statusMaxWidth] and the label yields — a status floating at whatever
/// point the label's flex share happened to end was the arrangement this
/// replaced, and it read as misalignment rather than as a decision.
class SidebarRow extends StatelessWidget {
  const SidebarRow({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.status = Status.none,
    this.actions = const [],
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;
  final Status status;

  /// Shown on hover, between the label and the status — a plugin's own
  /// openings. See [PluginRowCommand].
  final List<({String label, IconData icon, VoidCallback onTap})> actions;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    return Tappable.builder(
      onTap: onTap,
      // The wash is the primitive's; the flag still reveals the row's actions.
      feedback: TapFeedback.overlay,
      builder: (context, hovered) => Container(
        margin: const EdgeInsets.symmetric(
          horizontal: FwSpacing.md,
          vertical: 1,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: FwSpacing.lg,
          vertical: FwSpacing.md,
        ),
        decoration: BoxDecoration(
          color: selected ? colors.accentSoft : Colors.transparent,
          borderRadius: BorderRadius.circular(context.radii.radiusSmall),
        ),
        child: LayoutBuilder(
          builder: (context, box) => Row(
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  size: FwIconSize.sm,
                  color: selected ? colors.accent : colors.mut,
                ),
                const Gap(FwSpacing.md),
              ],
              // The label takes the slack and yields, which is what pins
              // everything after it to the right edge.
              Expanded(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: selected
                      ? context.type.bodyStrong.copyWith(color: colors.accent)
                      : context.type.body,
                ),
              ),
              // Only on hover, and only then: a row that always carried its
              // buttons would put a `+` beside every plugin that has one,
              // which is a rail of controls rather than a list of places.
              if (hovered)
                for (var action in actions)
                  Tooltip(
                    message: action.label,
                    child: Tappable.builder(
                      onTap: action.onTap,
                      builder: (context, over) => Padding(
                        padding: const EdgeInsets.only(left: FwSpacing.xs),
                        child: Icon(
                          action.icon,
                          size: FwIconSize.md,
                          color: over ? colors.accent : colors.mut,
                        ),
                      ),
                    ),
                  ),
              if (!status.isEmpty) ...[
                const Gap(FwSpacing.sm),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: _statusCap(
                      box.maxWidth,
                      (icon != null ? FwIconSize.sm + FwSpacing.md : 0) +
                          FwSpacing.sm,
                    ),
                  ),
                  child: Text(
                    status.message,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.type.micro.copyWith(
                      color: toneColor(colors, status.tone),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// One package of a plugin, hung off a rail rather than boxed. Selecting it is
/// what raises that package's work.
///
/// Takes what it draws, not the controller that knows it: the shell reads
/// selection and hands over commands, so this can be put in the catalog and
/// looked at in every state without a session behind it. See
/// `tool/catalog/demos/sidebar_row.dart`.
class SidebarChildRow extends StatelessWidget {
  const SidebarChildRow({
    super.key,
    required this.label,
    required this.status,
    required this.selected,
    required this.onTap,
    this.commands = const [],
  });

  final String label;
  final Status status;
  final bool selected;
  final VoidCallback onTap;

  /// What the ⋮ offers. Empty draws no ⋮ at all.
  final List<PluginChildCommand> commands;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;

    return Tappable.builder(
      onTap: onTap,
      // The wash is the primitive's; the rail is this row's own, which is why
      // the flag is still read here.
      feedback: TapFeedback.overlay,
      builder: (context, hovered) => Container(
        // The rail is always drawn — only its colour changes — so the row keeps
        // its geometry and nothing below it moves on selection.
        margin: const EdgeInsets.only(left: FwSpacing.xxl),
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(
              color: selected
                  ? colors.accent
                  : hovered
                  ? colors.mut3
                  : colors.line,
              width: 2,
            ),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(
          FwSpacing.lg,
          FwSpacing.sm,
          FwSpacing.xl,
          FwSpacing.sm,
        ),
        child: LayoutBuilder(
          builder: (context, box) => Row(
            children: [
              // The name yields and takes the slack, which is what pins the
              // status to the right — the same column the plugin rows above
              // keep, so the rail reads as one aligned list rather than two
              // conventions. The ⋮ sits past it at the far edge either way.
              Expanded(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: context.type.bodySmall.copyWith(
                    color: selected ? colors.ink : colors.mut,
                  ),
                ),
              ),
              if (!status.isEmpty) ...[
                const Gap(FwSpacing.sm),
                // Capped, because "does not yield" cannot mean "takes the
                // whole row": a row reading "10 assets · 347 kB · 2
                // problems" and not *which package* is worse than one that
                // says neither. Past this it ellipsises and the name keeps
                // the rest.
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: _statusCap(
                      box.maxWidth,
                      FwSpacing.sm +
                          (commands.isNotEmpty ? 18 + FwSpacing.sm : 0),
                    ),
                  ),
                  child: Text(
                    status.message,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.type.micro.copyWith(
                      color: toneColor(colors, status.tone),
                    ),
                  ),
                ),
              ],
              if (commands.isNotEmpty) ...[
                // Clear of the status. At 14px the glyph is mostly whitespace,
                // so set flush against a word it reads as punctuation on the
                // end of it rather than as a control of its own.
                const Gap(FwSpacing.sm),
                // Only under the pointer, and holding its box either way: a ⋮ on
                // every row is a column of dots down the sidebar, and a ⋮ that
                // appears by *widening* the row shifts the status you were
                // reading on the way to it.
                //
                // Square and explicit, so the tap target is the box rather than
                // the glyph — `Tappable` is opaque and adds no padding of its
                // own, which leaves 14px of dots to hit otherwise.
                SizedBox(
                  width: 18,
                  height: 18,
                  child: hovered || selected
                      ? _ChildCommandsButton(commands)
                      : null,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The ⋮ on a sidebar child row.
class _ChildCommandsButton extends StatelessWidget {
  const _ChildCommandsButton(this.commands);

  final List<PluginChildCommand> commands;

  @override
  Widget build(BuildContext context) {
    return Menu(
      side: PopoverSide.bottom,
      align: PopoverAlign.end,
      entries: [
        for (var command in commands)
          MenuItem(
            command.label,
            icon: command.icon,
            danger: command.danger,
            // Captured from the *row*, not from the menu: the popover is gone
            // by the time this runs, and a dialog pushed onto a dead context
            // throws.
            onSelected: () => command.onSelected(context),
          ),
      ],
      builder: (context, controller) => Tappable(
        onTap: controller.toggle,
        child: Center(
          child: Icon(
            Icons.more_vert,
            size: FwIconSize.sm,
            color: context.colors.mut,
          ),
        ),
      ),
    );
  }
}
