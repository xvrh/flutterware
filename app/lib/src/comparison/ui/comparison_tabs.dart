import 'dart:async';

import 'package:flutter/material.dart';

import '../../capture/settle.dart';
import '../../shell/shell_controller.dart';
import '../../shell/worktree.dart';
import '../../ui/tappable.dart';
import '../../ui/theme.dart';
import '../channels.dart';
import '../comparison_controller.dart';
import '../session_environment.dart';
import '../shot_store_io.dart';
import 'previews_tab.dart';
import 'scenarios_tab.dart';
import 'state_chip.dart';
import '../../ui/error_state.dart';

/// The tab strip's root, so a test can scope to it.
const comparisonTabsKey = Key('comparison-tabs');

Key comparisonTabKey(String id) => ValueKey('changes.tab.$id');

/// The tab ids, which are also their first address segment.
const filesTabId = 'files';

/// Every tab id, so a reader of the address can tell a tab from a file path.
const comparisonTabIds = {filesTabId, 'previews', 'scenarios'};

/// **`fw:///worktrees/<worktree>/changes`** — what this branch did.
///
/// Three renderings of one delta against one base: the files that changed,
/// what the previews look like on either side, and what the scenarios do.
/// This owns the strip and the two comparison halves; the file diff is handed
/// in as [files], because it is a screen of its own with its own master,
/// detail and index tabs.
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
///
/// **The file half renders without a session and these two cannot.** It reads
/// git; they need the previews and scenarios cores, which need a resolved
/// config. So a checkout nobody has opened gets the files tab and no others,
/// which is the honest shape rather than a tab that would explain itself.
class ComparisonTabs extends StatefulWidget {
  const ComparisonTabs({
    super.key,
    required this.shell,
    required this.worktree,
    required this.files,
  });

  final ShellController shell;
  final Worktree worktree;

  /// The file diff, built only when its tab is showing.
  ///
  /// Told whether a strip was drawn above it, because that decides whether it
  /// has to name itself: with a strip it is a tab among three and writes no
  /// title, and without one it is the whole screen.
  final Widget Function(BuildContext context, bool withinTabs) files;

  @override
  State<ComparisonTabs> createState() => _ComparisonTabsState();
}

class _ComparisonTabsState extends State<ComparisonTabs>
    implements SettleSource {
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
    // **A session arrives late, and this screen mounts before it.** The file
    // diff needs none, so the tabs are shown for a checkout that is still
    // opening — and deciding "no session, no comparison" on the first frame
    // pinned that answer forever, on the very worktree the window was
    // launched in.
    widget.shell.addListener(_onShell);
    unawaited(_open());
  }

  void _onShell() {
    if (!mounted) return;
    if (_controller != null) {
      // **The address moves the tab too, and only a tap used to run it.**
      // `_select` is the click path; a pasted link, the back button and a
      // drive `navigate` all change the address without going through it, so
      // arriving at `changes/scenarios` from another tab lit the tab, drew its
      // half — and left it on `Nothing to compare yet.` for ever, because
      // nothing had asked the half to run. Idempotent: `open` joins a run in
      // flight and returns at once for one that has finished.
      _openSelectedTab();
      return;
    }
    if (widget.shell.sessionFor(widget.worktree) != null) {
      unawaited(_open());
    } else if (!widget.shell.isOpen(widget.worktree) && _unavailable == null) {
      // **Decided here, never on the first frame.** `ShellController.go`
      // deliberately does not open a tab for this screen — it renders for a
      // checkout nobody has opened — so at startup this mounts *before* the
      // window's own worktree has a session. Concluding "no comparison" in
      // that window latched the wrong answer, and told a window capture the
      // screen was finished when it had not begun.
      setState(() => _unavailable = 'Open this worktree to compare it.');
    }
  }

  /// What a capture must not photograph through.
  ///
  /// Answered from the same state the screen draws from, as [SettleSource]
  /// requires. **Busy includes [HalfStage.ready]**, which is the state between
  /// the base landing and the tab's run starting: it is a microtask wide and it
  /// is idle, so a settle check that fell in it would photograph a list that
  /// has not begun filling.
  @override
  String? get busyWith {
    if (_loading) return 'opening the comparison';
    // Undecided is busy. A capture that settled here would photograph the file
    // diff alone and report success; the alternative failure — a capture that
    // waits and then says `waitedOn: [opening the comparison]` — is one
    // somebody can act on.
    var controller = _controller;
    if (controller == null) {
      return _unavailable == null ? 'opening the comparison' : null;
    }
    if (controller.refusal != null) return null;
    var half = _tabs.firstWhere((tab) => tab.id == _tab).half;
    // **The files tab waits on nothing.** With the halves lazy, an unopened
    // comparison has no base checkout and never will until somebody asks for
    // one — so reading a null `baseRoot` as *preparing* would leave this screen
    // permanently busy on the one tab that prepares nothing.
    if (half == null) return null;
    if (controller.baseRoot == null) return 'preparing the base checkout';
    return switch (half.stage) {
      HalfStage.done || HalfStage.refused => null,
      _ => 'comparing ${half.kind.label}',
    };
  }

  Future<void> _open() async {
    // **The addressed worktree's session, not the selected one.** This screen
    // renders for a checkout that has no tab, which is precisely a checkout
    // `selectedSession` knows nothing about.
    if (_controller != null) return;
    var session = widget.shell.sessionFor(widget.worktree);
    if (session == null) {
      // Not open, so there are no cores and no comparison — only the file
      // diff, which needs none. Said rather than waited on: leaving `_loading`
      // true made this the one screen a window capture could never settle.
      // Not concluded here — see [_onShell]. Left undecided, which is what
      // keeps the screen busy until the shell has actually answered.
      if (mounted) setState(() => _loading = false);
      return;
    }
    var environment = await SessionComparisonEnvironment.open(
      session: session,
      flutterSdk: widget.shell.flutterSdk,
      appToolDirectory: widget.shell.appContext.appToolDirectory.path,
      // **The project's own answer, not a second one.** The file diff resolves
      // its base as `fw.changes(base:)` first and inference after; a comparison
      // that only ever inferred would compare against `master` on a screen
      // whose other tab says `develop`, and the design's one-definition rule
      // exists precisely to stop that.
      baseRef: widget.shell.manifestFor(widget.worktree)?.changes?.base,
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
    // **Nothing is prepared here.** Building the environment is two git calls
    // and answers what the strip needs — which halves this project declares,
    // and what they would be against. Everything past that, the base checkout
    // included, waits for a tab.
    _openSelectedTab();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  /// The tab named by the address's first segment.
  ///
  /// **Anything that is not a tab id is a file path**, which is what makes the
  /// grammar backwards compatible: `changes/app/lib/foo.dart` was a whole
  /// address before there were tabs, and it still means the file diff. New
  /// addresses spell it `changes/files/app/lib/foo.dart`, because a repository
  /// with a top-level `previews/` directory would otherwise be ambiguous
  /// exactly where it matters.
  String get _tab {
    var named = widget.shell.address.segments.firstOrNull;
    if (named != null && _tabs.any((tab) => tab.id == named)) return named;
    return filesTabId;
  }

  List<_Tab> get _tabs => [
    const _Tab(id: filesTabId, label: 'files'),
    for (var half in _controller?.declared ?? const <ComparisonHalf>[])
      _Tab(id: half.kind.name, label: half.kind.label, half: half),
  ];

  void _select(String id) {
    widget.shell.selectChangesTab(tab: id);
    _openSelectedTab();
  }

  /// Findings only, and merged across both halves: one preview that broke and
  /// one scenario that broke is two broken things, and which half they came
  /// from is the second question.
  Map<ComparedState, int> _counts(ComparisonController controller) {
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

  void _openSelectedTab() {
    var half = _tabs.firstWhere((tab) => tab.id == _tab).half;
    if (half != null) unawaited(_controller?.open(half.kind));
  }

  @override
  Widget build(BuildContext context) {
    // No comparison to be had — the files tab still is one, and it is the one
    // that needs nothing from us.
    if (_loading || _unavailable != null || _controller == null) {
      return Builder(builder: (context) => widget.files(context, false));
    }

    var controller = _controller!;
    var tabs = _tabs;
    var selected = tabs.firstWhere((tab) => tab.id == _tab);

    return Column(
      key: comparisonTabsKey,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _TabStrip(
          tabs: tabs,
          selected: selected.id,
          onSelect: _select,
          base: controller.environment.baseLabel,
          counts: _counts(controller),
        ),
        Expanded(
          child: selected.half == null
              ? Builder(builder: (context) => widget.files(context, true))
              : _HalfView(
                  controller: controller,
                  half: selected.half!,
                  settle: widget.shell.appContext.settle,
                  selected: widget.shell.address.segments.skip(1).isEmpty
                      ? null
                      : widget.shell.address.segments.skip(1).join('/'),
                  onSelect: (id) => widget.shell.selectChangesTab(
                    tab: selected.id,
                    segments: id.split('/'),
                  ),
                ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    widget.shell.removeListener(_onShell);
    widget.shell.appContext.settle.remove(this);
    _controller
      ?..removeListener(_onChange)
      ..dispose();
    super.dispose();
  }
}

class _Tab {
  const _Tab({required this.id, required this.label, this.half});

  final String id;
  final String label;

  /// Null for the file diff, which is not a comparison half — it needs no base
  /// checkout, costs nothing, and is built by the host.
  final ComparisonHalf? half;
}

/// `[ files ][ previews ][ scenarios ]`
///
/// **A tab says what it is, and nothing about what it would cost.** It used to
/// carry an estimate — *previews · 14 of 213* — on the reasoning that opening a
/// tab runs its half, so the price should be readable from outside it. Working
/// the price out turned out to cost about what the work costs, and it was paid
/// on arrival by everyone who opened Changes to read a diff. See
/// [ComparisonController].
class _TabStrip extends StatelessWidget {
  const _TabStrip({
    required this.tabs,
    required this.selected,
    required this.onSelect,
    required this.base,
    required this.counts,
  });

  final List<_Tab> tabs;
  final String selected;
  final void Function(String id) onSelect;

  /// What all three tabs are against.
  final String base;

  /// Findings across both halves, worst first.
  final Map<ComparedState, int> counts;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.line)),
      ),
      padding: const EdgeInsets.only(left: FwSpacing.xxxl, right: FwSpacing.xl),
      child: Row(
        children: [
          for (var tab in tabs)
            _TabButton(
              tab: tab,
              selected: tab.id == selected,
              onTap: () => onSelect(tab.id),
            ),
          const Spacer(),
          // **No title of its own.** The sidebar row says "Changes" and the
          // file diff writes its own header inside its tab; a third one over
          // the top of both said the same word twice on one screen. What is
          // left is the two things the strip is the only place for: what all
          // three tabs are against, and what they found between them.
          for (var entry in counts.entries)
            Padding(
              padding: const EdgeInsets.only(left: FwSpacing.xs),
              child: StateChip(entry.key, count: entry.value),
            ),
          const Gap(FwSpacing.md),
          Text(
            'against $base',
            style: context.type.micro.copyWith(color: colors.mut),
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
    // The one thing a tab still says about its half, and it only says it once
    // you have opened the thing that is running.
    var note = half?.stage == HalfStage.running ? 'running…' : null;

    return Tappable.builder(
      key: comparisonTabKey(tab.id),
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
                color: selected ? colors.ink : colors.mut,
              ),
            ),
            if (half?.stage == HalfStage.refused) ...[
              const Gap(FwSpacing.sm),
              Icon(Icons.error_outline, size: FwIconSize.xs, color: colors.red),
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
  const _HalfView({
    required this.controller,
    required this.half,
    required this.settle,
    required this.selected,
    required this.onSelect,
  });

  final ComparisonController controller;
  final ComparisonHalf half;
  final SettleRegistry settle;

  /// What the address names below the tab, or null.
  final String? selected;
  final ValueChanged<String> onSelect;

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
        // Nothing to point a stage at until the first verdict lands, and the
        // list would be an empty column beside an empty pane.
        if (half.rows.isEmpty && half.scenarios.isEmpty) {
          return _Working(
            half.isRunning ? 'Comparing…' : 'Nothing to compare yet.',
          );
        }
        return switch (half.kind) {
          ComparisonHalfKind.previews => PreviewsTab(
            half: half,
            store: CacheShotStore(controller.environment.shots),
            settle: settle,
            selected: selected,
            onSelect: onSelect,
          ),
          ComparisonHalfKind.scenarios => ScenariosTab(
            half: half,
            store: CacheShotStore(controller.environment.shots),
            settle: settle,
            selected: selected,
            onSelect: onSelect,
          ),
        };
    }
  }
}

class _Refusal extends StatelessWidget {
  const _Refusal(this.message);

  final String message;

  @override
  Widget build(BuildContext context) =>
      ErrorState(title: 'Not compared', message: message);
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
