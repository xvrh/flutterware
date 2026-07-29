import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutterware/plugins.dart';

import '../address/address_scope.dart';
import '../plugins/native_plugin.dart';
import '../ui/theme.dart';
import 'address_bar.dart';
import 'config_load.dart';
import 'config_screen.dart';
import '../utils/hot_reload.dart';
import '../utils/value_stream_builder.dart';
import 'shell_controller.dart';
import 'shell_search.dart';
import 'sidebar_row.dart';
import 'worktree.dart';
import 'worktree_home.dart';

/// The transient "what the last reload did" line in the band.
const configLoadLineKey = Key('config-load-line');

/// The sticky config-failure banner under the band.
const configErrorBannerKey = Key('config-error-banner');

/// The band button that opens the config screen.
const configButtonKey = Key('config-button');

/// Width the macOS traffic lights occupy; band content insets past them.
const _trafficLightInset = 78.0;
const _bandHeight = 40.0;

/// How far tabs sit below the top of the band. Everything else in the band
/// aligns to the box this leaves, not to the band itself.
const _tabInset = 6.0;

/// How much of a tab a worktree's name may claim before it is ellipsised.
const _tabLabelMaxWidth = 180.0;
const _sidebarWidth = 232.0;

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
      home: ShellView(shell),
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
          const SingleActivator(LogicalKeyboardKey.keyK, meta: true): () =>
              unawaited(showShellSearch(context, shell)),
          const SingleActivator(LogicalKeyboardKey.keyK, control: true): () =>
              unawaited(showShellSearch(context, shell)),
          // The same screen in the next checkout, and back. The bracket pair is
          // what every editor uses for cycling, and with two worktrees open it
          // is the A/B flick that makes a visual comparison possible at all.
          const SingleActivator(
            LogicalKeyboardKey.bracketRight,
            meta: true,
            shift: true,
          ): () =>
              shell.cycleWorktree(1),
          const SingleActivator(
            LogicalKeyboardKey.bracketLeft,
            meta: true,
            shift: true,
          ): () =>
              shell.cycleWorktree(-1),
          const SingleActivator(
            LogicalKeyboardKey.bracketRight,
            control: true,
            shift: true,
          ): () =>
              shell.cycleWorktree(1),
          const SingleActivator(
            LogicalKeyboardKey.bracketLeft,
            control: true,
            shift: true,
          ): () =>
              shell.cycleWorktree(-1),
        },
        // Key events dispatch from whatever holds primary focus and bubble to
        // its *ancestors*. With nothing focused that is the root scope, which
        // sits above `CallbackShortcuts` — so the bindings never see a key
        // until something inside happens to be focused. Taking focus on mount
        // puts the shell below them, which is what makes a shortcut work
        // without clicking the window first.
        child: Focus(
          autofocus: true,
          // The top of the address tree, wrapping the band as well as the
          // panel: the bar that displays the address is a consumer of it like
          // any other, and putting it outside would make it the one thing that
          // needs its own way of reading.
          child: AddressRoot(
            address: shell.addressListenable,
            onChanged: shell.go,
            child: Scaffold(
              body: Column(
                children: [
                  _Band(shell),
                  // Above the rail and the panel both, because it is a fact
                  // about the worktree rather than about whatever is mounted —
                  // and a config that failed no longer takes the panel down
                  // with it, so this is the only thing that would say so.
                  _ConfigErrorBanner(shell),
                  Expanded(
                    child: Row(
                      children: [
                        if (shell.sidebarVisible) _Sidebar(shell),
                        Expanded(child: _Panel(shell)),
                      ],
                    ),
                  ),
                  AddressBar(shell),
                ],
              ),
            ),
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
          SearchTrigger(
            onTap: () => unawaited(showShellSearch(context, shell)),
          ),
          const Gap(FwSpacing.md),
          _ConfigLoadLine(shell),
          _ConfigButton(shell),
          const _HotReloadButtons(),
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

/// The selected worktree's config failure, until a load succeeds.
///
/// **Not dismissible.** It is a fact about a file on disk, so hiding it would
/// hide a real problem — and unlike before, there is no other symptom to notice:
/// the plugins built from the last config that loaded are all still running
/// behind it.
///
/// Says one line and offers the screen. The compiler's own output lives on
/// `fw://<worktree>/config`, where the reload button and the history of previous
/// reloads are, and rendering it in two places would mean maintaining it in two
/// places.
class _ConfigErrorBanner extends StatelessWidget {
  const _ConfigErrorBanner(this.shell);

  final ShellController shell;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    var worktree = shell.selected;
    var error = worktree == null ? null : shell.errorFor(worktree);
    // Redundant while you are looking at the screen that explains it.
    if (error == null || shell.isConfigScreen) return const SizedBox.shrink();

    return Container(
      key: configErrorBannerKey,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: FwSpacing.lg,
        vertical: FwSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: colors.red.withValues(alpha: 0.08),
        border: Border(bottom: BorderSide(color: colors.red)),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, size: 14, color: colors.red),
          const Gap(FwSpacing.sm),
          Expanded(
            child: Text(
              error.message.trimRight().split('\n').first,
              style: context.type.caption.copyWith(color: colors.red),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          TextButton(
            onPressed: shell.selectConfig,
            style: TextButton.styleFrom(
              minimumSize: Size.zero,
              padding: const EdgeInsets.symmetric(horizontal: FwSpacing.sm),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              'Details',
              style: context.type.caption.copyWith(color: colors.red),
            ),
          ),
        ],
      ),
    );
  }
}

/// What the last config load did, for a few seconds after it did it.
///
/// **The `unchanged` case is the reason this exists.** A reload that matched and
/// a reload that never happened are the same absence of feedback, and that
/// ambiguity is what makes reloading feel unreliable — so a load always says
/// something, even when the answer is "nothing moved". The duration rides along
/// so a drift from ~100ms to seconds is visible without anyone going looking.
///
/// Opening a worktree is deliberately silent: the tab appearing is already the
/// feedback, and announcing it would make every switch chatty.
class _ConfigLoadLine extends StatefulWidget {
  const _ConfigLoadLine(this.shell);

  final ShellController shell;

  @override
  State<_ConfigLoadLine> createState() => _ConfigLoadLineState();
}

class _ConfigLoadLineState extends State<_ConfigLoadLine> {
  static const _linger = Duration(seconds: 4);

  ConfigLoad? _showing;
  Timer? _hide;

  @override
  void initState() {
    super.initState();
    widget.shell.addListener(_check);
  }

  @override
  void dispose() {
    widget.shell.removeListener(_check);
    _hide?.cancel();
    super.dispose();
  }

  void _check() {
    var worktree = widget.shell.selected;
    var load = worktree == null ? null : widget.shell.lastLoad(worktree);
    if (load == null ||
        load == _showing ||
        load.outcome == ConfigLoadOutcome.built) {
      return;
    }
    setState(() => _showing = load);
    _hide?.cancel();
    _hide = Timer(_linger, () {
      if (mounted) setState(() => _showing = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    var load = _showing;
    return AnimatedOpacity(
      opacity: load == null ? 0 : 1,
      duration: const Duration(milliseconds: 200),
      child: load == null
          ? const SizedBox.shrink()
          : Padding(
              key: configLoadLineKey,
              padding: const EdgeInsets.only(right: FwSpacing.sm),
              child: Text(
                '${load.summary} · ${load.duration.inMilliseconds}ms',
                style: context.type.caption.copyWith(
                  color: load.succeeded ? colors.mut : colors.red,
                ),
              ),
            ),
    );
  }
}

/// Opens `fw://<worktree>/config`.
///
/// **This used to reload on click**, which put the action in the chrome and its
/// result nowhere: a reload that rebuilt one plugin, or refused because a plugin
/// was busy, had no place to say so. Now the button is navigation and the Reload
/// button lives on the screen, next to the log of what previous reloads did.
///
/// It carries the config's state, because that is the one thing about this file
/// worth a permanent pixel in the band: a dot when the config is failing.
class _ConfigButton extends StatelessWidget {
  const _ConfigButton(this.shell);

  final ShellController shell;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    var worktree = shell.selected;
    var failing = worktree != null && shell.errorFor(worktree) != null;
    // Amber, not red: the file is fine, the reload is merely waiting. Silence
    // here would look exactly like a watcher that is not working.
    var pending = worktree != null && shell.isReloadPending(worktree);
    var dot = failing ? colors.red : (pending ? colors.amber : null);

    return Tooltip(
      message: failing
          ? 'This worktree’s config did not load'
          : pending
          ? 'The config changed; a plugin is busy'
          : 'Config — what tool/flutterware.dart resolved to',
      child: IconButton(
        key: configButtonKey,
        onPressed: worktree == null ? null : shell.selectConfig,
        icon: Stack(
          clipBehavior: Clip.none,
          children: [
            Icon(
              Icons.tune,
              size: 16,
              color: shell.isConfigScreen ? colors.accent : colors.mut,
            ),
            if (dot != null)
              Positioned(
                right: -1,
                top: -1,
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
                ),
              ),
          ],
        ),
        disabledColor: colors.mut3,
        constraints: const BoxConstraints.tightFor(width: 28, height: 28),
        padding: EdgeInsets.zero,
      ),
    );
  }
}

/// Hot reload and hot restart of flutterware itself.
///
/// Only rendered when `flutter run` is driving this process — see [HotReload],
/// which is what registers the methods that make either possible. For anyone
/// who installed flutterware rather than building it, these never appear, and
/// that is correct rather than a degraded experience: there is no compiler
/// present to produce new code.
///
/// Distinct from [_ConfigButton] beside it, which opens the *worktree's config*
/// screen. That one is for using flutterware; this pair is for working on it.
class _HotReloadButtons extends StatefulWidget {
  const _HotReloadButtons();

  @override
  State<_HotReloadButtons> createState() => _HotReloadButtonsState();
}

class _HotReloadButtonsState extends State<_HotReloadButtons> {
  HotReload? _hot;

  @override
  void initState() {
    super.initState();
    // Connecting is a socket to ourselves and costs nothing when it fails,
    // which is the common case.
    unawaited(
      HotReload.connect().then((hot) {
        if (!mounted) {
          unawaited(hot?.dispose());
          return;
        }
        setState(() => _hot = hot);
      }),
    );
  }

  @override
  void dispose() {
    unawaited(_hot?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var hot = _hot;
    if (hot == null) return const SizedBox.shrink();

    return ValueStreamBuilder<bool>(
      stream: hot.available,
      builder: (context, available, _) {
        if (!available) return const SizedBox.shrink();
        var colors = context.colors;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _bandButton(
              colors: colors,
              icon: Icons.local_fire_department_outlined,
              tooltip: 'Hot reload flutterware',
              onPressed: hot.reload,
            ),
            if (hot.canRestart)
              _bandButton(
                colors: colors,
                icon: Icons.restart_alt,
                // Naming what it costs: this tears down the window drawing it.
                tooltip: 'Hot restart flutterware (the window will reappear)',
                onPressed: hot.restart,
              ),
          ],
        );
      },
    );
  }

  Widget _bandButton({
    required FwPalette colors,
    required IconData icon,
    required String tooltip,
    required Future<void> Function() onPressed,
  }) => Tooltip(
    message: tooltip,
    child: IconButton(
      onPressed: () => unawaited(onPressed()),
      icon: Icon(icon, size: 16, color: colors.mut),
      constraints: const BoxConstraints.tightFor(width: 28, height: 28),
      padding: EdgeInsets.zero,
    ),
  );
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
/// Finds the plugin rail. A plugin's label and a package's name also appear in
/// the address along the bottom, so a test about the rail has to say it means
/// the rail.
const sidebarKey = ValueKey('shell.sidebar');

class _Sidebar extends StatelessWidget {
  const _Sidebar(this.shell);

  final ShellController shell;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    var worktree = shell.selected;
    var session = shell.selectedSession;
    return Container(
      key: sidebarKey,
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
                        SidebarChildRow(
                          label: child.label,
                          status: child.status,
                          selected:
                              shell.selectedPluginId == plugin.id &&
                              shell.selectedChildId == child.id,
                          commands: plugin.childCommands(context, child.id),
                          onTap: () => shell.selectChild(plugin.id, child.id),
                        ),
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
    } else if (shell.isConfigScreen) {
      body = ConfigScreen(shell, worktree);
    } else {
      var plugin = shell.selectedPluginId == null
          ? null
          : session.pluginById(shell.selectedPluginId!);
      body = plugin == null
          ? WorktreeHome(shell, worktree)
          : KeyedSubtree(
              // Rebuild the panel from scratch when the worktree or the plugin
              // changes; panels hold their own state and must not leak it
              // across worktrees. Nothing below the plugin is in the key —
              // moving within a plugin should update the panel, not remount it,
              // or a compile loop would be torn down and restarted for a click
              // in its own tree.
              key: ValueKey('${session.worktree.path}::${plugin.id}'),
              // The plugin's own level of the address tree. The panel reads
              // what it needs from here; the shell does not read past the
              // plugin segment and does not pass what it has not read.
              child: AddressScope(child: plugin.buildPanel(context)),
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
