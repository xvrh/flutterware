import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutterware/plugins.dart';

import '../plugins/native_plugin.dart';
import '../ui/theme.dart';
import '../utils/router_outlet.dart';
import 'shell_controller.dart';
import 'worktree.dart';
import 'worktree_home.dart';

/// Width the macOS traffic lights occupy; band content insets past them.
const _trafficLightInset = 78.0;
const _bandHeight = 40.0;

/// How far tabs sit below the top of the band. Everything else in the band
/// aligns to the box this leaves, not to the band itself.
const _tabInset = 6.0;

/// How much of a tab a worktree's name may claim before it is ellipsised.
const _tabLabelMaxWidth = 180.0;
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
      // Follows the OS. The shell reads every colour through `context.colors`,
      // so both builds come from the same widgets — but a plugin panel that
      // still hardcodes its own will stay light, and look it.
      darkTheme: appDarkTheme,
      themeMode: ThemeMode.system,
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
      builder: (context, _) => CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyB, meta: true):
              shell.toggleSidebar,
          const SingleActivator(LogicalKeyboardKey.keyB, control: true):
              shell.toggleSidebar,
        },
        child: Scaffold(
          body: Column(
            children: [
              _Band(shell),
              Expanded(
                child: Row(
                  children: [
                    if (shell.sidebarVisible) _Sidebar(shell),
                    Expanded(child: _Panel(shell)),
                  ],
                ),
              ),
            ],
          ),
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
          // Where a desktop app puts it: in the chrome, always in the same
          // place, so the rail can go to nothing at all rather than leaving a
          // strip behind — a panel that hides its own list would otherwise
          // leave two empty strips side by side.
          _SidebarButton(shell),
          const Gap(FwSpacing.xs),
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
          _ReloadButton(shell),
          const Gap(FwSpacing.md),
        ],
      ),
    );
  }
}

/// Shows and hides the plugin rail.
class _SidebarButton extends StatelessWidget {
  const _SidebarButton(this.shell);

  final ShellController shell;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(
        shell.sidebarVisible ? Icons.chevron_left : Icons.chevron_right,
        size: 16,
        color: context.colors.mut,
      ),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 24, height: 24),
      tooltip:
          '${shell.sidebarVisible ? 'Hide' : 'Show'} the sidebar '
          '(${Platform.isMacOS ? '⌘B' : 'Ctrl+B'})',
      onPressed: shell.toggleSidebar,
    );
  }
}

/// Re-runs the selected worktree's `tool/flutterware.dart`.
///
/// Worktree discovery is *not* what this does — the switcher rescans itself
/// when it opens, which is the only moment that list is looked at.
class _ReloadButton extends StatelessWidget {
  const _ReloadButton(this.shell);

  final ShellController shell;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    var worktree = shell.selected;
    var blocked =
        worktree != null && (shell.sessionFor(worktree)?.isBlocked ?? false);
    var enabled = worktree != null && !blocked && !shell.isLoading(worktree);

    return Tooltip(
      message: blocked
          ? 'A plugin is busy; reloading would tear it down'
          : 'Reload this worktree’s config',
      child: IconButton(
        onPressed: enabled ? () => shell.reloadConfig() : null,
        icon: Icon(Icons.refresh, size: 16, color: colors.mut),
        disabledColor: colors.mut3,
        constraints: const BoxConstraints.tightFor(width: 28, height: 28),
        padding: EdgeInsets.zero,
      ),
    );
  }
}

/// The key a worktree's tab carries, so a test can point at the tab rather than
/// at a name the home screen also shows.
Key worktreeTabKey(Worktree worktree) => ValueKey('tab:${worktree.path}');

class _WorktreeTab extends StatelessWidget {
  _WorktreeTab(this.shell, this.worktree)
    : super(key: worktreeTabKey(worktree));

  final ShellController shell;
  final Worktree worktree;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    var selected = shell.selected == worktree;
    var loading = shell.isLoading(worktree);
    var status = shell.sessionFor(worktree)?.status ?? Status.none;
    var radius = Radius.circular(context.radii.radiusSmall);
    // Always allocated, transparent when unselected: a border that appears on
    // selection changes the tab's size and shifts everything beside it.
    var edge = BorderSide(color: selected ? colors.line : Colors.transparent);

    return _Hoverable(
      onTap: () => shell.select(worktree),
      builder: (context, hovered) => Container(
        height: _bandHeight - _tabInset,
        margin: const EdgeInsets.only(top: _tabInset, right: FwSpacing.xs),
        padding: const EdgeInsets.only(left: FwSpacing.lg, right: FwSpacing.sm),
        decoration: BoxDecoration(
          color: selected
              ? colors.bg
              : hovered
              ? colors.hoverOverlay
              : Colors.transparent,
          borderRadius: BorderRadius.only(topLeft: radius, topRight: radius),
          border: Border(top: edge, left: edge, right: edge),
        ),
        child: Row(
          children: [
            if (loading) ...[
              SizedBox.square(
                dimension: 9,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: colors.mut2,
                ),
              ),
              const Gap(FwSpacing.md),
            ] else if (!status.isEmpty && status.tone != Tone.neutral) ...[
              _Dot(toneColor(colors, status.tone)),
              const Gap(FwSpacing.sm),
            ],
            // Capped, or a branch called `feature/some-long-description` gives
            // itself a tab wide enough to push the switcher off screen. The
            // tooltip is where the whole name still lives.
            Tooltip(
              message: worktree.branch == null || worktree.title == null
                  ? worktree.displayName
                  : '${worktree.displayName}\n${worktree.branch}',
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: _tabLabelMaxWidth),
                child: Text(
                  worktree.displayName,
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                  style: selected
                      ? context.type.bodyStrong
                      : context.type.bodyMuted,
                ),
              ),
            ),
            const Gap(FwSpacing.sm),
            _CloseButton(shell, worktree),
          ],
        ),
      ),
    );
  }
}

/// Gives a target a pointer cursor and a hover state.
///
/// The shell is a desktop app: a row that does not answer the mouse reads as
/// decoration rather than as something you can click. [builder] receives the
/// hover state so each row decides what hovering means for it — a wash, a
/// brighter rail — instead of every one growing its own [MouseRegion].
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

    var colors = context.colors;
    return Tooltip(
      message: blockers.isEmpty ? 'Close worktree' : blockers.join('\n'),
      child: _Hoverable(
        onTap: () {
          if (!shell.close(worktree)) _showBlocked(context, blockers);
        },
        builder: (context, hovered) => Icon(
          blockers.isEmpty ? Icons.close : Icons.lock_outline,
          size: 13,
          color: blockers.isNotEmpty
              ? colors.amber
              : hovered
              ? colors.ink
              : colors.mut2,
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

  /// Opening the menu is the only moment this list is read, so it is also the
  /// only moment worth rescanning. Not awaited: the last known worktrees are
  /// shown immediately and git's answer folds in when it arrives.
  void _open() {
    _menuController.open();
    unawaited(shell.rescanWorktrees());
  }

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    return Padding(
      // Aligns to the tabs' box rather than the band's, which is 6px taller.
      padding: const EdgeInsets.only(top: _tabInset),
      child: Center(
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
            message: 'Switch worktree',
            child: IconButton(
              onPressed: () => controller.isOpen ? controller.close() : _open(),
              icon: Icon(Icons.expand_more, size: 18, color: colors.mut),
              constraints: const BoxConstraints.tightFor(width: 28, height: 28),
              padding: EdgeInsets.zero,
            ),
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
        isOpen ? shell.select(worktree) : unawaited(shell.open(worktree));
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

/// The worktree's home row, then one row per plugin with the status its report
/// carries.
class _Sidebar extends StatelessWidget {
  const _Sidebar(this.shell);

  final ShellController shell;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    var worktree = shell.selected;
    var session = shell.selectedSession;
    return Container(
      width: _sidebarWidth,
      decoration: BoxDecoration(
        color: colors.panel,
        border: Border(right: BorderSide(color: colors.line)),
      ),
      child: worktree == null
          ? null
          : ListView(
              padding: const EdgeInsets.symmetric(vertical: FwSpacing.lg),
              children: [
                _Row(
                  // Not the worktree's name: the tab above already says that,
                  // and this row is a destination, not a label.
                  label: 'Overview',
                  selected: shell.isHome,
                  onTap: shell.selectHome,
                  icon: Icons.home_outlined,
                  // The config error lives on that screen, so the row has to
                  // say so — otherwise it is invisible from any plugin panel.
                  status: shell.errorFor(worktree) == null
                      ? Status.none
                      : const Status.error('config'),
                ),
                const Gap(FwSpacing.lg),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    FwSpacing.xl,
                    0,
                    FwSpacing.xl,
                    FwSpacing.md,
                  ),
                  child: Text('PLUGINS', style: context.type.micro),
                ),
                if (session == null)
                  const _SidebarSkeleton()
                else if (session.plugins.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: FwSpacing.xl,
                    ),
                    child: Text(
                      'No plugins declared.\nAdd them in tool/flutterware.dart.',
                      style: context.type.caption,
                    ),
                  )
                else
                  for (var plugin in session.plugins) ...[
                    _PluginRow(shell, plugin),
                    // Expanded only for the selected plugin: a sidebar showing
                    // every package of every plugin at once is a wall, not a
                    // summary.
                    if (shell.selectedPluginId == plugin.id)
                      for (var child in plugin.core.report.children)
                        _ChildRow(shell, plugin.id, child),
                  ],
              ],
            ),
    );
  }
}

/// Stands in for the plugin rows while the config is still running, so the
/// sidebar has the shape it will have rather than jumping into existence.
class _SidebarSkeleton extends StatelessWidget {
  const _SidebarSkeleton();

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    return Column(
      children: [
        for (var i = 0; i < 3; i++)
          Container(
            height: 14,
            margin: EdgeInsets.fromLTRB(
              FwSpacing.xl,
              FwSpacing.md,
              FwSpacing.xl + i * 18.0,
              FwSpacing.md,
            ),
            decoration: BoxDecoration(
              color: colors.line,
              borderRadius: BorderRadius.circular(context.radii.radiusSmall),
            ),
          ),
      ],
    );
  }
}

/// The one row shape the sidebar uses: a filled selection, no border, so
/// selecting never changes anyone's size.
class _Row extends StatelessWidget {
  const _Row({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.status = Status.none,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;
  final Status status;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    return _Hoverable(
      onTap: onTap,
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
          color: selected
              ? colors.accentSoft
              : hovered
              ? colors.hoverOverlay
              : Colors.transparent,
          borderRadius: BorderRadius.circular(context.radii.radiusSmall),
        ),
        child: Row(
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 14,
                color: selected ? colors.accent : colors.mut,
              ),
              const Gap(FwSpacing.md),
            ],
            Expanded(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: selected
                    ? context.type.bodyStrong.copyWith(color: colors.accent)
                    : context.type.body,
              ),
            ),
            if (!status.isEmpty) ...[
              const Gap(FwSpacing.sm),
              Text(
                status.message,
                style: context.type.micro.copyWith(
                  color: toneColor(colors, status.tone),
                ),
              ),
            ],
          ],
        ),
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
    var report = plugin.core.report;
    return _Row(
      label: report.label,
      selected: shell.selectedPluginId == plugin.id,
      onTap: () => shell.selectPlugin(plugin.id),
      status: report.status,
    );
  }
}

/// One package of a plugin, hung off a rail rather than boxed. Selecting it is
/// what raises that package's work.
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

    return _Hoverable(
      onTap: () => shell.selectChild(pluginId, child.id),
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
            Expanded(
              child: Text(
                child.label,
                overflow: TextOverflow.ellipsis,
                style: context.type.bodySmall.copyWith(
                  color: selected ? colors.ink : colors.mut,
                ),
              ),
            ),
            if (!child.status.isEmpty) ...[
              const Gap(FwSpacing.sm),
              Text(
                child.status.message,
                style: context.type.micro.copyWith(
                  color: toneColor(colors, child.status.tone),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Mounts the selected plugin's panel — the one place a native plugin is
/// unrestricted Flutter — or the worktree's home screen.
class _Panel extends StatelessWidget {
  const _Panel(this.shell);

  final ShellController shell;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    var worktree = shell.selected;
    var session = shell.selectedSession;

    Widget body;
    if (worktree == null) {
      body = const _Message(title: 'No worktree open');
    } else if (session == null) {
      body = _Loading(worktree.displayName);
    } else {
      var plugin = shell.selectedPluginId == null
          ? null
          : session.pluginById(shell.selectedPluginId!);
      body = plugin == null
          ? WorktreeHome(shell, worktree)
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

/// What an opening worktree shows while its config runs. The tab is already
/// there; this is the rest of the window catching up.
class _Loading extends StatelessWidget {
  const _Loading(this.name);

  final String name;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox.square(
          dimension: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const Gap(FwSpacing.lg),
        Text('Reading $name’s config…', style: context.type.caption),
      ],
    ),
  );
}

class _Message extends StatelessWidget {
  const _Message({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(FwSpacing.xxxl),
      child: Text(
        title,
        style: context.type.heading.copyWith(color: context.colors.mut2),
      ),
    ),
  );
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
