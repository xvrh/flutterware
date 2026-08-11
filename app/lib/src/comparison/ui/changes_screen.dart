import 'dart:async';

import 'package:flutter/material.dart';

import '../../capture/settle.dart';
import '../../shell/shell_controller.dart';
import '../../shell/worktree.dart';
import '../../ui/empty_state.dart';
import '../../ui/tappable.dart';
import '../../ui/theme.dart';
import '../channels.dart';
import '../comparison_controller.dart';
import '../session_environment.dart';
import 'state_chip.dart';

/// The changes screen's root, so a test can scope to it.
const changesScreenKey = Key('changes-screen');

Key changesTabKey(String id) => ValueKey('changes.tab.$id');

/// **`fw:///worktrees/<worktree>/changes`** — what this branch did.
///
/// Three renderings of one delta, against one base: the files that changed,
/// what the previews look like on either side, and what the scenarios do.
///
/// **Not its own space, and the reversal is the interesting part.** The design
/// doc argued for one, from the premise that a comparison spans two plugins and
/// needs a session on both sides — which is a fact about the *runner*, and one
/// `fw compare` disproves by running with no session on the base at all. What a
/// comparison spans is not what a screen belongs to. The case that matters is
/// this work against its base, which is a fact about one worktree.
///
/// **Files is free and the other two cost seconds**, and that is why they are
/// tabs on one panel rather than a place of their own: behind a tab on the
/// screen you already open to read a diff, the expensive halves get discovered.
/// Somewhere else they would have to be remembered, and a feature that has to
/// be remembered is used twice.
class ChangesScreen extends StatefulWidget {
  const ChangesScreen(this.shell, this.worktree, {super.key});

  final ShellController shell;
  final Worktree worktree;

  @override
  State<ChangesScreen> createState() => _ChangesScreenState();
}

class _ChangesScreenState extends State<ChangesScreen> implements SettleSource {
  ComparisonController? _controller;

  /// Why there is no comparison at all — not a git repository, no base.
  String? _unavailable;

  var _loading = true;

  @override
  void initState() {
    super.initState();
    // **Registered synchronously, before the first await.** Registering after
    // one leaves the registry empty for as long as that await takes, and a
    // capture only needs 250ms of quiet to decide the window is worth
    // photographing — which is how the first capture of this screen came back
    // `settled: true` over the words "Preparing the base checkout…".
    widget.shell.appContext.settle.add(this);
    unawaited(_open());
  }

  /// What a capture must not photograph through.
  ///
  /// Answered from the same state the screen draws from, as [SettleSource]
  /// requires. **Busy includes [HalfStage.ready]**, which is the state between
  /// the estimate landing and the tab's run starting: it is a microtask wide
  /// and it is idle, so a settle check that fell in it would photograph a list
  /// that has not begun filling.
  @override
  String? get busyWith {
    if (_loading) return 'opening the comparison';
    var controller = _controller;
    if (controller == null || controller.refusal != null) return null;
    if (controller.baseRoot == null) return 'preparing the base checkout';
    var half = _tabs.firstWhere((tab) => tab.id == _tab).half;
    return switch (half?.stage) {
      null || HalfStage.done || HalfStage.refused => null,
      _ => 'comparing ${half!.kind.label}',
    };
  }

  Future<void> _open() async {
    var session = widget.shell.selectedSession;
    if (session == null) return;
    var environment = await SessionComparisonEnvironment.open(
      session: session,
      flutterSdk: widget.shell.flutterSdk,
      appToolDirectory: widget.shell.appContext.appToolDirectory.path,
    );
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (environment == null) {
        _unavailable =
            'This worktree is not in a git repository with a base to '
            'compare against.';
        return;
      }
      _controller = ComparisonController(environment)..addListener(_onChange);
    });
    // Preparing the base is what lets a tab carry its estimate. Rendering and
    // replaying stay behind the tab.
    unawaited(_controller!.prepare().then((_) => _openSelectedTab()));
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  /// The tab named by the address, or the first one that has anything to show.
  String get _tab {
    var named = widget.shell.address.segments.firstOrNull;
    var tabs = _tabs;
    if (named != null && tabs.any((tab) => tab.id == named)) return named;
    return tabs.firstWhere((tab) => tab.available, orElse: () => tabs.first).id;
  }

  List<_Tab> get _tabs => [
    const _Tab(id: 'files', label: 'files', available: false),
    for (var half in _controller?.declared ?? const <ComparisonHalf>[])
      _Tab(id: half.kind.name, label: half.kind.label, half: half),
  ];

  void _select(String id) {
    widget.shell.selectChanges(tab: id);
    _openSelectedTab();
  }

  void _openSelectedTab() {
    var half = _tabs.firstWhere((tab) => tab.id == _tab).half;
    if (half != null) unawaited(_controller?.open(half.kind));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const SizedBox.shrink();
    if (_unavailable case var message?) {
      return EmptyState(title: 'Nothing to compare', message: message);
    }

    var controller = _controller!;
    var tabs = _tabs;
    var selected = tabs.firstWhere((tab) => tab.id == _tab);

    return Column(
      key: changesScreenKey,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Header(controller),
        _TabStrip(tabs: tabs, selected: selected.id, onSelect: _select),
        Expanded(
          child: selected.half == null
              ? const _FilesPlaceholder()
              : _HalfView(controller, selected.half!),
        ),
      ],
    );
  }

  @override
  void dispose() {
    widget.shell.appContext.settle.remove(this);
    _controller
      ?..removeListener(_onChange)
      ..dispose();
    super.dispose();
  }
}

class _Tab {
  const _Tab({
    required this.id,
    required this.label,
    this.half,
    this.available = true,
  });

  final String id;
  final String label;
  final ComparisonHalf? half;
  final bool available;
}

/// Both sides, and what the comparison found.
class _Header extends StatelessWidget {
  const _Header(this.controller);

  final ComparisonController controller;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    var counts = _counts();

    return Container(
      padding: const EdgeInsets.fromLTRB(
        FwSpacing.xxxl,
        FwSpacing.xxl,
        FwSpacing.xxxl,
        FwSpacing.lg,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Changes', style: context.type.pageTitle),
                const Gap(FwSpacing.xs),
                Text(
                  'against ${controller.environment.baseLabel}',
                  style: context.type.caption.copyWith(color: colors.mut),
                ),
              ],
            ),
          ),
          if (counts.isNotEmpty)
            Wrap(
              spacing: FwSpacing.sm,
              children: [
                for (var entry in counts.entries)
                  StateChip(entry.key, count: entry.value),
              ],
            ),
        ],
      ),
    );
  }

  /// Findings only, and merged across both halves: one preview that broke and
  /// one scenario that broke is two broken things, and which half they came
  /// from is the second question.
  Map<ComparedState, int> _counts() {
    var counts = <ComparedState, int>{};
    for (var state in [
      for (var row in controller.previews.rows) row.state,
      for (var scenario in controller.scenarios.scenarios) scenario.state,
    ]) {
      if (state.isFinding) counts[state] = (counts[state] ?? 0) + 1;
    }
    return Map.fromEntries(
      counts.entries.toList()
        ..sort((a, b) => a.key.index.compareTo(b.key.index)),
    );
  }
}

/// `[ files ][ previews · 14 of 213 ][ scenarios · 5 of 43 ]`
///
/// The estimate rides on the tab because that is where it has to arrive
/// *before* the click: opening a tab runs its half, so the cost has to be
/// readable from outside it. A tab whose estimate is not known yet says
/// nothing rather than guessing.
class _TabStrip extends StatelessWidget {
  const _TabStrip({
    required this.tabs,
    required this.selected,
    required this.onSelect,
  });

  final List<_Tab> tabs;
  final String selected;
  final void Function(String id) onSelect;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.line)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: FwSpacing.xxxl),
      child: Row(
        children: [
          for (var tab in tabs)
            _TabButton(
              tab: tab,
              selected: tab.id == selected,
              onTap: () => onSelect(tab.id),
            ),
        ],
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.tab,
    required this.selected,
    required this.onTap,
  });

  final _Tab tab;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    var half = tab.half;
    var note = switch (half?.stage) {
      null => null,
      HalfStage.refused => null,
      HalfStage.running => 'running…',
      _ => half?.estimate,
    };

    return Tappable.builder(
      key: changesTabKey(tab.id),
      onTap: onTap,
      builder: (context, hovered) => Container(
        padding: const EdgeInsets.symmetric(
          horizontal: FwSpacing.lg,
          vertical: FwSpacing.md,
        ),
        decoration: BoxDecoration(
          color: hovered && !selected ? colors.hoverOverlay : null,
          border: Border(
            bottom: BorderSide(
              color: selected ? colors.accent : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Row(
          children: [
            Text(
              tab.label,
              style: context.type.body.copyWith(
                color: selected
                    ? colors.ink
                    : tab.available
                    ? colors.mut
                    : colors.mut3,
              ),
            ),
            if (half?.stage == HalfStage.refused) ...[
              const Gap(FwSpacing.sm),
              Icon(Icons.error_outline, size: 12, color: colors.red),
            ],
            if (note != null) ...[
              const Gap(FwSpacing.sm),
              Text(
                '· $note',
                style: context.type.micro.copyWith(color: colors.mut),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// One half, in whatever state it is in.
class _HalfView extends StatelessWidget {
  const _HalfView(this.controller, this.half);

  final ComparisonController controller;
  final ComparisonHalf half;

  @override
  Widget build(BuildContext context) {
    switch (half.stage) {
      case HalfStage.undeclared:
        return const SizedBox.shrink();
      case HalfStage.refused:
        return _Refusal(half.refusal ?? 'It cannot be compared.');
      case HalfStage.preparing:
        return const _Working('Preparing the base checkout…');
      case HalfStage.ready:
      case HalfStage.running:
      case HalfStage.done:
        return _Rows(controller, half);
    }
  }
}

/// The list, filling as rows are decided.
///
/// **Findings first and everything else after**, rather than findings only: a
/// list that hides what it looked at cannot be told apart from a list that
/// did not look. The count at the bottom is what says the difference.
class _Rows extends StatelessWidget {
  const _Rows(this.controller, this.half);

  final ComparisonController controller;
  final ComparisonHalf half;

  @override
  Widget build(BuildContext context) {
    var rows = <(String id, ComparedState state, String? note)>[
      for (var row in half.rows) (row.label ?? row.id, row.state, row.note),
      for (var scenario in half.scenarios)
        (scenario.scenario, scenario.state, null),
    ];
    var findings = rows.where((row) => row.$2.isFinding).toList();
    var quiet = rows.length - findings.length;

    if (rows.isEmpty) {
      return half.isRunning
          ? const _Working('Comparing…')
          : const _Working('Nothing to compare yet.');
    }

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: FwSpacing.md),
      children: [
        for (var row in findings) _Row(id: row.$1, state: row.$2, note: row.$3),
        // Only once it has stopped looking. "Nothing changed" over a run still
        // in flight is a verdict the tool has not reached, and it is the one
        // sentence a reader would act on without checking.
        if (findings.isEmpty && !half.isRunning)
          Padding(
            padding: const EdgeInsets.all(FwSpacing.xxxl),
            child: Text(
              'Nothing changed.',
              style: context.type.body.copyWith(color: context.colors.mut),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            FwSpacing.xxxl,
            FwSpacing.xl,
            FwSpacing.xxxl,
            0,
          ),
          child: Text(
            half.isRunning
                ? 'Comparing… ${findings.length} so far'
                : '${rows.length} looked at, $quiet unchanged',
            style: context.type.micro.copyWith(color: context.colors.mut),
          ),
        ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.id, required this.state, this.note});

  final String id;
  final ComparedState state;
  final String? note;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: FwSpacing.xxxl,
        vertical: FwSpacing.xs,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 84, child: StateChip(state)),
          const Gap(FwSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(id, style: context.type.body),
                if (note case var note?) ...[
                  const Gap(2),
                  Text(
                    note,
                    style: context.type.caption.copyWith(color: colors.mut),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Refusal extends StatelessWidget {
  const _Refusal(this.message);

  final String message;

  @override
  Widget build(BuildContext context) => EmptyState(
    icon: Icons.error_outline,
    title: 'Not compared',
    message: message,
  );
}

class _Working extends StatelessWidget {
  const _Working(this.message);

  final String message;

  @override
  Widget build(BuildContext context) => Center(
    child: Text(
      message,
      style: context.type.body.copyWith(color: context.colors.mut),
    ),
  );
}

/// Until the file-changes panel lands and takes this tab.
class _FilesPlaceholder extends StatelessWidget {
  const _FilesPlaceholder();

  @override
  Widget build(BuildContext context) => const EmptyState(
    icon: Icons.description_outlined,
    title: 'The file diff lands here',
    message:
        'The two tabs beside this one compare what the branch looks like and '
        'what it does.',
  );
}
