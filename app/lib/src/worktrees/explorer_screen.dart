import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../shell/worktree.dart';
import '../shell/worktree_filter.dart';
import '../ui/theme.dart';
import 'explorer_row.dart';
import 'facts.dart';

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
class WorktreeExplorerView extends StatelessWidget {
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
    this.onSelect,
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
  final ValueChanged<ExplorerEntry>? onSelect;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    var rows = _filtered();
    // The busiest row sets the scale every bar is drawn against — which is what
    // makes the widths mean something relative to each other.
    var busiest = rows.fold(0, (max, r) => math.max(max, r.$1.branchLines));

    return ColoredBox(
      color: colors.bg,
      child: Column(
        children: [
          _Header(
            total: entries.length,
            shown: rows.length,
            query: query,
            sort: sort,
            refreshedAt: refreshedAt,
            isRefreshing: isRefreshing,
            now: now,
            onQueryChanged: onQueryChanged,
            onSortChanged: onSortChanged,
            onRefresh: onRefresh,
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
                        label: entry.label,
                        branch: worktree.branch,
                        isMain: worktree.isMain,
                        isOpen: entry.isOpen,
                        isCurrent: worktree.path == currentWorktreePath,
                        facts: entry.facts,
                        now: now,
                        match: match,
                        scale: busiest == 0 ? 0 : entry.branchLines / busiest,
                        onTap: () => onSelect?.call(entry),
                        onOpen: () => onOpen?.call(entry),
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
    for (var entry in entries) {
      if (query.trim().isEmpty) {
        rows.add((entry, null));
        continue;
      }
      var match = matchWorktreeFilter(query, [
        entry.label,
        entry.worktree.branch,
        entry.worktree.name,
      ]);
      if (match != null) rows.add((entry, match));
    }
    rows.sort((a, b) => _compare(a.$1, b.$1));
    return rows;
  }

  int _compare(ExplorerEntry a, ExplorerEntry b) => switch (sort) {
    ExplorerSort.activity => _activityOf(b).compareTo(_activityOf(a)),
    ExplorerSort.needsYou => _needs(b).compareTo(_needs(a)),
    ExplorerSort.name => a.label.toLowerCase().compareTo(b.label.toLowerCase()),
    ExplorerSort.branch => (a.worktree.branch ?? '').compareTo(
      b.worktree.branch ?? '',
    ),
  };

  int _needs(ExplorerEntry e) => e.facts.needsYou ? 1 : 0;

  int _activityOf(ExplorerEntry e) =>
      e.facts.activity.value?.at.millisecondsSinceEpoch ?? 0;
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
      padding: const EdgeInsets.fromLTRB(
        FwSpacing.xl,
        FwSpacing.lg,
        FwSpacing.lg,
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
          _Filter(query: query, onChanged: onQueryChanged),
          const Spacer(),
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

class _Filter extends StatelessWidget {
  const _Filter({required this.query, required this.onChanged});

  final String query;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    OutlineInputBorder border(Color color) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(context.radii.radius),
      borderSide: BorderSide(color: color),
    );
    return SizedBox(
      width: 240,
      child: TextField(
        controller: TextEditingController(text: query),
        onChanged: onChanged,
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
