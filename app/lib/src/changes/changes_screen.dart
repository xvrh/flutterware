import 'dart:async';

import 'package:flutter/material.dart';

import '../shell/worktree.dart';
import '../ui/theme.dart';
import 'change_rows.dart';
import 'change_set.dart';
import 'changes_config_cache.dart';
import 'changes_controller.dart';
import 'changes_tree.dart';
import 'diff_lines.dart';
import 'diff_view.dart';
import 'hunk_ruler.dart';
import 'patch_index.dart';
import 'ranking.dart';

/// The changes screen's root, so a test can scope to it.
const changesScreenKey = Key('changes-screen');

/// The index of paths, on the left.
const changesListKey = Key('changes-list');

/// The selected file's diff, on the right.
const changesFileKey = Key('changes-file');

/// **`fw:///worktrees/<worktree>/changes`** — what this checkout has changed
/// against its base branch, committed and uncommitted together.
///
/// Deliberately not a plugin, and unlike the config screen not merely because
/// of what it is *about*: it reads git rather than the project, so it renders
/// for a worktree **nobody has opened**. A plugin needs a resolved config and a
/// session; the checkout you most want to look at is the one an agent has been
/// working in while you were elsewhere.
///
/// **Master and detail.** Left: every path in the delta, ranked, and nothing
/// else. Right: the one file you picked. They used to be a single list of file
/// rows that expanded to inject their own diff, which made the surface you
/// navigate with and the surface you read the same one — every complaint about
/// this screen came out of that, from "clicking a file scrolls but does not
/// open it" to a live update sliding the lines under your eyes.
///
/// A churn map and a directory tree were the other two ways in. Both are gone:
/// three navigation surfaces for one list of files is two too many, and the
/// ranked index says what they said, with names on it.
class ChangesScreen extends StatefulWidget {
  const ChangesScreen({
    required this.worktree,
    this.isOpen = false,
    this.repoRoot,
    this.initialPath,
    this.onPathChanged,
    this.gitMoved,
    this.load,
    this.live = true,
    super.key,
  });

  final Worktree worktree;

  /// The main checkout, which the repository-wide cache holding this project's
  /// ranking rules is keyed by. Null ranks by built-in defaults.
  final String? repoRoot;

  /// Whether the checkout has a tab. Only affects what the empty state says.
  final bool isOpen;

  /// The file the address names, expanded and scrolled to on arrival.
  ///
  /// **Segments after the plugin id belong to the panel**, which is the rule
  /// every other panel in the shell already follows. Here it means a file's
  /// diff has a name you can paste: `fw:///worktrees/<n>/changes/lib/a.dart`.
  final String? initialPath;

  /// Writes the expansion back into the address, so what you are looking at is
  /// what the bar says and what a link would reopen.
  final ValueChanged<String?>? onPathChanged;

  /// The shell's repository-wide git signal. Staging and committing write a
  /// linked worktree's index under the *main* checkout, so no watch on this
  /// working tree can see them — and committing is exactly what clears the
  /// `uncommitted` marks this screen draws.
  final Stream<void>? gitMoved;

  /// Whether to watch the checkout. Off for a test that would otherwise put a
  /// recursive watch on a real temporary directory to prove something else.
  final bool live;

  /// Injected for widget tests, which must neither spawn an isolate nor need a
  /// repository.
  final Future<ChangeSet> Function(String path)? load;

  @override
  State<ChangesScreen> createState() => _ChangesScreenState();
}

class _ChangesScreenState extends State<ChangesScreen> {
  late ChangesController _changes;

  /// One controller each, because they are two independent readings. The index
  /// stays where you left it while you read; the body starts at the top of
  /// whatever you just picked.
  final _index = ScrollController();
  final _body = ScrollController();

  /// The path the right pane is showing. **One, not a set** — the screen used
  /// to expand any number of files inline, which is what made the list you
  /// navigate with and the thing you read the same surface.
  String? _selected;

  /// Rebuilt whenever the patch is, which is what throws the decoded text of
  /// the previous one away.
  HunkLineCache? _lines;
  ChangeSet? _cachedFor;

  var _query = '';

  /// **The lenses.** Two toggles over the index, each with a count.
  ///
  /// *Just changed* is what has moved while this screen has been open — an
  /// agent's current sentence, not its paragraph. It replaced an *uncommitted*
  /// lens, which was the wrong question: committed-versus-not is a distinction
  /// that matters when a person is deciding what to push, and this screen is
  /// for watching something that commits on its own schedule. "What is it doing
  /// **now**" is the question that was actually being asked.
  ///
  /// *Low-signal* is what the ranking demoted.
  ///
  /// Between them and the pinned band above, the three questions a fifty-file
  /// branch raises: what a **rule** says matters, what is **moving**, and what
  /// is **skippable**.
  var _justChangedOnly = false;

  /// Whether the noise drawer is open. **Off by default and remembered for the
  /// session**, not persisted: the whole value of the drawer is that the
  /// screen opens on the signal.
  var _noiseOpen = false;

  @override
  void initState() {
    super.initState();
    _selected = widget.initialPath;
    _start();
  }

  @override
  void didUpdateWidget(ChangesScreen old) {
    super.didUpdateWidget(old);
    if (old.worktree.path != widget.worktree.path) {
      _changes.dispose();
      _selected = widget.initialPath;
      _start();
      return;
    }
    // An address that arrived from outside — pasted, or followed from the
    // explorer — selects what it names.
    if (widget.initialPath case var path?
        when path != old.initialPath && path != _selected) {
      _show(path);
    }
  }

  void _start() {
    _changes = ChangesController(
      worktreePath: widget.worktree.path,
      repoRoot: widget.repoRoot,
      load: widget.load,
    )..addListener(_onChanged);
    // **Watching is scoped to this screen being mounted**, which is what makes
    // one recursive watch affordable: the explorer refuses fourteen of them,
    // and this is one, on the checkout you are looking at, for as long as you
    // are looking at it.
    if (widget.live) _changes.watch(gitMoved: widget.gitMoved);
    unawaited(_changes.refresh());
  }

  void _onChanged() => setState(() {});

  @override
  void dispose() {
    _changes
      ..removeListener(_onChanged)
      ..dispose();
    _index.dispose();
    _body.dispose();
    super.dispose();
  }

  HunkLineCache _linesFor(ChangeSet set) {
    if (!identical(_cachedFor, set)) {
      _cachedFor = set;
      _lines = HunkLineCache(set.patch);
    }
    return _lines!;
  }

  /// Null when nothing is narrowing the index at all.
  ///
  /// The typed query and the lenses compose by intersection, so `motion` plus
  /// *just changed* means both, which is what anybody would expect of two
  /// controls sitting next to each other.
  Set<String>? _visible(ChangeSet set) {
    Set<String>? visible;
    if (_query.trim().isNotEmpty) {
      visible = pathsMatching([
        ...set.changed.map((f) => f.path),
        ...set.untracked.map((e) => e.path),
      ], _query);
    }
    if (_justChangedOnly) {
      var moved = _changes.moved;
      visible = visible == null ? {...moved} : visible.intersection(moved);
    }
    return visible;
  }

  /// Shows [path] in the right pane, from the top.
  ///
  /// **The body scrolls back to the start.** Two files' diffs share a scroll
  /// offset only by accident, and arriving four hundred lines into a file you
  /// just picked is the sort of thing that reads as the app losing its place.
  void _show(String? path) {
    if (path == _selected) return;
    setState(() => _selected = path);
    if (_body.hasClients) _body.jumpTo(0);
    widget.onPathChanged?.call(path);
  }

  /// What the right pane is showing, and what it falls back to.
  ///
  /// **Nothing is auto-selected.** The claim this screen makes is that it knows
  /// what to look at first, so opening straight into the top-ranked file would
  /// be tempting — and wrong: the first thing you want is the *shape* of what
  /// an agent did, which is the index. Reading a file is the second question,
  /// and it is one you should have asked.
  FileChange? _selectedFile(ChangeSet set) {
    if (_selected case var path?) {
      return set.changed.where((f) => f.path == path).firstOrNull;
    }
    return null;
  }

  UntrackedEntry? _selectedUntracked(ChangeSet set) {
    if (_selected case var path?) {
      return set.untracked.where((e) => e.path == path).firstOrNull;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    var set = _changes.value;
    var rows = set == null
        ? const <ChangeRow>[]
        : buildIndexRows(
            set,
            selected: _selected,
            visible: _visible(set),
            noiseOpen: _noiseOpen,
          );

    return Column(
      key: changesScreenKey,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(
          worktree: widget.worktree,
          set: set,
          isLoading: _changes.isLoading,
          live: widget.live,
          isWatching: _changes.isWatching,
          readAt: _changes.readAt,
          failure: _changes.failure,
          onRefresh: () => unawaited(_changes.refresh()),
        ),
        Divider(height: 1, color: context.colors.line),
        Expanded(
          child: set == null
              ? const SizedBox.shrink()
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: _indexWidth,
                      child: _IndexPane(
                        set: set,
                        rows: rows,
                        controller: _index,
                        query: _query,
                        selected: _selected,
                        visible: _visible(set),
                        noiseOpen: _noiseOpen,
                        justChanged: _changes.moved,
                        justChangedOnly: _justChangedOnly,
                        onQuery: (q) => setState(() => _query = q),
                        onSelect: _show,
                        onToggleNoise: () =>
                            setState(() => _noiseOpen = !_noiseOpen),
                        onToggleJustChanged: () => setState(
                          () => _justChangedOnly = !_justChangedOnly,
                        ),
                      ),
                    ),
                    VerticalDivider(width: 1, color: context.colors.line),
                    Expanded(
                      child: _FilePane(
                        file: _selectedFile(set),
                        untracked: _selectedUntracked(set),
                        missing: _selected,
                        uncommitted: set.uncommitted,
                        lines: _linesFor(set),
                        controller: _body,
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }

  /// Wider than the tree it replaced, because it now carries the whole index —
  /// a filename, its directory and its counts on one row.
  static const _indexWidth = 320.0;
}

class _Header extends StatelessWidget {
  const _Header({
    required this.worktree,
    required this.set,
    required this.isLoading,
    required this.live,
    required this.isWatching,
    required this.readAt,
    required this.failure,
    required this.onRefresh,
  });

  final Worktree worktree;
  final ChangeSet? set;
  final bool isLoading;
  final bool live;
  final bool isWatching;
  final DateTime? readAt;
  final Object? failure;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        FwSpacing.xxl,
        FwSpacing.xl,
        FwSpacing.xxl,
        FwSpacing.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Changes', style: context.type.pageTitle),
                    const Gap(FwSpacing.xs),
                    // **The identity is drawn before anything is loaded.** A
                    // screen that opens on a spinner tells you nothing you did
                    // not already know.
                    Text(
                      worktree.displayName,
                      style: context.type.caption.copyWith(color: colors.mut),
                    ),
                  ],
                ),
              ),
              // **What makes the liveness believable.** A screen that updates
              // by itself and never says so is indistinguishable from one that
              // has stopped — and the one thing worse than a stale screen is a
              // stale screen you trust.
              _Watching(live: live, isWatching: isWatching, readAt: readAt),
              const Gap(FwSpacing.sm),
              IconButton(
                onPressed: isLoading ? null : onRefresh,
                tooltip: 'Read this checkout again',
                icon: Icon(
                  Icons.refresh,
                  size: 18,
                  color: isLoading ? colors.mut3 : colors.mut,
                ),
              ),
            ],
          ),
          const Gap(FwSpacing.md),
          _Summary(set),
          if (failure case var why?) ...[
            const Gap(FwSpacing.md),
            _Note('Could not read this checkout: $why'),
          ],
          if (set case var it?) ...[
            if (it.baseSource == BaseSource.none) ...[
              const Gap(FwSpacing.md),
              _Note(
                'No base branch: none of origin/HEAD, main or master resolved '
                'here, so nothing is compared against a guess. Showing '
                'uncommitted work only.',
              ),
            ],
            if (it.refusal case var why?) ...[
              const Gap(FwSpacing.md),
              _Note('$why'),
            ],
            // Ranking by rules that have since been edited is worth one line.
            // Nothing is said in the fresh case: a screen that narrates its
            // cache on every load is one whose important message goes unread.
            if (ResolvedChangesConfig(null, it.configState).notice
                case var why?) ...[
              const Gap(FwSpacing.md),
              _Note(why),
            ],
            if (it.isEmpty) ...[
              const Gap(FwSpacing.md),
              _Note('Nothing changed against ${it.base ?? 'the base'}.'),
            ],
          ],
        ],
      ),
    );
  }
}

/// Says whether the screen is still listening — three words, no timer.
///
/// **Deliberately not an age that counts up.** "14s ago" needs a ticker
/// rebuilding the header every second for a number that means nothing on a
/// screen which refreshes when the checkout moves and not otherwise: on a quiet
/// worktree it would climb to "40m ago" and read as broken. What you actually
/// want to know is whether it will still notice, so that is what it says, and
/// the exact clock time of the last read is in the tooltip for the one moment
/// you want it.
///
/// The failed case earns its own words. A watch can be refused — the checkout
/// was deleted under us, or the system is out of watches — and *that* is the
/// state where the screen quietly stops being true.
///
/// **It says nothing about a read in progress**, which it tried to and should
/// not: a probe is 60–195 ms, so the word would be a flicker nobody can read,
/// and on the one load slow enough to see — the first — the summary below is
/// already saying `Reading…`. Two of that word in one header, six pixels apart,
/// meaning different things.
class _Watching extends StatelessWidget {
  const _Watching({
    required this.live,
    required this.isWatching,
    required this.readAt,
  });

  final bool live;
  final bool isWatching;
  final DateTime? readAt;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    if (!live) return const SizedBox.shrink();
    var stale = !isWatching;
    return Tooltip(
      message: stale
          ? 'This checkout is not being watched — refresh to read it again'
          : 'Re-read whenever this checkout changes'
                '${readAt == null ? '' : '\nLast read at ${_clock(readAt!)}'}',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: stale ? colors.mut3 : colors.grn,
            ),
          ),
          const Gap(FwSpacing.xs),
          Text(
            stale ? 'Not watching' : 'Watching',
            style: context.type.micro.copyWith(
              color: stale ? colors.mut2 : colors.mut3,
            ),
          ),
        ],
      ),
    );
  }

  static String _clock(DateTime at) =>
      '${at.hour.toString().padLeft(2, '0')}:'
      '${at.minute.toString().padLeft(2, '0')}:'
      '${at.second.toString().padLeft(2, '0')}';
}

class _Summary extends StatelessWidget {
  const _Summary(this.set);

  final ChangeSet? set;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    var style = context.type.bodySmall;
    if (set case var it?) {
      var uncommitted = it.changed
          .where((f) => it.uncommitted.contains(f.path))
          .length;
      return Wrap(
        spacing: FwSpacing.md,
        children: [
          Text('${it.changed.length} files', style: style),
          Text('+${it.added}', style: style.copyWith(color: colors.grn)),
          Text('-${it.removed}', style: style.copyWith(color: colors.red)),
          if (uncommitted > 0)
            Text(
              '$uncommitted uncommitted',
              style: style.copyWith(color: colors.amber),
            ),
          // The base and where it came from, always — the one thing worse than
          // no base is the wrong one presented as fact.
          Text(switch (it.baseSource) {
            BaseSource.none => 'no base',
            BaseSource.configured => 'base ${it.base} (configured)',
            BaseSource.inferred => 'base ${it.base} (inferred)',
          }, style: style.copyWith(color: colors.mut2)),
        ],
      );
    }
    return Text('Reading…', style: style.copyWith(color: colors.mut2));
  }
}

/// The **index**: filter, then every path in the delta, ranked.
///
/// Navigation only. Nothing here is content, which is the whole point of the
/// split — the list stays where you left it while you read, and a live re-probe
/// that adds a file changes this column without moving a line of what is open.
/// The **index**: filter, what to look at first, and the tree of everything
/// else.
///
/// Navigation only. Nothing here is content, which is the whole point of the
/// split — the list stays where you left it while you read, and a live re-probe
/// that adds a file changes this column without moving a line of what is open.
///
/// **Two orderings, both kept.** *Look here first* is an alert: short, in rank
/// order, and pinned to the top where it cannot be missed. Everything else is
/// navigation, and navigation wants structure, so it is a directory tree —
/// ordered by weight, so an agent's heaviest module is still the first thing
/// under it. Tabs were the other way to reconcile the two, and a tab hides the
/// alert half the time.
class _IndexPane extends StatelessWidget {
  const _IndexPane({
    required this.set,
    required this.rows,
    required this.controller,
    required this.query,
    required this.selected,
    required this.onQuery,
    required this.onSelect,
    required this.onToggleNoise,
    required this.onToggleJustChanged,
    required this.noiseOpen,
    required this.justChanged,
    required this.justChangedOnly,
    required this.visible,
  });

  final ChangeSet set;

  /// The flat parts: pinned, the noise drawer, untracked.
  final List<ChangeRow> rows;

  final ScrollController controller;
  final String query;
  final String? selected;
  final ValueChanged<String> onQuery;
  final ValueChanged<String> onSelect;
  final VoidCallback onToggleNoise;
  final VoidCallback onToggleJustChanged;
  final bool noiseOpen;
  final Set<String> justChanged;
  final bool justChangedOnly;
  final Set<String>? visible;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    var tree = buildTree(
      treeFiles(set, visible: visible, noiseOpen: noiseOpen),
    );
    var nothing = rows.isEmpty && tree.totalFiles == 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(FwSpacing.md),
          child: TextField(
            onChanged: onQuery,
            style: context.type.bodySmall,
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Filter paths',
              hintStyle: context.type.bodySmall.copyWith(color: colors.mut3),
              prefixIcon: Icon(Icons.search, size: 16, color: colors.mut3),
              prefixIconConstraints: const BoxConstraints(minWidth: 26),
              border: const OutlineInputBorder(),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: FwSpacing.sm,
                vertical: FwSpacing.sm,
              ),
            ),
          ),
        ),
        _LensRow(
          set: set,
          noiseOpen: noiseOpen,
          justChanged: justChanged,
          justChangedOnly: justChangedOnly,
          onToggleNoise: onToggleNoise,
          onToggleJustChanged: onToggleJustChanged,
        ),
        Expanded(
          child: nothing
              ? Center(
                  child: Text(
                    set.changed.isEmpty
                        ? 'Nothing to show.'
                        : 'Nothing matches.',
                    style: context.type.bodySmall.copyWith(color: colors.mut2),
                  ),
                )
              // **Not virtualised, deliberately.** The index is the file count,
              // not the line count — a 228-file branch is a few hundred rows,
              // where the list it replaced could be four thousand. A tree that
              // remembers which folders are open cannot be rebuilt by index
              // anyway.
              : ListView(
                  key: changesListKey,
                  controller: controller,
                  children: [
                    if (!set.attentionConfigured) const _NoRulesYet(),
                    for (var row in rows) _flat(context, row),
                    if (tree.totalFiles > 0)
                      _TreeNodeView(
                        node: tree,
                        depth: 0,
                        selected: selected,
                        uncommitted: set.uncommitted,
                        ranking: set.ranking,
                        onSelect: onSelect,
                        // Open at the top, shut further down: a branch that
                        // touched one module wants that module visible, and a
                        // repo of forty directories does not want all of them
                        // unfolded at once.
                        openDepth: 1,
                      ),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _flat(BuildContext context, ChangeRow row) => switch (row) {
    SectionRow(:var label, :var detail) => Padding(
      padding: const EdgeInsets.fromLTRB(
        FwSpacing.md,
        FwSpacing.lg,
        FwSpacing.md,
        FwSpacing.xs,
      ),
      child: Row(
        children: [
          Flexible(
            child: Text(
              label,
              style: context.type.caption,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (detail case var it?) ...[
            const Gap(FwSpacing.sm),
            Text(
              it,
              style: context.type.micro.copyWith(color: context.colors.mut3),
            ),
          ],
        ],
      ),
    ),
    FileRow(:var file, :var selected, :var uncommitted, :var reason) =>
      IndexFileRow(
        file: file,
        selected: selected,
        uncommitted: uncommitted,
        reason: reason,
        onTap: () => onSelect(file.path),
      ),
    UntrackedRow(:var entry, :var selected) => IndexUntrackedRow(
      entry: entry,
      selected: selected,
      onTap: entry.isDirectory ? null : () => onSelect(entry.path),
    ),
    // The body's rows never reach the index.
    HunkRow() || DiffLineRow() || FileNoticeRow() => const SizedBox.shrink(),
  };
}

/// Said once, quietly, to a project that has never written an `attention:`
/// rule.
///
/// **There are no built-in ones**, so without this the band is simply absent
/// and the whole ranking reads as a feature that does not work. A project that
/// *has* rules and matched none of them is told nothing, because it already
/// knows they exist.
class _NoRulesYet extends StatelessWidget {
  const _NoRulesYet();

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        FwSpacing.md,
        FwSpacing.xs,
        FwSpacing.md,
        FwSpacing.md,
      ),
      child: Text(
        'Nothing is pinned. Name what matters here with '
        'fw.changes(ChangesConfig(attention: [...])) in tool/flutterware.dart.',
        style: context.type.micro.copyWith(color: colors.mut3),
      ),
    );
  }
}

/// The lenses, drawn only when they would say something.
///
/// A `0 uncommitted` chip on a branch with nothing uncommitted is a control
/// that does nothing, which is worse than no control — the same rule the
/// section headings follow.
class _LensRow extends StatelessWidget {
  const _LensRow({
    required this.set,
    required this.noiseOpen,
    required this.justChanged,
    required this.justChangedOnly,
    required this.onToggleNoise,
    required this.onToggleJustChanged,
  });

  final ChangeSet set;
  final bool noiseOpen;
  final Set<String> justChanged;
  final bool justChangedOnly;
  final VoidCallback onToggleNoise;
  final VoidCallback onToggleJustChanged;

  @override
  Widget build(BuildContext context) {
    // **It appears when it becomes true, which is exactly when it is useful.**
    // Nothing has moved on arrival, so there is no chip; the first time the
    // agent writes something, one shows up saying so.
    var fresh = justChanged.length;
    var noise = set.ordered(RankTier.noise).length;
    if (fresh == 0 && noise == 0) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        FwSpacing.md,
        0,
        FwSpacing.md,
        FwSpacing.sm,
      ),
      child: Wrap(
        spacing: FwSpacing.xs,
        runSpacing: FwSpacing.xs,
        children: [
          if (fresh > 0)
            IndexLens(
              label: 'just changed',
              count: fresh,
              on: justChangedOnly,
              onTap: onToggleJustChanged,
            ),
          if (noise > 0)
            IndexLens(
              label: 'low-signal',
              count: noise,
              on: noiseOpen,
              onTap: onToggleNoise,
            ),
        ],
      ),
    );
  }
}

/// One directory, and everything under it.
///
/// Stateful for the same reason the version before the rewrite was: which
/// folders you have opened is yours, and it has to survive the rebuild that a
/// live re-probe causes every couple of seconds.
class _TreeNodeView extends StatefulWidget {
  const _TreeNodeView({
    required this.node,
    required this.depth,
    required this.selected,
    required this.uncommitted,
    required this.ranking,
    required this.onSelect,
    required this.openDepth,
  });

  final TreeNode node;
  final int depth;
  final String? selected;
  final Set<String> uncommitted;

  /// So a pinned file can say, where it lives, what pinned it.
  final Ranking ranking;

  final ValueChanged<String> onSelect;
  final int openDepth;

  @override
  State<_TreeNodeView> createState() => _TreeNodeViewState();
}

class _TreeNodeViewState extends State<_TreeNodeView> {
  /// `<=`, not `<`: depth 0 is the root, which is the tree rather than a row in
  /// it, so the first directory anybody sees is at depth 1. Off by that one and
  /// every top-level folder opens shut, which looks exactly like an empty
  /// index.
  late var _open = widget.depth <= widget.openDepth;

  @override
  Widget build(BuildContext context) {
    var node = widget.node;
    var colors = context.colors;
    // The root is the tree, not a row in it.
    var isRoot = widget.depth == 0 && node.path.isEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!isRoot)
          InkWell(
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: EdgeInsets.only(
                left: FwSpacing.md + (widget.depth - 1) * FwSpacing.lg,
                right: FwSpacing.md,
                top: FwSpacing.xxs,
                bottom: FwSpacing.xxs,
              ),
              child: Row(
                children: [
                  Icon(
                    _open ? Icons.expand_more : Icons.chevron_right,
                    size: 14,
                    color: colors.mut3,
                  ),
                  Expanded(
                    child: Text(
                      node.name,
                      style: context.type.bodySmall.copyWith(color: colors.mut),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const Gap(FwSpacing.xs),
                  Text(
                    '${node.totalFiles}',
                    style: context.type.micro.copyWith(color: colors.mut3),
                  ),
                ],
              ),
            ),
          ),
        if (isRoot || _open) ...[
          for (var child in node.sortedChildren)
            _TreeNodeView(
              node: child,
              depth: widget.depth + 1,
              selected: widget.selected,
              uncommitted: widget.uncommitted,
              ranking: widget.ranking,
              onSelect: widget.onSelect,
              openDepth: widget.openDepth,
            ),
          for (var file in node.sortedFiles)
            Padding(
              padding: EdgeInsets.only(
                left: isRoot ? 0 : widget.depth * FwSpacing.lg,
              ),
              child: IndexFileRow(
                file: file,
                selected: file.path == widget.selected,
                uncommitted: widget.uncommitted.contains(file.path),
                // The second place attention is surfaced: a pinned file says
                // what pinned it here too, where you are browsing, not only in
                // the band you may have scrolled past.
                reason: widget.ranking.forPath(file.path)?.reason,
                pinned:
                    widget.ranking.forPath(file.path)?.tier ==
                    RankTier.attention,
                // **No directory line under a file in the tree.** Its position
                // already says where it is, and repeating the path is the noise
                // the tree exists to remove.
                showDirectory: false,
                onTap: () => widget.onSelect(file.path),
              ),
            ),
        ],
      ],
    );
  }
}

/// The **body**: one file's diff, or the reason there is not one.
class _FilePane extends StatelessWidget {
  const _FilePane({
    required this.file,
    required this.untracked,
    required this.missing,
    required this.uncommitted,
    required this.lines,
    required this.controller,
  });

  final FileChange? file;
  final UntrackedEntry? untracked;

  /// The path the address named, so a selection that no longer exists can say
  /// so instead of falling silently back to nothing.
  final String? missing;

  final Set<String> uncommitted;
  final HunkLineCache lines;
  final ScrollController controller;

  @override
  Widget build(BuildContext context) {
    if (file case var it?) {
      var rows = buildFileRows(it);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _FileHeader(file: it, uncommitted: uncommitted.contains(it.path)),
          Divider(height: 1, color: context.colors.line),
          Expanded(
            child: ListView.builder(
              key: changesFileKey,
              controller: controller,
              itemCount: rows.length,
              itemBuilder: (context, index) => switch (rows[index]) {
                HunkRow(:var hunk) => HunkHeaderLine(hunk: hunk),
                // The one place a byte slice becomes text, and it happens for
                // the rows the list actually builds.
                DiffLineRow(:var hunk, :var index) => HunkLineView(
                  lines: lines,
                  hunk: hunk,
                  index: index,
                ),
                FileNoticeRow(:var message) => Padding(
                  padding: const EdgeInsets.all(FwSpacing.xxl),
                  child: Text(
                    message,
                    style: context.type.bodySmall.copyWith(
                      color: context.colors.mut2,
                    ),
                  ),
                ),
                _ => const SizedBox.shrink(),
              },
            ),
          ),
        ],
      );
    }

    if (untracked case var it?) {
      return _Empty(
        title: it.path,
        // Untracked means git has no other side to compare against — there is
        // no diff to render, and saying "no changes" would be a lie about a
        // file that is entirely new.
        body: it.isDirectory
            ? 'An untracked directory. Nothing here has been scanned — see the '
                  'note on the changes list.'
            : 'Not tracked yet, so there is nothing to compare it against. '
                  'Every line in it is new.',
      );
    }

    if (missing != null) {
      return _Empty(
        title: missing!,
        body:
            'This file is no longer part of the delta — it may have been '
            'committed away, reverted, or renamed.',
      );
    }

    return const _Empty(
      title: 'Pick a file',
      body:
          'The list on the left is ranked: what a rule pinned comes first, '
          'then the rest by weight.',
    );
  }
}

/// What the right pane says when it has nothing to draw.
class _Empty extends StatelessWidget {
  const _Empty({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: context.type.bodySmall.copyWith(color: colors.mut),
              overflow: TextOverflow.ellipsis,
            ),
            const Gap(FwSpacing.sm),
            Text(
              body,
              style: context.type.bodySmall.copyWith(color: colors.mut2),
            ),
          ],
        ),
      ),
    );
  }
}

/// The right pane's own header: which file, and what it costs.
class _FileHeader extends StatelessWidget {
  const _FileHeader({required this.file, required this.uncommitted});

  final FileChange file;
  final bool uncommitted;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    var slash = file.path.lastIndexOf('/');
    var directory = slash < 0 ? '' : file.path.substring(0, slash + 1);
    var name = slash < 0 ? file.path : file.path.substring(slash + 1);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        FwSpacing.xxl,
        FwSpacing.lg,
        FwSpacing.xxl,
        FwSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // **Name first, directory after it, dimmed** — the same rule the
          // explorer's card settled on. The name is the column you scan; a
          // directory-first row leaves the names on a ragged left edge.
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(
                  name,
                  style: context.type.bodyStrong,
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                ),
              ),
              if (directory.isNotEmpty) ...[
                const Gap(FwSpacing.sm),
                Flexible(
                  child: Text(
                    directory,
                    style: context.type.micro.copyWith(color: colors.mut3),
                    overflow: TextOverflow.ellipsis,
                    softWrap: false,
                  ),
                ),
              ],
            ],
          ),
          const Gap(FwSpacing.xs),
          Row(
            children: [
              // **The ruler kept its place, and this is a better one.** It used
              // to sit on a full-width file row; in a 320 px index there is no
              // width for it, and here it is directly above the hunks it is
              // describing — where "the change is all at the top" is a thing
              // you check before you start scrolling.
              HunkRuler(file: file, width: 120, height: 6),
              const Gap(FwSpacing.md),
              Expanded(
                child: _FileCounts(file: file, uncommitted: uncommitted),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _statusWord(ChangeStatus status) => switch (status) {
    ChangeStatus.added => 'added',
    ChangeStatus.deleted => 'deleted',
    ChangeStatus.renamed => 'renamed',
    ChangeStatus.modified => 'modified',
  };
}

class _FileCounts extends StatelessWidget {
  const _FileCounts({required this.file, required this.uncommitted});

  final FileChange file;
  final bool uncommitted;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    return Wrap(
      spacing: FwSpacing.md,
      children: [
        Text(
          _FileHeader._statusWord(file.status),
          style: context.type.micro.copyWith(color: colors.mut2),
        ),
        if (file.oldPath case var from?)
          Text(
            'from $from',
            style: context.type.micro.copyWith(color: colors.mut2),
          ),
        Text(
          '+${file.added}',
          style: context.type.micro.copyWith(color: colors.grn),
        ),
        Text(
          '-${file.removed}',
          style: context.type.micro.copyWith(color: colors.red),
        ),
        if (uncommitted)
          Text(
            'uncommitted',
            style: context.type.micro.copyWith(color: colors.amber),
          ),
        if (file.hunks.isNotEmpty)
          Text(
            '${file.hunks.length} '
            '${file.hunks.length == 1 ? 'hunk' : 'hunks'}',
            style: context.type.micro.copyWith(color: colors.mut3),
          ),
      ],
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    return Container(
      padding: const EdgeInsets.all(FwSpacing.md),
      decoration: BoxDecoration(
        color: colors.hoverOverlay,
        borderRadius: BorderRadius.circular(context.radii.radiusSmall),
      ),
      child: Text(
        text,
        style: context.type.bodySmall.copyWith(color: colors.mut),
      ),
    );
  }
}
