// THROWAWAY shell prototype. Fake data, no project model, no daemon.
// Explores the chosen chrome before M1 — worktree tabs in the reclaimed
// titlebar band plus a switcher popover for worktrees that are not open.
// Delete once M1 lands the real shell.
//
//   flutter run -d macos -t lib/main_shell_dev.dart
import 'package:flutter/material.dart';

import 'src/ui/theme.dart';

void main() => runApp(const ShellMockApp());

/// Width the traffic lights occupy; band content insets past it.
const _trafficLightInset = 78.0;
const _bandHeight = 40.0;
const _sidebarWidth = 232.0;

class ShellMockApp extends StatelessWidget {
  const ShellMockApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: appTheme,
      home: const Scaffold(body: _Shell()),
    );
  }
}

// ── fake data ────────────────────────────────────────────────────────────────

class Worktree {
  const Worktree(
    this.title,
    this.branch, {
    this.open = false,
    this.note,
    this.tone,
  });

  final String title;
  final String branch;

  /// Open worktrees get a tab and hold live subscriptions; the rest are only
  /// listed in the switcher and cost nothing.
  final bool open;
  final String? note;
  final Color? tone;
}

class PluginEntry {
  const PluginEntry(this.icon, this.label, this.status, {this.tone});
  final IconData icon;
  final String label;
  final String status;
  final Color? tone;
}

List<Worktree> _worktrees(FwPalette c) => [
  Worktree(
    'Worktree explorer design',
    'feature/explorer',
    open: true,
    note: 'claude waiting',
    tone: c.amber,
  ),
  const Worktree('main', 'main', open: true),
  Worktree(
    'Fix flaky PTY test',
    'fix/pty',
    open: true,
    note: 'ahead 3',
    tone: c.grn,
  ),
  Worktree(
    'Scenario runner rewrite',
    'feature/scenarios',
    note: '2 failing',
    tone: c.red,
  ),
  const Worktree('Bump analyzer', 'chore/analyzer'),
  Worktree('Release 0.6.0', 'release/0.6.0', note: 'PR open', tone: c.info),
  const Worktree('Spike: termui', 'spike/termui'),
];

List<PluginEntry> _plugins(FwPalette c) => [
  PluginEntry(Icons.science_outlined, 'Tests', '3 failing', tone: c.red),
  PluginEntry(Icons.grid_view_outlined, 'UI catalog', '48 entries'),
  PluginEntry(Icons.inventory_2_outlined, 'Dependencies', '170 direct'),
  PluginEntry(Icons.flag_outlined, 'Feature flags', '2 on'),
  PluginEntry(Icons.dns_outlined, 'Docker', 'stack down', tone: c.amber),
  PluginEntry(Icons.commit_outlined, 'Git', 'ahead 3', tone: c.grn),
  PluginEntry(Icons.image_outlined, 'Launcher icon', ''),
  PluginEntry(Icons.terminal_outlined, 'Processes', '2 running'),
];

// ── shell ────────────────────────────────────────────────────────────────────

class _Shell extends StatelessWidget {
  const _Shell();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const _Band(),
        Expanded(
          child: Row(
            children: [
              const _PluginSidebar(),
              Expanded(
                child: Container(
                  color: context.colors.bg,
                  child: const _Panel(),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The reclaimed titlebar band: a tab per *open* worktree, then the switcher.
class _Band extends StatelessWidget {
  const _Band();

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    var worktrees = _worktrees(colors);
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
                for (var (i, worktree) in worktrees.indexed)
                  if (worktree.open)
                    _WorktreeTab(worktree: worktree, selected: i == 0),
                const _SwitcherButton(),
              ],
            ),
          ),
          _BandAction(Icons.refresh, 'Reload config'),
          const Gap(FwSpacing.md),
        ],
      ),
    );
  }
}

class _BandAction extends StatelessWidget {
  const _BandAction(this.icon, this.tooltip);
  final IconData icon;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        onPressed: () {},
        icon: Icon(icon, size: 16, color: context.colors.mut),
        constraints: const BoxConstraints.tightFor(width: 28, height: 28),
        padding: EdgeInsets.zero,
      ),
    );
  }
}

class _WorktreeTab extends StatelessWidget {
  const _WorktreeTab({required this.worktree, required this.selected});
  final Worktree worktree;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    var radius = Radius.circular(context.radii.radiusSmall);
    return Container(
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
          if (worktree.tone != null) ...[
            _Dot(worktree.tone!),
            const Gap(FwSpacing.sm),
          ],
          Text(
            worktree.title,
            style: selected ? context.type.bodyStrong : context.type.bodyMuted,
          ),
          const Gap(FwSpacing.sm),
          // Closing a tab releases that worktree's watchers and subscriptions.
          Icon(Icons.close, size: 13, color: colors.mut2),
        ],
      ),
    );
  }
}

/// Opens the full `git worktree list` — the ones without a tab included.
class _SwitcherButton extends StatelessWidget {
  const _SwitcherButton();

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    return Center(
      child: MenuAnchor(
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
        menuChildren: [const _SwitcherMenu()],
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
  const _SwitcherMenu();

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    var worktrees = _worktrees(colors);
    var closed = worktrees.where((w) => !w.open).toList();
    return SizedBox(
      width: 340,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _MenuHeading('OPEN'),
          for (var worktree in worktrees.where((w) => w.open))
            _SwitcherRow(worktree: worktree),
          const Gap(FwSpacing.md),
          _MenuHeading('NOT OPEN · ${closed.length}'),
          for (var worktree in closed) _SwitcherRow(worktree: worktree),
        ],
      ),
    );
  }
}

class _MenuHeading extends StatelessWidget {
  const _MenuHeading(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        FwSpacing.xl,
        FwSpacing.sm,
        FwSpacing.xl,
        FwSpacing.sm,
      ),
      child: Text(label, style: context.type.micro),
    );
  }
}

class _SwitcherRow extends StatelessWidget {
  const _SwitcherRow({required this.worktree});
  final Worktree worktree;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    return InkWell(
      onTap: () {},
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: FwSpacing.xl,
          vertical: FwSpacing.md,
        ),
        child: Row(
          children: [
            SizedBox(
              width: 14,
              child: worktree.tone != null
                  ? _Dot(worktree.tone!)
                  : const SizedBox(),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    worktree.title,
                    style: worktree.open
                        ? context.type.bodyStrong
                        : context.type.body,
                  ),
                  Text(worktree.branch, style: context.type.caption),
                ],
              ),
            ),
            if (worktree.note != null)
              Text(
                worktree.note!,
                style: context.type.micro.copyWith(
                  color: worktree.tone ?? colors.mut2,
                ),
              )
            else if (!worktree.open)
              Text(
                'Open',
                style: context.type.micro.copyWith(color: colors.accent),
              ),
          ],
        ),
      ),
    );
  }
}

class _PluginSidebar extends StatelessWidget {
  const _PluginSidebar();

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
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
          for (var (i, plugin) in _plugins(colors).indexed)
            _PluginRow(plugin: plugin, selected: i == 1, colors: colors),
        ],
      ),
    );
  }
}

class _PluginRow extends StatelessWidget {
  const _PluginRow({
    required this.plugin,
    required this.selected,
    required this.colors,
  });
  final PluginEntry plugin;
  final bool selected;
  final FwPalette colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: FwSpacing.md, vertical: 1),
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
          Icon(
            plugin.icon,
            size: 16,
            color: selected ? colors.accent : colors.mut,
          ),
          const Gap(FwSpacing.lg),
          Expanded(
            child: Text(
              plugin.label,
              style: selected
                  ? context.type.bodyStrong.copyWith(color: colors.accent)
                  : context.type.body,
            ),
          ),
          if (plugin.status.isNotEmpty)
            Text(
              plugin.status,
              style: context.type.micro.copyWith(
                color: plugin.tone ?? colors.mut2,
              ),
            ),
        ],
      ),
    );
  }
}

/// Stand-in for whatever plugin panel is mounted.
class _Panel extends StatelessWidget {
  const _Panel();

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    return Padding(
      padding: const EdgeInsets.all(FwSpacing.xxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('UI catalog', style: context.type.pageTitle),
              const Gap(FwSpacing.lg),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: FwSpacing.md,
                  vertical: FwSpacing.xxs,
                ),
                decoration: BoxDecoration(
                  color: colors.statusFill(colors.grn),
                  border: Border.all(color: colors.statusBorder(colors.grn)),
                  borderRadius: BorderRadius.circular(
                    context.radii.radiusSmall,
                  ),
                ),
                child: Text(
                  'guest warm · 118ms',
                  style: context.type.micro.copyWith(color: colors.grn),
                ),
              ),
            ],
          ),
          const Gap(FwSpacing.xs),
          Text('feature/explorer · 48 entries', style: context.type.bodyMuted),
          const Gap(FwSpacing.xxl),
          Expanded(
            child: GridView.count(
              crossAxisCount: 4,
              mainAxisSpacing: FwSpacing.xl,
              crossAxisSpacing: FwSpacing.xl,
              childAspectRatio: 1.4,
              children: [
                for (var i = 0; i < 8; i++)
                  Container(
                    decoration: BoxDecoration(
                      color: colors.panel,
                      border: Border.all(color: colors.line),
                      borderRadius: BorderRadius.circular(context.radii.radius),
                    ),
                    child: Center(
                      child: Icon(
                        Icons.crop_original,
                        color: colors.mut3,
                        size: 28,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot(this.color);
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 7,
      height: 7,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}
