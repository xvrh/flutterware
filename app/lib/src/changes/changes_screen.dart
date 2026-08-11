import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../shell/worktree.dart';
import '../ui/theme.dart';
import 'change_rows.dart';
import 'change_set.dart';
import 'changes_config_cache.dart';
import 'changes_controller.dart';
import 'changes_tree.dart';
import 'churn_map.dart';
import 'diff_lines.dart';
import 'diff_view.dart';
import 'hunk_ruler.dart';
import 'patch_index.dart';

/// The changes screen's root, so a test can scope to it.
const changesScreenKey = Key('changes-screen');

/// The scrolling list of files and diff lines.
const changesListKey = Key('changes-list');

/// **`fw:///worktrees/<worktree>/changes`** — what this checkout has changed
/// against its base branch, committed and uncommitted together.
///
/// Deliberately not a plugin, and unlike the config screen not merely because
/// of what it is *about*: it reads git rather than the project, so it renders
/// for a worktree **nobody has opened**. A plugin needs a resolved config and a
/// session; the checkout you most want to look at is the one an agent has been
/// working in while you were elsewhere.
///
/// Three views of one delta, each answering something the others cannot: the
/// **churn map** says where the weight is before you read a line, the **tree**
/// says what was touched where, and the **list** is the diff itself.
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
  final _scroll = ScrollController();

  /// Paths whose bodies are showing. **Keyed by path, not by index**, so a
  /// reload that reordered the list leaves what you had open, open.
  final _expanded = <String>{};

  /// Rebuilt whenever the patch is, which is what throws the decoded text of
  /// the previous one away.
  HunkLineCache? _lines;
  ChangeSet? _cachedFor;

  var _query = '';
  String? _directory;
  String? _current;

  /// Whether the noise drawer is open. **Off by default and remembered for the
  /// session**, not persisted: the whole value of the drawer is that the
  /// screen opens on the signal.
  var _noiseOpen = false;

  /// A path the address named that has not been scrolled to yet.
  ///
  /// The jump cannot happen when the address arrives: the rows do not exist
  /// until the delta has loaded, and the list has no clients until it has been
  /// laid out. So it is remembered and spent on the first frame that has both —
  /// otherwise an address naming the fortieth file opens on the first one, and
  /// the link only appears to work for whatever is near the top.
  String? _pendingJump;

  @override
  void initState() {
    super.initState();
    if (widget.initialPath case var path?) {
      _expanded.add(path);
      _current = path;
      _pendingJump = path;
    }
    _start();
  }

  @override
  void didUpdateWidget(ChangesScreen old) {
    super.didUpdateWidget(old);
    if (old.worktree.path != widget.worktree.path) {
      _changes.dispose();
      _expanded.clear();
      _start();
      return;
    }
    // An address that arrived from outside — pasted, or followed from the
    // explorer — opens what it names without disturbing anything else already
    // open.
    if (widget.initialPath case var path?
        when path != old.initialPath && _expanded.add(path)) {
      _current = path;
      _pendingJump = path;
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

  void _onChanged() {
    // Read where we are **before** the new rows exist: once `setState` has run
    // the old layout is gone, and with it the only evidence of what you were
    // looking at.
    //
    // Only when the answer actually moved. The controller also notifies when a
    // read *starts*, and when one comes back saying nothing changed — neither
    // renumbers a row, and measuring the viewport for them would be a walk of
    // the sliver twice every two seconds for no reason.
    if (!identical(_changes.value, _cachedFor)) _anchor = _readAnchor();
    setState(() {});
  }

  /// The row at the top of the viewport, and how far above the top it starts.
  ///
  /// **Scroll position is pixels, and a live re-index moves pixels.** An agent
  /// creating one file inserts a row 63 px tall above everything below it, so
  /// an unchanged offset is now pointing 63 px earlier into the diff you were
  /// reading. Measured in a window: it is small enough to look like a glitch
  /// and large enough to lose your line. Keying the rows does **not** fix it —
  /// that was tried first, and `RenderSliverList` still lays out from the
  /// offset it was given.
  ///
  /// So the position is remembered as *a row and an offset into it*, which is
  /// what it means, and put back after the new rows have been laid out.
  ({String key, double delta})? _anchor;

  ({String key, double delta})? _readAnchor() {
    if (!_scroll.hasClients || _rows.isEmpty) return null;
    var sliver = _sliverOf();
    if (sliver == null) return null;
    var offset = _scroll.offset;
    ({String key, double delta})? best;
    for (var child = sliver.firstChild; child != null;) {
      var data = child.parentData! as SliverMultiBoxAdaptorParentData;
      var index = data.index;
      if (index != null && index >= 0 && index < _rows.length) {
        var reveal = _revealOffsetOf(child);
        // The topmost row whose start is at or above the viewport top: the one
        // the eye treats as "where I am".
        if (reveal != null && reveal <= offset + 0.5) {
          best = (key: _rows[index].anchorKey, delta: offset - reveal);
        }
      }
      child = sliver.childAfter(child);
    }
    return best;
  }

  void _restoreAnchor(({String key, double delta}) anchor) {
    if (!mounted || !_scroll.hasClients) return;
    // **Never while the list is moving under a hand.** The correction is a
    // `jumpTo`, and `jumpTo` ends the current scroll activity — measured: a
    // fling that was mid-flight at 549 px stops dead and stays there. On a
    // checkout an agent is writing in, that is a flick killed every two
    // seconds, which is far worse than the drift this exists to fix. While you
    // are scrolling you are not reading a fixed line anyway.
    //
    // `correctBy` was tried instead, since it is the mechanism built for
    // adjusting an offset without disturbing the activity. It keeps the fling
    // alive and does not move anything: it is a layout-time correction, and
    // from a post-frame callback there is no layout left for it to correct.
    if (_scroll.position.isScrollingNotifier.value) return;
    var index = _rows.indexWhere((row) => row.anchorKey == anchor.key);
    // The row is gone — the file it belonged to was committed away, or its
    // hunks moved. Nothing to hold on to, and pretending otherwise would put
    // you somewhere arbitrary.
    if (index < 0) return;
    var sliver = _sliverOf();
    if (sliver == null) return;
    for (var child = sliver.firstChild; child != null;) {
      var data = child.parentData! as SliverMultiBoxAdaptorParentData;
      if (data.index == index) {
        if (_revealOffsetOf(child) case var reveal?) {
          var want = (reveal + anchor.delta).clamp(
            _scroll.position.minScrollExtent,
            _scroll.position.maxScrollExtent,
          );
          if ((want - _scroll.offset).abs() > 0.5) _scroll.jumpTo(want);
        }
        return;
      }
      child = sliver.childAfter(child);
    }
    // **The bound, stated rather than hidden.** Only rows the sliver actually
    // laid out can be measured, which is the viewport plus its cache extent —
    // more than a screenful of insertions above you. Past that the offset is
    // left where it was, which is what this screen did before any of this.
  }

  /// The scroll offset at which [child] would sit at the top of the viewport.
  static double? _revealOffsetOf(RenderBox child) {
    var viewport = RenderAbstractViewport.maybeOf(child);
    return viewport?.getOffsetToReveal(child, 0).offset;
  }

  /// The list's sliver. Found by walking down from the list itself: `ListView`
  /// gives no handle on the sliver it builds, and the tree pane's own `ListView`
  /// comes first in this subtree, so starting from the screen would find the
  /// wrong one.
  RenderSliverMultiBoxAdaptor? _sliverOf() {
    RenderSliverMultiBoxAdaptor? found;
    void visit(RenderObject node) {
      if (found != null) return;
      if (node is RenderSliverMultiBoxAdaptor) {
        found = node;
        return;
      }
      node.visitChildren(visit);
    }

    var root = _listKey.currentContext?.findRenderObject();
    if (root != null) visit(root);
    return found;
  }

  final _listKey = GlobalKey();

  /// The rows the last build produced, which is what an anchor index means.
  var _rows = const <ChangeRow>[];

  @override
  void dispose() {
    _changes
      ..removeListener(_onChanged)
      ..dispose();
    _scroll.dispose();
    super.dispose();
  }

  HunkLineCache _linesFor(ChangeSet set) {
    if (!identical(_cachedFor, set)) {
      _cachedFor = set;
      _lines = HunkLineCache(set.patch);
    }
    return _lines!;
  }

  /// Null when nothing is filtering — which is what tells the churn map to draw
  /// every column at full strength, and the list to include the untracked.
  Set<String>? _visible(ChangeSet set) {
    if (_query.trim().isEmpty && _directory == null) return null;
    var byQuery = pathsMatching(set.changed, _query);
    if (_directory == null) return byQuery;
    return byQuery.intersection(pathsUnder(set.changed, _directory!));
  }

  void _toggle(FileChange file) {
    var opened = !_expanded.remove(file.path);
    setState(() {
      if (opened) _expanded.add(file.path);
      _current = file.path;
    });
    widget.onPathChanged?.call(opened ? file.path : null);
  }

  void _jumpTo(FileChange file, List<ChangeRow> rows) {
    setState(() => _current = file.path);
    var index = rows.indexWhere(
      (row) => row is FileRow && row.file.path == file.path,
    );
    if (index < 0 || !_scroll.hasClients) return;
    // **An estimate, not a measurement.** Rows are not uniform, so this lands
    // near the file rather than exactly on it. Near is what a churn-map click
    // is asking for, and measuring would mean building every row above the
    // target — which is precisely what the virtualised list exists to avoid.
    unawaited(
      _scroll.animateTo(
        (index * _rowEstimate).clamp(0, _scroll.position.maxScrollExtent),
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      ),
    );
  }

  static const _rowEstimate = 34.0;

  @override
  Widget build(BuildContext context) {
    var set = _changes.value;
    var visible = set == null ? null : _visible(set);
    var rows = set == null
        ? const <ChangeRow>[]
        : buildRows(
            set,
            expanded: _expanded,
            visible: visible,
            noiseOpen: _noiseOpen,
          );

    _rows = rows;

    if (_anchor case var it? when rows.isNotEmpty) {
      _anchor = null;
      WidgetsBinding.instance.addPostFrameCallback((_) => _restoreAnchor(it));
    }

    if (_pendingJump case var path? when rows.isNotEmpty) {
      var target = set?.changed.where((f) => f.path == path).firstOrNull;
      _pendingJump = null;
      if (target != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _jumpTo(target, rows);
        });
      }
    }

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
        if (set != null && set.changed.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              FwSpacing.xxl,
              0,
              FwSpacing.xxl,
              FwSpacing.lg,
            ),
            child: ChurnMap(
              files: set.changed,
              visible: visible,
              current: _current,
              onTap: (file) => _jumpTo(file, rows),
            ),
          ),
        Divider(height: 1, color: context.colors.line),
        Expanded(
          child: set == null
              ? const SizedBox.shrink()
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: _treeWidth,
                      child: _TreePane(
                        set: set,
                        directory: _directory,
                        onQuery: (q) => setState(() => _query = q),
                        onDirectory: (d) => setState(() => _directory = d),
                        onFile: (file) => _jumpTo(file, rows),
                      ),
                    ),
                    VerticalDivider(width: 1, color: context.colors.line),
                    Expanded(
                      child: _List(
                        listKey: _listKey,
                        set: set,
                        rows: rows,
                        lines: _linesFor(set),
                        controller: _scroll,
                        current: _current,
                        onToggle: _toggle,
                        onToggleNoise: () =>
                            setState(() => _noiseOpen = !_noiseOpen),
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }

  static const _treeWidth = 240.0;
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

/// Filter, then tree. Both narrow the list; neither opens anything.
class _TreePane extends StatelessWidget {
  const _TreePane({
    required this.set,
    required this.directory,
    required this.onQuery,
    required this.onDirectory,
    required this.onFile,
  });

  final ChangeSet set;
  final String? directory;
  final ValueChanged<String> onQuery;
  final ValueChanged<String?> onDirectory;
  final ValueChanged<FileChange> onFile;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    var tree = buildTree(set.changed);

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
        if (directory case var it?)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: FwSpacing.md),
            child: _Chip(label: it, onClear: () => onDirectory(null)),
          ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: FwSpacing.sm),
            children: [
              for (var child in tree.sortedChildren)
                _TreeRow(
                  node: child,
                  depth: 0,
                  selected: directory,
                  onDirectory: onDirectory,
                  onFile: onFile,
                ),
              for (var file in tree.sortedFiles)
                _TreeFile(file: file, depth: 0, onTap: onFile),
            ],
          ),
        ),
      ],
    );
  }
}

class _TreeRow extends StatefulWidget {
  const _TreeRow({
    required this.node,
    required this.depth,
    required this.selected,
    required this.onDirectory,
    required this.onFile,
  });

  final TreeNode node;
  final int depth;
  final String? selected;
  final ValueChanged<String?> onDirectory;
  final ValueChanged<FileChange> onFile;

  @override
  State<_TreeRow> createState() => _TreeRowState();
}

class _TreeRowState extends State<_TreeRow> {
  // Open at the top, shut further down: a branch that touched one module wants
  // that module visible, and a repo of forty directories does not want all of
  // them unfolded at once.
  late var _open = widget.depth < 1;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    var node = widget.node;
    var isSelected = widget.selected == node.path;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () {
            setState(() => _open = !_open);
            widget.onDirectory(isSelected ? null : node.path);
          },
          child: Container(
            color: isSelected ? colors.accentSoft : Colors.transparent,
            padding: EdgeInsets.only(
              left: FwSpacing.md + widget.depth * FwSpacing.lg,
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
                    style: context.type.bodySmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  '${node.totalFiles}',
                  style: context.type.micro.copyWith(color: colors.mut3),
                ),
              ],
            ),
          ),
        ),
        if (_open) ...[
          for (var child in node.sortedChildren)
            _TreeRow(
              node: child,
              depth: widget.depth + 1,
              selected: widget.selected,
              onDirectory: widget.onDirectory,
              onFile: widget.onFile,
            ),
          for (var file in node.sortedFiles)
            _TreeFile(
              file: file,
              depth: widget.depth + 1,
              onTap: widget.onFile,
            ),
        ],
      ],
    );
  }
}

class _TreeFile extends StatelessWidget {
  const _TreeFile({
    required this.file,
    required this.depth,
    required this.onTap,
  });

  final FileChange file;
  final int depth;
  final ValueChanged<FileChange> onTap;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    return InkWell(
      onTap: () => onTap(file),
      child: Padding(
        padding: EdgeInsets.only(
          left: FwSpacing.md + (depth + 1) * FwSpacing.lg,
          right: FwSpacing.md,
          top: FwSpacing.xxs,
          bottom: FwSpacing.xxs,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                file.path.split('/').last,
                style: context.type.bodySmall.copyWith(color: colors.mut),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Gap(FwSpacing.xs),
            HunkRuler(file: file, width: 36, height: 8),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.onClear});

  final String label;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: FwSpacing.sm,
        vertical: FwSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: colors.accentSoft,
        borderRadius: BorderRadius.circular(context.radii.radiusSmall),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: context.type.micro,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          InkWell(
            onTap: onClear,
            child: Icon(Icons.close, size: 12, color: colors.mut),
          ),
        ],
      ),
    );
  }
}

/// The virtualised list. **One `ListView.builder` over one flat row list**, so
/// a file expanded to four thousand lines costs the screenful you can see.
class _List extends StatelessWidget {
  const _List({
    required this.listKey,
    required this.set,
    required this.rows,
    required this.lines,
    required this.controller,
    required this.current,
    required this.onToggle,
    required this.onToggleNoise,
  });

  final GlobalKey listKey;
  final ChangeSet set;
  final List<ChangeRow> rows;
  final HunkLineCache lines;
  final ScrollController controller;
  final String? current;
  final ValueChanged<FileChange> onToggle;
  final VoidCallback onToggleNoise;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return Center(
        child: Text(
          set.changed.isEmpty ? 'Nothing to show.' : 'Nothing matches.',
          style: context.type.bodySmall.copyWith(color: context.colors.mut2),
        ),
      );
    }
    // Same order of work as `buildRows`, which already runs on every build.
    var indexOf = {for (var i = 0; i < rows.length; i++) rows[i].anchorKey: i};
    // The `GlobalKey` is on the wrapper rather than on the list, because it is
    // only ever used to walk *down* to the sliver — and a `ListView` holding a
    // key a test cannot name is a list a test cannot find.
    return KeyedSubtree(
      key: listKey,
      child: ListView.builder(
        key: changesListKey,
        controller: controller,
        itemCount: rows.length,
        // **Element identity, not scroll position.** Keyed and index-mapped,
        // an expanded file that moved from row 12 to row 13 keeps its own
        // element rather than being rebuilt as whatever is at 12 now.
        //
        // It does *not* keep the viewport still, which was worth finding out
        // by trying: `RenderSliverList` still lays out from the offset it was
        // given, so a row inserted above still slides what you were reading
        // down by its height. `_readAnchor` is what handles that.
        findChildIndexCallback: (key) =>
            indexOf[(key as ValueKey<String>).value],
        itemBuilder: (context, index) => KeyedSubtree(
          key: ValueKey(rows[index].anchorKey),
          child: _row(context, rows[index]),
        ),
      ),
    );
  }

  Widget _row(BuildContext context, ChangeRow row) => switch (row) {
    SectionRow(:var label, :var detail) => Padding(
      padding: const EdgeInsets.fromLTRB(
        FwSpacing.lg,
        FwSpacing.xl,
        FwSpacing.lg,
        FwSpacing.xs,
      ),
      child: Row(
        children: [
          Text(label, style: context.type.caption),
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
    NoiseDrawerRow(:var files, :var added, :var removed, :var open) =>
      NoiseDrawerLine(
        files: files,
        added: added,
        removed: removed,
        open: open,
        onTap: onToggleNoise,
      ),
    FileRow(:var file, :var expanded, :var uncommitted, :var reason) =>
      ChangeFileRow(
        file: file,
        expanded: expanded,
        uncommitted: uncommitted,
        reason: reason,
        isCurrent: file.path == current,
        onTap: () => onToggle(file),
      ),
    HunkRow(:var hunk) => HunkHeaderLine(hunk: hunk),
    // The one place a byte slice becomes text, and it happens for the rows
    // the list actually builds.
    DiffLineRow(:var hunk, :var index) => HunkLineView(
      lines: lines,
      hunk: hunk,
      index: index,
    ),
    FileNoticeRow(:var message) => Padding(
      padding: const EdgeInsets.fromLTRB(
        FwSpacing.xxl,
        FwSpacing.sm,
        FwSpacing.lg,
        FwSpacing.lg,
      ),
      child: Text(
        message,
        style: context.type.bodySmall.copyWith(color: context.colors.mut2),
      ),
    ),
    UntrackedRow(:var entry) => UntrackedFileLine(entry: entry),
  };
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
