import 'package:flutter/material.dart';
import 'package:flutterware/plugins.dart';

import '../plugins/native_plugin.dart';
import '../ui/menu.dart';
import '../ui/popover.dart';
import '../ui/tappable.dart';
import '../ui/theme.dart';

/// How much of the rail a status may claim before it ellipsises.
///
/// A constant rather than a fraction: the sidebar is a fixed 232 wide, and this
/// leaves a readable name beside the longest status any plugin writes today —
/// the asset inspector's "10 assets · 347 kB · 2 problems".
const _statusMaxWidth = 100.0;

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

    return _Hoverable(
      onTap: onTap,
      builder: (context, hovered) => Container(
        // The rail is always drawn — only its colour changes — so the row keeps
        // its geometry and nothing below it moves on selection.
        margin: const EdgeInsets.only(left: FwSpacing.xxl),
        decoration: BoxDecoration(
          color: hovered && !selected
              ? colors.hoverOverlay
              : Colors.transparent,
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
        child: Row(
          children: [
            // The row reads left to right — name, status — and the ⋮ sits at
            // the far edge. Two things are needed for that, and they are easy
            // to confuse:
            //
            // The **Expanded** takes all the slack, so the ⋮ after it is pinned
            // to the right rather than trailing whatever the status ended at.
            // The **loose Flexibles inside it** each take only their own width,
            // so the status sits against the name instead of being pushed to
            // the middle by a label that had filled half the row.
            Expanded(
              child: Row(
                children: [
                  // The name yields and the status does not, which is the way
                  // round it has to be. A flexible child is *clamped* to its
                  // share of the row whether or not the other one wanted it, so
                  // a flexible status was truncated to "buildi…" beside a
                  // three-letter package name with the rest of the row empty.
                  // Non-flexible, it takes its own width and the name takes
                  // what is left.
                  Flexible(
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
                      constraints: const BoxConstraints(
                        maxWidth: _statusMaxWidth,
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
            if (commands.isNotEmpty) ...[
              // Clear of the status. At 14px the glyph is mostly whitespace, so
              // set flush against a word it reads as punctuation on the end of
              // it rather than as a control of its own.
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

/// Hover tracking for a whole row, handed to the builder.
class _Hoverable extends StatefulWidget {
  const _Hoverable({required this.onTap, required this.builder});

  final VoidCallback onTap;
  final Widget Function(BuildContext context, bool hovered) builder;

  @override
  State<_Hoverable> createState() => _HoverableState();
}

class _HoverableState extends State<_Hoverable> {
  var _hovered = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.click,
    onEnter: (_) => setState(() => _hovered = true),
    onExit: (_) => setState(() => _hovered = false),
    child: GestureDetector(
      onTap: widget.onTap,
      child: widget.builder(context, _hovered),
    ),
  );
}
