import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../shell/worktree.dart';
import '../shell/worktree_filter.dart';
import '../ui/theme.dart';
import 'explorer_row.dart';
import 'facts.dart';
import 'facts_text.dart';

/// One worktree and everything known about it.
///
/// Pairs the shell's existing identity type with the facts layer rather than
/// inventing a third: `Worktree` stays the only thing that knows what a
/// checkout *is*.
class ExplorerEntry {
  const ExplorerEntry({
    required this.worktree,
    this.facts = const WorktreeFacts(),
    this.isOpen = false,
  });

  final Worktree worktree;
  final WorktreeFacts facts;

  /// Whether the shell holds a tab for it. The shell's business, not the facts
  /// layer's — passed in rather than probed.
  final bool isOpen;

  /// The label-priority stack, resolved.
  ///
  /// **Open question** (inherited from the 2026-05-18 plugin design, and this is
  /// the first surface where both are routinely present): an agent title and a
  /// PR title both want to be the name. The rule here is that a *live* agent
  /// wins — while it is working or waiting, its title is what the worktree is
  /// currently about — and the PR title wins otherwise.
  String get label {
    var agent = facts.agent.value;
    if (agent != null &&
        agent.title != null &&
        (agent.state == AgentState.working ||
            agent.state == AgentState.waiting)) {
      return agent.title!;
    }
    if (facts.forge.value?.title case var title?) return title;
    if (agent?.title case var title?) return title;
    return worktree.displayName;
  }

  int get branchLines => facts.git.value?.changes?.lines ?? 0;
}

/// How the list is ordered.
///
/// [activity] is the default, and deliberately **not** grouped open-first: the
/// worktree that needs you is most often the one that is *not* open — an agent
/// finished while you were elsewhere — and grouping by open-ness buries exactly
/// the row this screen exists to surface. Open-ness is a marker, not a section.
enum ExplorerSort {
  activity('activity'),
  needsYou('needs you'),
  name('name'),
  branch('branch');

  const ExplorerSort(this.label);
  final String label;
}

/// The explorer — `fw:///worktrees`.
///
/// A View: entries and callbacks in, no probing, no git, no clock of its own.
/// See `docs/superpowers/specs/2026-08-10-worktree-explorer-view-design.md`.
class WorktreeExplorerView extends StatefulWidget {
  const WorktreeExplorerView({
    super.key,
    required this.entries,
    required this.now,
    this.query = '',
    this.sort = ExplorerSort.activity,
    this.refreshedAt,
    this.isRefreshing = false,
    this.currentWorktreePath,
    this.onQueryChanged,
    this.onSortChanged,
    this.onRefresh,
    this.onOpen,
  });

  final List<ExplorerEntry> entries;
  final DateTime now;
  final String query;
  final ExplorerSort sort;
  final DateTime? refreshedAt;
  final bool isRefreshing;
  final String? currentWorktreePath;

  final ValueChanged<String>? onQueryChanged;
  final ValueChanged<ExplorerSort>? onSortChanged;
  final VoidCallback? onRefresh;
  final ValueChanged<ExplorerEntry>? onOpen;

  @override
  State<WorktreeExplorerView> createState() => _WorktreeExplorerViewState();
}

class _WorktreeExplorerViewState extends State<WorktreeExplorerView> {
  /// Which rows are showing their detail.
  ///
  /// **A set, not one at a time.** Comparing two checkouts is the reason this
  /// screen exists, and a detail that closed the moment you opened another one
  /// would turn the comparison into a memory test.
  final _expanded = <String>{};

  void _toggle(String path) => setState(
    () =>
        _expanded.contains(path) ? _expanded.remove(path) : _expanded.add(path),
  );

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    var rows = _filtered();
    // The busiest row sets the scale every bar is drawn against — which is what
    // makes the widths mean something relative to each other.
    var busiest = rows.fold(0, (max, r) => math.max(max, r.$1.branchLines));

    // Decided once for the whole list, so the cells stay in line. See
    // `WorktreeRow.showAgent`.
    var showAgent = rows.any(
      (r) =>
          (r.$1.facts.agent.value?.state ?? AgentState.none) != AgentState.none,
    );
    var showForge = rows.any((r) => r.$1.facts.forge.hasValue);

    return ColoredBox(
      color: colors.bg,
      child: Column(
        children: [
          _Header(
            total: widget.entries.length,
            shown: rows.length,
            query: widget.query,
            sort: widget.sort,
            refreshedAt: widget.refreshedAt,
            isRefreshing: widget.isRefreshing,
            now: widget.now,
            onQueryChanged: widget.onQueryChanged,
            onSortChanged: widget.onSortChanged,
            onRefresh: widget.onRefresh,
          ),
          Expanded(
            child: rows.isEmpty
                ? const Center(child: NoWorktreeMatches())
                : ListView.builder(
                    itemCount: rows.length,
                    itemBuilder: (context, i) {
                      var (entry, match) = rows[i];
                      var worktree = entry.worktree;
                      return WorktreeRow(
                        // Identity, so a row that moves takes its own hover and
                        // expansion with it instead of inheriting the state of
                        // whatever used to sit at this index.
                        key: ValueKey(worktree.path),
                        label: entry.label,
                        branch: worktree.branch,
                        isMain: worktree.isMain,
                        isOpen: entry.isOpen,
                        isCurrent: worktree.path == widget.currentWorktreePath,
                        facts: entry.facts,
                        now: widget.now,
                        match: match,
                        scale: busiest == 0 ? 0 : entry.branchLines / busiest,
                        showAgent: showAgent,
                        showForge: showForge,
                        expanded: _expanded.contains(worktree.path),
                        path: worktree.path,
                        onToggleExpand: () => _toggle(worktree.path),
                        onOpen: () => widget.onOpen?.call(entry),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  List<(ExplorerEntry, FilterMatch?)> _filtered() {
    var rows = <(ExplorerEntry, FilterMatch?)>[];
    for (var entry in widget.entries) {
      if (widget.query.trim().isEmpty) {
        rows.add((entry, null));
        continue;
      }
      var match = matchWorktreeFilter(widget.query, [
        entry.label,
        entry.worktree.branch,
        entry.worktree.name,
      ]);
      if (match != null) rows.add((entry, match));
    }
    rows.sort((a, b) => _compare(a.$1, b.$1));
    return rows;
  }

  /// **A total order, in every mode.** `List.sort` is not stable in Dart, so a
  /// comparator that returns 0 for two rows lets them trade places on any
  /// rebuild — and with watchers running, rebuilds happen every couple of
  /// seconds. Every mode therefore ends at the path, which nothing can change.
  int _compare(ExplorerEntry a, ExplorerEntry b) {
    var first = switch (widget.sort) {
      // By the age the row prints — see [activityAge]. Sorting by the exact
      // timestamp made two working agents swap on every keystroke of theirs.
      ExplorerSort.activity => _age(a).compareTo(_age(b)),
      // Then by freshness within each half, so "needs you" is a partition of
      // the activity order rather than a different list.
      ExplorerSort.needsYou =>
        _needs(b).compareTo(_needs(a)) != 0
            ? _needs(b).compareTo(_needs(a))
            : _age(a).compareTo(_age(b)),
      ExplorerSort.name => a.label.toLowerCase().compareTo(
        b.label.toLowerCase(),
      ),
      ExplorerSort.branch => (a.worktree.branch ?? '').compareTo(
        b.worktree.branch ?? '',
      ),
    };
    return first != 0 ? first : a.worktree.path.compareTo(b.worktree.path);
  }

  int _needs(ExplorerEntry e) => e.facts.needsYou ? 1 : 0;

  Duration _age(ExplorerEntry e) => activityAge(e.facts, widget.now);
}

class _Header extends StatelessWidget {
  const _Header({
    required this.total,
    required this.shown,
    required this.query,
    required this.sort,
    required this.refreshedAt,
    required this.isRefreshing,
    required this.now,
    required this.onQueryChanged,
    required this.onSortChanged,
    required this.onRefresh,
  });

  final int total;
  final int shown;
  final String query;
  final ExplorerSort sort;
  final DateTime? refreshedAt;
  final bool isRefreshing;
  final DateTime now;
  final ValueChanged<String>? onQueryChanged;
  final ValueChanged<ExplorerSort>? onSortChanged;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    return Container(
      // Matched to the rows below, so the title sits over the column of names
      // and the refresh button over the column of row controls.
      padding: const EdgeInsets.fromLTRB(
        explorerInsetLeft,
        FwSpacing.lg,
        explorerInsetRight,
        FwSpacing.lg,
      ),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.line)),
      ),
      child: Row(
        children: [
          Text('Worktrees', style: context.type.heading),
          const Gap(FwSpacing.md),
          Text(
            shown == total ? '$total' : '$shown of $total',
            style: context.type.caption.copyWith(color: colors.mut2),
          ),
          const Gap(FwSpacing.xxl),
          // Absorbs the slack rather than claiming a fixed 240 beside a
          // `Spacer` — which overflows the moment the window is narrower than
          // the sum of everything on this row, and a header that overflows is
          // the first thing anyone sees.
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 240),
                child: _Filter(query: query, onChanged: onQueryChanged),
              ),
            ),
          ),
          const Gap(FwSpacing.lg),
          Text('Sort', style: context.type.micro.copyWith(color: colors.mut3)),
          const Gap(FwSpacing.sm),
          _SortMenu(sort: sort, onChanged: onSortChanged),
          const Gap(FwSpacing.xl),
          // The one progress indicator on the screen. Cells go dim; they never
          // grow spinners.
          if (isRefreshing)
            Text(
              'Refreshing…',
              style: context.type.micro.copyWith(color: colors.mut2),
            )
          else if (refreshedAt != null)
            Text(
              _agoLabel(refreshedAt!, now),
              style: context.type.micro.copyWith(color: colors.mut3),
            ),
          const Gap(FwSpacing.sm),
          IconButton(
            onPressed: onRefresh,
            icon: Icon(Icons.refresh, size: 15, color: colors.mut),
            tooltip: 'Refresh every worktree',
            constraints: const BoxConstraints.tightFor(width: 26, height: 26),
            padding: EdgeInsets.zero,
          ),
        ],
      ),
    );
  }

  static String _agoLabel(DateTime then, DateTime now) {
    var d = now.difference(then);
    if (d.inSeconds < 60) return '${d.inSeconds}s ago';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    return '${d.inHours}h ago';
  }
}

/// The filter box, and **the one controller on this screen**.
///
/// It has to be stateful. A `TextEditingController` built in `build` is a new
/// controller on every rebuild, which throws away the selection and the composing
/// region — and once the filesystem watchers landed, this screen rebuilds every
/// couple of seconds whether or not anybody is typing, so the field became
/// unusable: the caret jumped to the start mid-word and the keyboard appeared to
/// lose the field.
///
/// The controller therefore outlives the builds, and the incoming [query] is
/// pushed into it **only when it actually differs** — a blind assignment on every
/// rebuild would move the caret to the end for the same reason, one keystroke
/// later.
class _Filter extends StatefulWidget {
  const _Filter({required this.query, required this.onChanged});

  final String query;
  final ValueChanged<String>? onChanged;

  @override
  State<_Filter> createState() => _FilterState();
}

class _FilterState extends State<_Filter> {
  late final _controller = TextEditingController(text: widget.query);

  @override
  void didUpdateWidget(_Filter old) {
    super.didUpdateWidget(old);
    // Only when something *else* changed the query — a cleared filter, an
    // address that carried one. Typing round-trips through `onChanged` and comes
    // back identical, and this must not touch the field then.
    if (widget.query != _controller.text) {
      _controller.value = TextEditingValue(
        text: widget.query,
        selection: TextSelection.collapsed(offset: widget.query.length),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    OutlineInputBorder border(Color color) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(context.radii.radius),
      borderSide: BorderSide(color: color),
    );
    // Width is the caller's business — it caps this at 240 and lets it shrink
    // below that on a narrow window.
    return TextField(
      controller: _controller,
      onChanged: widget.onChanged,
      style: context.type.bodySmall,
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: colors.panel,
        prefixIcon: Icon(Icons.search, size: 14, color: colors.mut3),
        prefixIconConstraints: const BoxConstraints.tightFor(
          width: 28,
          height: 20,
        ),
        hintText: 'Filter',
        hintStyle: context.type.bodySmall.copyWith(color: colors.mut3),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: FwSpacing.md,
          vertical: FwSpacing.sm,
        ),
        border: border(colors.line),
        enabledBorder: border(colors.line),
        focusedBorder: border(colors.accent),
      ),
    );
  }
}

class _SortMenu extends StatelessWidget {
  const _SortMenu({required this.sort, required this.onChanged});

  final ExplorerSort sort;
  final ValueChanged<ExplorerSort>? onChanged;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    return MenuAnchor(
      menuChildren: [
        for (var value in ExplorerSort.values)
          MenuItemButton(
            onPressed: () => onChanged?.call(value),
            child: Text(value.label, style: context.type.bodySmall),
          ),
      ],
      builder: (context, controller, child) => TextButton(
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
        style: TextButton.styleFrom(
          minimumSize: Size.zero,
          padding: const EdgeInsets.symmetric(horizontal: FwSpacing.sm),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              sort.label,
              style: context.type.bodySmall.copyWith(color: colors.ink),
            ),
            Icon(Icons.expand_more, size: 14, color: colors.mut2),
          ],
        ),
      ),
    );
  }
}
