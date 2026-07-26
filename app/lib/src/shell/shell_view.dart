import 'package:flutter/material.dart';
import 'package:flutterware/plugins.dart';

import '../plugins/native_plugin.dart';
import '../ui/theme.dart';
import '../utils/router_outlet.dart';
import 'shell_controller.dart';
import 'worktree.dart';

/// Width the macOS traffic lights occupy; band content insets past them.
const _trafficLightInset = 78.0;
const _bandHeight = 40.0;
const _sidebarWidth = 232.0;

/// Maps a plugin [Tone] to a palette colour. The single place tones become
/// pixels — everywhere else they stay data.
Color toneColor(FwPalette colors, Tone tone) => switch (tone) {
  Tone.neutral => colors.mut2,
  Tone.good => colors.grn,
  Tone.info => colors.info,
  Tone.warn => colors.amber,
  Tone.error => colors.red,
};

class ShellApp extends StatelessWidget {
  const ShellApp(this.shell, {super.key});

  final ShellController shell;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutterware',
      theme: appTheme,
      debugShowCheckedModeBanner: false,
      home: RouterOutlet.root(child: ShellView(shell)),
    );
  }
}

class ShellView extends StatelessWidget {
  const ShellView(this.shell, {super.key});

  final ShellController shell;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: shell,
      builder: (context, _) => Scaffold(
        body: Column(
          children: [
            _Band(shell),
            Expanded(
              child: Row(
                children: [
                  _Sidebar(shell),
                  Expanded(child: _Panel(shell)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The reclaimed titlebar: a tab per open worktree, then the switcher.
class _Band extends StatelessWidget {
  const _Band(this.shell);

  final ShellController shell;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    return Container(
      height: _bandHeight,
      decoration: BoxDecoration(
        color: colors.panel,
        border: Border(bottom: BorderSide(color: colors.line)),
      ),
      padding: const EdgeInsets.only(left: _trafficLightInset),
      child: Row(
        children: [
          Expanded(
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (var worktree in shell.openWorktrees)
                  _WorktreeTab(shell, worktree),
                _SwitcherButton(shell),
              ],
            ),
          ),
          if (shell.isBusy)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: FwSpacing.md),
              child: SizedBox.square(
                dimension: 13,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          Tooltip(
            message: 'Rescan worktrees',
            child: IconButton(
              onPressed: shell.refresh,
              icon: Icon(Icons.refresh, size: 16, color: colors.mut),
              constraints: const BoxConstraints.tightFor(width: 28, height: 28),
              padding: EdgeInsets.zero,
            ),
          ),
          const Gap(FwSpacing.md),
        ],
      ),
    );
  }
}

class _WorktreeTab extends StatelessWidget {
  const _WorktreeTab(this.shell, this.worktree);

  final ShellController shell;
  final Worktree worktree;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    var selected = shell.selected == worktree;
    var status = shell.sessionFor(worktree)?.status ?? Status.none;
    var radius = Radius.circular(context.radii.radiusSmall);

    return GestureDetector(
      onTap: () => shell.select(worktree),
      child: Container(
        height: _bandHeight - 6,
        margin: const EdgeInsets.only(top: 6, right: FwSpacing.xs),
        padding: const EdgeInsets.only(left: FwSpacing.lg, right: FwSpacing.sm),
        decoration: BoxDecoration(
          color: selected ? colors.bg : Colors.transparent,
          borderRadius: BorderRadius.only(topLeft: radius, topRight: radius),
          border: selected
              ? Border(
                  top: BorderSide(color: colors.line),
                  left: BorderSide(color: colors.line),
                  right: BorderSide(color: colors.line),
                )
              : null,
        ),
        child: Row(
          children: [
            if (!status.isEmpty && status.tone != Tone.neutral) ...[
              _Dot(toneColor(colors, status.tone)),
              const Gap(FwSpacing.sm),
            ],
            Text(
              worktree.displayName,
              style: selected
                  ? context.type.bodyStrong
                  : context.type.bodyMuted,
            ),
            const Gap(FwSpacing.sm),
            _CloseButton(shell, worktree),
          ],
        ),
      ),
    );
  }
}

/// Closing releases the worktree's plugins. A plugin that hard-blocks teardown
/// refuses, and the reasons are shown rather than the click doing nothing.
class _CloseButton extends StatelessWidget {
  const _CloseButton(this.shell, this.worktree);

  final ShellController shell;
  final Worktree worktree;

  @override
  Widget build(BuildContext context) {
    var session = shell.sessionFor(worktree);
    var blockers = [
      for (var guard in session?.guards ?? const <Guard>[])
        if (guard.level == GuardLevel.block) guard.reason,
    ];

    return Tooltip(
      message: blockers.isEmpty ? 'Close worktree' : blockers.join('\n'),
      child: GestureDetector(
        onTap: () {
          if (!shell.close(worktree)) _showBlocked(context, blockers);
        },
        child: Icon(
          blockers.isEmpty ? Icons.close : Icons.lock_outline,
          size: 13,
          color: blockers.isEmpty ? context.colors.mut2 : context.colors.amber,
        ),
      ),
    );
  }

  void _showBlocked(BuildContext context, List<String> reasons) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cannot close this worktree'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [for (var reason in reasons) Text('• $reason')],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}

/// Lists every worktree git reports, split by whether it is open.
class _SwitcherButton extends StatefulWidget {
  const _SwitcherButton(this.shell);

  final ShellController shell;

  @override
  State<_SwitcherButton> createState() => _SwitcherButtonState();
}

class _SwitcherButtonState extends State<_SwitcherButton> {
  final _menuController = MenuController();

  ShellController get shell => widget.shell;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    return Center(
      child: MenuAnchor(
        controller: _menuController,
        alignmentOffset: const Offset(0, 4),
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(colors.bg),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(vertical: FwSpacing.md),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(context.radii.radius),
              side: BorderSide(color: colors.line),
            ),
          ),
        ),
        menuChildren: [_SwitcherMenu(shell, _menuController)],
        builder: (context, controller, child) => Tooltip(
          message: 'Open a worktree',
          child: IconButton(
            onPressed: () =>
                controller.isOpen ? controller.close() : controller.open(),
            icon: Icon(Icons.add, size: 16, color: colors.mut),
            constraints: const BoxConstraints.tightFor(width: 28, height: 28),
            padding: EdgeInsets.zero,
          ),
        ),
      ),
    );
  }
}

class _SwitcherMenu extends StatelessWidget {
  const _SwitcherMenu(this.shell, this.menu);

  final ShellController shell;
  final MenuController menu;

  @override
  Widget build(BuildContext context) {
    var open = shell.openWorktrees;
    var closed = shell.closedWorktrees;
    return SizedBox(
      width: 360,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (open.isNotEmpty) ...[
            _MenuHeading('OPEN · ${open.length}'),
            for (var worktree in open) _SwitcherRow(shell, worktree, menu),
          ],
          if (closed.isNotEmpty) ...[
            const Gap(FwSpacing.md),
            _MenuHeading('NOT OPEN · ${closed.length}'),
            for (var worktree in closed) _SwitcherRow(shell, worktree, menu),
          ],
        ],
      ),
    );
  }
}

class _MenuHeading extends StatelessWidget {
  const _MenuHeading(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(
      horizontal: FwSpacing.xl,
      vertical: FwSpacing.sm,
    ),
    child: Text(label, style: context.type.micro),
  );
}

class _SwitcherRow extends StatelessWidget {
  const _SwitcherRow(this.shell, this.worktree, this.menu);

  final ShellController shell;
  final Worktree worktree;
  final MenuController menu;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    var isOpen = shell.isOpen(worktree);
    var status = shell.sessionFor(worktree)?.status ?? Status.none;

    return InkWell(
      onTap: () {
        // A MenuAnchor menu lives in an overlay, not on the Navigator — popping
        // the route here would unmount the whole shell.
        menu.close();
        isOpen ? shell.select(worktree) : shell.open(worktree);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: FwSpacing.xl,
          vertical: FwSpacing.md,
        ),
        child: Row(
          children: [
            SizedBox(
              width: 14,
              child: status.isEmpty || status.tone == Tone.neutral
                  ? null
                  : _Dot(toneColor(colors, status.tone)),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    worktree.displayName,
                    style: isOpen ? context.type.bodyStrong : context.type.body,
                  ),
                  // Only when it adds something: with no contributed title,
                  // displayName *is* the branch, and showing it twice is noise.
                  if (worktree.title != null && worktree.branch != null)
                    Text(worktree.branch!, style: context.type.caption),
                ],
              ),
            ),
            // Worktrees that are not open hold no session, so there is nothing
            // to report about them yet — see open question 4.
            Text(
              isOpen ? status.message : 'Open',
              style: context.type.micro.copyWith(
                color: isOpen ? toneColor(colors, status.tone) : colors.accent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One row per plugin, with the status its report carries.
class _Sidebar extends StatelessWidget {
  const _Sidebar(this.shell);

  final ShellController shell;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    var session = shell.selectedSession;
    return Container(
      width: _sidebarWidth,
      decoration: BoxDecoration(
        color: colors.panel,
        border: Border(right: BorderSide(color: colors.line)),
      ),
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: FwSpacing.lg),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              FwSpacing.xl,
              0,
              FwSpacing.xl,
              FwSpacing.md,
            ),
            child: Text('PLUGINS', style: context.type.micro),
          ),
          if (session == null || session.plugins.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: FwSpacing.xl),
              child: Text(
                'No plugins declared.\nAdd them in tool/flutterware.dart.',
                style: context.type.caption,
              ),
            )
          else
            for (var plugin in session.plugins) ...[
              _PluginRow(shell, plugin),
              // Expanded only for the selected plugin: a sidebar showing every
              // package of every plugin at once is a wall, not a summary.
              if (shell.selectedPluginId == plugin.id)
                for (var child in plugin.report.children)
                  _ChildRow(shell, plugin.id, child),
            ],
        ],
      ),
    );
  }
}

class _PluginRow extends StatelessWidget {
  const _PluginRow(this.shell, this.plugin);

  final ShellController shell;
  final NativePlugin plugin;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    var report = plugin.report;
    var selected = shell.selectedPluginId == plugin.id;

    return GestureDetector(
      onTap: () => shell.selectPlugin(plugin.id),
      child: Container(
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
        child: Row(
          children: [
            Expanded(
              child: Text(
                report.label,
                style: selected
                    ? context.type.bodyStrong.copyWith(color: colors.accent)
                    : context.type.body,
              ),
            ),
            if (!report.status.isEmpty)
              Text(
                report.status.message,
                style: context.type.micro.copyWith(
                  color: toneColor(colors, report.status.tone),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// One package of a plugin, indented under it. Selecting it is what raises
/// that package's work.
class _ChildRow extends StatelessWidget {
  const _ChildRow(this.shell, this.pluginId, this.child);

  final ShellController shell;
  final String pluginId;
  final PluginChild child;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    var selected =
        shell.selectedPluginId == pluginId && shell.selectedChildId == child.id;

    return GestureDetector(
      onTap: () => shell.selectChild(pluginId, child.id),
      child: Container(
        margin: const EdgeInsets.only(
          left: FwSpacing.xxl,
          right: FwSpacing.md,
          top: 1,
          bottom: 1,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: FwSpacing.lg,
          vertical: FwSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: selected ? colors.bg : Colors.transparent,
          borderRadius: BorderRadius.circular(context.radii.radiusSmall),
          border: selected ? Border.all(color: colors.line) : null,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                child.label,
                style: selected
                    ? context.type.bodySmall.copyWith(color: colors.ink)
                    : context.type.bodySmall.copyWith(color: colors.mut),
              ),
            ),
            if (!child.status.isEmpty)
              Text(
                child.status.message,
                style: context.type.micro.copyWith(
                  color: toneColor(colors, child.status.tone),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Mounts the selected plugin's panel — the one place a native plugin is
/// unrestricted Flutter.
class _Panel extends StatelessWidget {
  const _Panel(this.shell);

  final ShellController shell;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    var session = shell.selectedSession;
    var error = session == null ? null : shell.errorFor(session.worktree);

    Widget body;
    if (error != null) {
      body = _Message(
        title: 'This worktree’s config could not be read',
        detail: error.message,
        tone: Tone.error,
      );
    } else if (session == null) {
      body = const _Message(title: 'No worktree open');
    } else {
      var plugin = shell.selectedPluginId == null
          ? null
          : session.pluginById(shell.selectedPluginId!);
      body = plugin == null
          ? const _Message(title: 'No plugin selected')
          : KeyedSubtree(
              // Rebuild the panel from scratch when the worktree or the plugin
              // changes; panels hold their own state and must not leak it
              // across worktrees. The child id is *not* in the key — switching
              // packages should update the panel, not remount it, or the
              // subscription would be torn down and rebuilt needlessly.
              key: ValueKey('${session.worktree.path}::${plugin.id}'),
              child: plugin.buildPanel(context, shell.selectedChildId),
            );
    }

    return Container(color: colors.bg, child: body);
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.title, this.detail, this.tone = Tone.neutral});

  final String title;
  final String? detail;
  final Tone tone;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(FwSpacing.xxxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: context.type.heading.copyWith(
                color: toneColor(colors, tone),
              ),
            ),
            if (detail != null) ...[
              const Gap(FwSpacing.md),
              SelectableText(
                detail!,
                style: context.type.caption,
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot(this.color);

  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 7,
    height: 7,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}
