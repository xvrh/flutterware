import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:flutterware/plugins.dart';
import 'package:flutterware_app/src/plugins/native_plugin.dart';
import 'package:flutterware_app/src/shell/sidebar_row.dart';
import 'package:flutterware_app/src/ui/theme.dart';

import 'command_palette.dart' show wrapInAppTheme;

/// A package row in the shell's sidebar, in the states it is actually seen in.
///
/// The row it draws is `name · status · ⋮`, and the arrangement is the whole
/// point of having a demo for something this small: the name and the status sit
/// together on the left, and the ⋮ is pinned to the right edge so the dots form
/// a column down the sidebar whatever the statuses say. Both have been wrong —
/// the ⋮ used to follow the status text, and fixing that pushed the status into
/// the middle of the row.
///
/// Stacked rather than one state per entry: the alignment claims above are
/// about rows *relative to each other*, and a gallery that showed them one at a
/// time could not have caught either bug.
///
/// No Figma behind this — it is flutterware's own chrome, and the arrangement
/// was specified in review rather than drawn.
/// The sidebar's real width. These rows are as wide as they are, and a demo
/// that let them stretch to the window would not show the ellipsis that a long
/// package name actually hits.
const _sidebarWidth = 232.0;

/// Enough commands to open a menu with, for the states that have a ⋮.
List<PluginChildCommand> get _commands => [
  PluginChildCommand(
    label: 'Build a web page…',
    icon: Icons.language,
    onSelected: (_) {},
  ),
];

@Preview(name: 'Every state', group: 'Sidebar row', wrapper: wrapInAppTheme)
Widget sidebarRowStates() => const _Rail(
  children: [
    _Labelled(
      'idle',
      SidebarChildRow(
        label: 'app',
        status: Status.none,
        selected: false,
        onTap: _noop,
      ),
    ),
    _Labelled(
      'with a status',
      SidebarChildRow(
        label: 'examples/example',
        status: Status.info('building'),
        selected: false,
        onTap: _noop,
      ),
    ),
    _Labelled(
      'selected — the ⋮ stays without the pointer',
      _WithCommands(
        label: 'examples/example',
        status: Status.info('building'),
        selected: true,
      ),
    ),
    _Labelled(
      'every tone',
      Column(
        children: [
          SidebarChildRow(
            label: 'packages/core',
            status: Status.neutral('58 packages'),
            selected: false,
            onTap: _noop,
          ),
          SidebarChildRow(
            label: 'packages/ui',
            status: Status.warn('2 problems'),
            selected: false,
            onTap: _noop,
          ),
          SidebarChildRow(
            label: 'packages/legacy',
            status: Status.error('failed to scan'),
            selected: false,
            onTap: _noop,
          ),
        ],
      ),
    ),
    _Labelled(
      'the ⋮ lines up whatever the status says',
      Column(
        children: [
          _WithCommands(
            label: 'app',
            status: Status.info('building'),
            selected: true,
          ),
          _WithCommands(
            label: 'examples/example',
            status: Status.warn('10 assets · 347 kB · 2 problems'),
            selected: true,
          ),
          _WithCommands(label: 'tools', status: Status.none, selected: true),
        ],
      ),
    ),
    _Labelled(
      'a name too long for the rail keeps the status',
      _WithCommands(
        label: 'packages/design_system_foundations',
        status: Status.info('building'),
        selected: true,
      ),
    ),
  ],
);

/// A row that offers commands, so the ⋮ is drawn.
///
/// Separate because [PluginChildCommand] holds a callback and so cannot be
/// const, and the states above are otherwise all const.
class _WithCommands extends StatelessWidget {
  const _WithCommands({
    required this.label,
    required this.status,
    required this.selected,
  });

  final String label;
  final Status status;
  final bool selected;

  @override
  Widget build(BuildContext context) => SidebarChildRow(
    label: label,
    status: status,
    selected: selected,
    commands: _commands,
    onTap: _noop,
  );
}

void _noop() {}

/// The rail these rows live in, at the width they live at.
class _Rail extends StatelessWidget {
  const _Rail({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    return ColoredBox(
      color: colors.bg,
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: FwSpacing.xl),
        children: [
          for (var child in children)
            Align(
              alignment: Alignment.centerLeft,
              child: SizedBox(width: _sidebarWidth, child: child),
            ),
        ],
      ),
    );
  }
}

/// A caption above a state, so a screenshot of this entry says what each row is
/// meant to be showing.
class _Labelled extends StatelessWidget {
  const _Labelled(this.caption, this.child);

  final String caption;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: FwSpacing.xl),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            FwSpacing.lg,
            0,
            FwSpacing.lg,
            FwSpacing.xs,
          ),
          child: Text(
            caption,
            style: context.type.micro.copyWith(color: context.colors.mut3),
          ),
        ),
        child,
      ],
    ),
  );
}
