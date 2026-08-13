import 'dart:async';

import 'package:flutter/material.dart';

import '../shell/worktree.dart';
import '../ui/syntax.dart';
import '../ui/tappable.dart';
import '../ui/theme.dart';
import 'change_rows.dart';
import 'change_set.dart';
import 'changes_config_cache.dart';
import 'changes_controller.dart';
import 'changes_tree.dart';
import 'diff_lines.dart';
import 'diff_view.dart';
import 'hunk_ruler.dart';
import 'hunk_syntax.dart';
import 'patch_index.dart';
import 'ranking.dart';
import 'range_picker.dart';

/// The changes screen's root, so a test can scope to it.
const changesScreenKey = Key('changes-screen');

/// The index of paths, on the left.
const changesListKey = Key('changes-list');

/// The selected file's diff, on the right.
const changesFileKey = Key('changes-file');

/// Which of the index's two tabs is showing.
///
/// **The ranking's answer and the directory structure are two orderings of one
/// set of files, and they do not fit in one column.** Putting the pinned files
/// in a band above the tree was tried and used, and it lost on both counts: the
/// alert competed with the tree for the top of a 320 px column, and it was
/// still occupying that column on the branches where it had nothing to say.
enum IndexTab {
  /// Everything, as a directory tree.
  all,

  /// What a rule pinned: flat, in rank order, nothing folded.
  important,
}

/// Whether the *just changed* lens is drawn over — and so narrows — [tab].
///
/// **One declaration, read by both halves.** It was two: the widget-tree
/// condition that draws the chip, and a conjunct in the filter. They agreed,
/// until they did not — a lens left on under *All* went on narrowing the
/// *Important* tab, which does not draw it, so the pinned list emptied from a
/// control that was nowhere on screen. Drawn and filtering are now one fact.
bool lensApplies(IndexTab tab) => tab == IndexTab.all;

/// **`fw:///worktrees/<worktree>/changes`** — what this checkout has changed
/// against its base branch, committed and uncommitted together.
///
/// Deliberately not a plugin, and unlike the config screen not merely because
/// of what it is *about*: it reads git rather than the project, so it renders
/// for a worktree **nobody has opened**. A plugin needs a resolved config and a
/// session; the checkout you most want to look at is the one an agent has been
/// working in while you were elsewhere.
///
/// **Master and detail.** Left: every path in the delta, and nothing else.
/// Right: the one file you picked. They used to be a single list of file rows
/// that expanded to inject their own diff, which made the surface you navigate
/// with and the surface you read the same one — every complaint about this
/// screen came out of that, from "clicking a file scrolls but does not open it"
/// to a live update sliding the lines under your eyes.
///
/// The index is **two tabs**: *All*, a directory tree, and *Important*, the
/// files a rule pinned. A churn map was a third way in and is gone — three
/// navigation surfaces for one list of files is two too many.
class ChangesScreen extends StatefulWidget {
  const ChangesScreen({
    required this.worktree,
    this.isOpen = false,
    this.repoRoot,
    this.initialPath,
    this.onPathChanged,
    this.initialRange = ChangeRange.everything,
    this.onRangeChanged,
    this.gitMoved,
    this.load,
    this.live = true,
    this.showTitle = true,
    super.key,
  });

  final Worktree worktree;

  /// The main checkout, which the repository-wide cache holding this project's
  /// ranking rules is keyed by. Null means nothing is pinned: there are no
  /// built-in rules to fall back on.
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

  /// Which part of the branch's history to open on, from `?from=` and `?to=`.
  ///
  /// In the address for the same reason the file is: a range you cannot paste
  /// is one you re-pick every time somebody asks what you are looking at.
  final ChangeRange initialRange;

  /// Writes a picked range back into the address.
  final ValueChanged<ChangeRange>? onRangeChanged;

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

  /// Whether this screen has to name itself.
  ///
  /// **False when it is a tab.** `ComparisonTabs` draws a strip above all three
  /// renderings of one delta, and only this one was also writing a page title
  /// and a branch line under it — so the files tab began with two lines of
  /// chrome the previews and scenarios tabs do not have, and the strip's
  /// `against <base>` sat six pixels above this screen's own `base <x>`. The
  /// same delta, stated twice, in two different vocabularies.
  ///
  /// True when there is no strip, which is a real case rather than a fallback:
  /// a checkout nobody has opened gets the file diff and no comparison, with no
  /// rail and no tabs around it, and then this line is the only thing on screen
  /// that says whose changes these are.
  final bool showTitle;

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

  /// The same, for syntax tokens — see [_tokensFor], which is keyed by the open
  /// file rather than by the patch.
  HunkTokenCache? _tokens;
  String? _tokensFile;

  var _query = '';

  /// **The lens.** One toggle over the index, with a count.
  ///
  /// *Just changed* is what has moved while this screen has been open — an
  /// agent's current sentence, not its paragraph. It replaced an *uncommitted*
  /// lens, which was the wrong question: committed-versus-not is a distinction
  /// that matters when a person is deciding what to push, and this screen is
  /// for watching something that commits on its own schedule. "What is it doing
  /// **now**" is the question that was actually being asked.
  ///
  /// With the Important tab, the two questions a fifty-file branch raises: what
  /// a **rule** says matters, and what is **moving**. A *low-signal* lens sat
  /// beside this one and is gone with the ranking tier behind it.
  var _justChangedOnly = false;

  /// Null until you pick one, which is what lets the default depend on what the
  /// checkout turned out to contain — see [_tabFor]. Set the moment a tab is
  /// clicked, and never re-derived after that: a screen that switches tabs
  /// under you because a rule started matching is a screen that moved your
  /// place while you were reading.
  IndexTab? _tab;

  /// **Important when there is something in it, All otherwise.**
  ///
  /// The one thing a tab costs is that the alert is hidden half the time, so
  /// the half it is hidden in is the half where it is empty. On a branch where
  /// a rule fired, the screen opens on the four files it fired for; on one
  /// where none did, opening on an empty tab would be the worst of both.
  IndexTab _tabFor(ChangeSet set) =>
      _tab ??
      (buildImportantRows(set).isEmpty ? IndexTab.all : IndexTab.important);

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
      // **The tab goes back to being derived**, like the selection. Holding a
      // click made about the last checkout would open the next one on an
      // *Important* tab that has nothing in it — see [_tabFor], whose whole
      // point is that the empty half is the half a tab may not open on.
      _tab = null;
      _start();
      return;
    }
    // An address that arrived from outside — pasted, or followed from the
    // explorer — selects what it names.
    if (widget.initialPath case var path?
        when path != old.initialPath && path != _selected) {
      _show(path);
    }
    // The same for the range. It comes back down through the address rather
    // than being held here, which is what makes the picker's write and a
    // pasted `?from=` the same code path — and what stops the two disagreeing
    // when the back button moves one of them.
    if (widget.initialRange != _changes.range) {
      unawaited(_changes.setRange(widget.initialRange));
    }
  }

  void _start() {
    _changes = ChangesController(
      worktreePath: widget.worktree.path,
      repoRoot: widget.repoRoot,
      load: widget.load,
      range: widget.initialRange,
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
      // Tokens are per *file*, and the file being read changes far more often
      // than the patch does — see [_tokensFor].
      _tokens = null;
      _tokensFile = null;
    }
    return _lines!;
  }

  /// The tokens for the file the right pane is showing.
  ///
  /// **Keyed by the file, not by the patch**, because the language is: a
  /// `.dart` file and a `.yaml` file in one delta are two grammars, and a cache
  /// that outlived the selection would hand a hunk of one to the other. One
  /// file is open at a time, so one cache is the right number.
  HunkTokenCache _tokensFor(ChangeSet set, FileChange file) {
    if (_tokensFile != file.path || _tokens == null) {
      _tokensFile = file.path;
      _tokens = HunkTokenCache(
        _linesFor(set),
        language: languageForPath(file.path),
      );
    }
    return _tokens!;
  }

  /// Null when nothing is narrowing the index at all.
  ///
  /// The typed query and the lens compose by intersection, so `motion` plus
  /// *just changed* means both, which is what anybody would expect of two
  /// controls sitting next to each other.
  ///
  /// **The lens narrows the tab that draws it, and only that one.** It applied
  /// to both, and the *Important* tab does not draw it — so a lens left on
  /// under *All* emptied the pinned list from a control that was not on screen,
  /// under a tab label still counting the files it had just hidden, and the
  /// empty state said `No file matched an attention rule` about files that
  /// had. The filter box is drawn under both tabs and so narrows both.
  Set<String>? _visible(ChangeSet set, IndexTab tab) {
    Set<String>? visible;
    if (_query.trim().isNotEmpty) {
      visible = pathsMatching([
        ...set.changed.map((f) => f.path),
        ...set.untracked.map((e) => e.path),
      ], _query);
    }
    if (_justChangedOnly && lensApplies(tab)) {
      var moved = _changes.moved;
      visible = visible == null ? {...moved} : visible.intersection(moved);
    }
    return visible;
  }

  /// Narrows to [range], and says so in the address.
  ///
  /// **The selection is dropped with it.** A file that is in the whole delta is
  /// often not in one commit of it, and the right pane already has a state for
  /// a path the set no longer holds — `This file is no longer part of the
  /// delta`, which would be a confusing thing to read about a file you had just
  /// been looking at and had not touched. Going back to the index is the honest
  /// answer to *the question changed*.
  void _pickRange(ChangeRange range) {
    if (range == _changes.range) return;
    _show(null);
    // Written to the address rather than applied here: it comes back down as
    // `initialRange`, which is the same path a pasted link takes.
    if (widget.onRangeChanged case var write?) {
      write(range);
    } else {
      unawaited(_changes.setRange(range));
    }
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
    // Derived once: the tab the index draws and the tab the filter is computed
    // against are the same tab, and reading it twice is two chances to disagree
    // about the value this screen's narrowing now turns on.
    var tab = set == null ? IndexTab.all : _tabFor(set);

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
          showTitle: widget.showTitle,
          range: _changes.range,
          onRange: _pickRange,
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
                        tab: tab,
                        controller: _index,
                        query: _query,
                        selected: _selected,
                        visible: _visible(set, tab),
                        justChanged: _changes.moved,
                        justChangedOnly: _justChangedOnly,
                        onTab: (tab) => setState(() => _tab = tab),
                        onQuery: (q) => setState(() => _query = q),
                        onSelect: _show,
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
                        tokens: switch (_selectedFile(set)) {
                          var file? => _tokensFor(set, file),
                          null => null,
                        },
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
    required this.showTitle,
    required this.range,
    required this.onRange,
    required this.onRefresh,
  });

  final Worktree worktree;
  final ChangeSet? set;
  final bool isLoading;
  final bool live;
  final bool isWatching;
  final DateTime? readAt;
  final Object? failure;
  final bool showTitle;

  /// Read from the controller rather than from [set], because the range is the
  /// *question*: it is picked before the answer exists, and the first frame
  /// after picking one has no set at all.
  final ChangeRange range;

  final ValueChanged<ChangeRange> onRange;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        FwSpacing.xxl,
        showTitle ? FwSpacing.xl : FwSpacing.lg,
        FwSpacing.xxl,
        FwSpacing.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (showTitle)
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Changes', style: context.type.pageTitle),
                      const Gap(FwSpacing.xs),
                      // **The identity is drawn before anything is loaded.** A
                      // screen that opens on a spinner tells you nothing you
                      // did not already know.
                      Text(
                        worktree.displayName,
                        style: context.type.caption.copyWith(color: colors.mut),
                      ),
                    ],
                  ),
                )
              else
                // Under a strip, the summary *is* the header: the delta's
                // counts move up onto the line the title used to have, rather
                // than leaving an empty band where it was.
                Expanded(
                  child: _Summary(set, onRange: onRange, showBase: false),
                ),
              // **What makes the liveness believable.** A screen that updates
              // by itself and never says so is indistinguishable from one that
              // has stopped — and the one thing worse than a stale screen is a
              // stale screen you trust.
              //
              // **Centred against the refresh button, not against the title.**
              // These two are one cluster and read as one: aligned to the top
              // of the row, the badge sat seventeen pixels above the icon it
              // belongs beside, because a 14 px label and a 48 px `IconButton`
              // have nothing in common but their top edge.
              _Watching(
                live: live,
                isWatching: isWatching,
                readAt: readAt,
                pinned: !range.endsAtWorkingTree,
              ),
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
          if (showTitle) ...[
            const Gap(FwSpacing.md),
            _Summary(set, onRange: onRange),
          ],
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
    required this.pinned,
  });

  final bool live;
  final bool isWatching;
  final DateTime? readAt;

  /// Whether the range ends at a commit rather than at the files on disk.
  ///
  /// **Then nothing can move it, and saying *Watching* would be the exact
  /// failure this widget exists to prevent** — a screen that claims to be live
  /// while showing frozen history is the stale screen you trust. The watch is
  /// still armed and the badge still says something true; it just stops being
  /// a claim about the thing on screen.
  final bool pinned;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    if (!live) return const SizedBox.shrink();
    var stale = !isWatching;
    return Tooltip(
      message: pinned
          ? 'Pinned to a range of commits — nothing on disk can change it'
          : stale
          ? 'This checkout is not being watched — refresh to read it again'
          : 'Re-read whenever this checkout changes'
                '${readAt == null ? '' : '\nLast read at ${_clock(readAt!)}'}',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (pinned)
            Icon(Icons.push_pin_outlined, size: 11, color: colors.mut3)
          else
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
            pinned
                ? 'Pinned'
                : stale
                ? 'Not watching'
                : 'Watching',
            style: context.type.micro.copyWith(
              color: stale && !pinned ? colors.mut2 : colors.mut3,
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
  const _Summary(this.set, {required this.onRange, this.showBase = true});

  final ChangeSet? set;
  final ValueChanged<ChangeRange> onRange;

  /// False under the comparison strip, which states the base for all three
  /// tabs. `base master (inferred)` under `against origin/master` is one fact
  /// spelled two ways, and a reader who notices the difference has to work out
  /// whether it is one.
  final bool showBase;

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
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text('${it.changed.length} files', style: style),
          Text('+${it.added}', style: style.copyWith(color: colors.grn)),
          Text('-${it.removed}', style: style.copyWith(color: colors.red)),
          if (uncommitted > 0)
            Text(
              '$uncommitted uncommitted',
              style: style.copyWith(color: colors.amber),
            ),
          // **The base statement became the control.** It already answered
          // *against what*, which is the same question a range answers with
          // more in it — so the range is picked where the answer is read,
          // rather than from a second affordance in a header that is one line
          // tall. See `RangePicker`.
          RangePicker(set: it, onRange: onRange, withBase: showBase),
        ],
      );
    }
    return Text('Reading…', style: style.copyWith(color: colors.mut2));
  }
}

/// The **index**: filter, two tabs, and the paths.
///
/// Navigation only. Nothing here is content, which is the whole point of the
/// split — the list stays where you left it while you read, and a live re-probe
/// that adds a file changes this column without moving a line of what is open.
///
/// **Two orderings, one column, so two tabs.** *All* is a directory tree, which
/// is what navigation wants: structure, ordered by weight inside it, so an
/// agent's heaviest module is the first thing under each folder. *Important* is
/// the ranking's answer — flat, short, in rank order, nothing folded, because a
/// list of four files has no shape to communicate and folding it would only
/// hide it.
///
/// They were one column before this, the pinned files in a band above the tree,
/// and using it settled the argument: two lists arguing for the top of a 320 px
/// column, with the band still taking that space on branches where it had
/// nothing to say.
class _IndexPane extends StatelessWidget {
  const _IndexPane({
    required this.set,
    required this.tab,
    required this.controller,
    required this.query,
    required this.selected,
    required this.onTab,
    required this.onQuery,
    required this.onSelect,
    required this.onToggleJustChanged,
    required this.justChanged,
    required this.justChangedOnly,
    required this.visible,
  });

  final ChangeSet set;
  final IndexTab tab;

  final ScrollController controller;
  final String query;
  final String? selected;
  final ValueChanged<IndexTab> onTab;
  final ValueChanged<String> onQuery;
  final ValueChanged<String> onSelect;
  final VoidCallback onToggleJustChanged;
  final Set<String> justChanged;
  final bool justChangedOnly;
  final Set<String>? visible;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    // Unfiltered, because a tab label is a claim about the checkout and not
    // about the box you are typing in. A count that drops to 0 as you type
    // makes the other tab look like the place the file went.
    var pinned = buildImportantRows(set).length;

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
        _Tabs(
          tab: tab,
          all: set.changed.length + set.untracked.length,
          important: pinned,
          onTab: onTab,
        ),
        // Drawn and filtering are one fact — see [lensApplies]. Narrowing four
        // pinned files to the two that moved is not a question anyone has.
        if (lensApplies(tab))
          _LensRow(
            justChanged: justChanged.length,
            justChangedOnly: justChangedOnly,
            onToggleJustChanged: onToggleJustChanged,
          ),
        Expanded(
          child: switch (tab) {
            IndexTab.all => _all(context),
            IndexTab.important => _important(context),
          },
        ),
      ],
    );
  }

  /// Everything in the delta: the tree, then the untracked paths under it.
  Widget _all(BuildContext context) {
    var tree = buildTree(treeFiles(set, visible: visible));
    var untracked = buildUntrackedRows(
      set,
      selected: selected,
      visible: visible,
    );
    if (tree.totalFiles == 0 && untracked.isEmpty) {
      return _Nothing(
        set.changed.isEmpty ? 'Nothing to show.' : 'Nothing matches.',
      );
    }
    // **Not virtualised, deliberately.** The index is the file count, not the
    // line count — a 228-file branch is a few hundred rows, where the list it
    // replaced could be four thousand. A tree that remembers which folders are
    // open cannot be rebuilt by index anyway.
    return ListView(
      key: changesListKey,
      controller: controller,
      children: [
        if (tree.totalFiles > 0)
          _TreeNodeView(
            node: tree,
            depth: 0,
            selected: selected,
            uncommitted: set.uncommitted,
            ranking: set.ranking,
            onSelect: onSelect,
            // Open at the top, shut further down: a branch that touched one
            // module wants that module visible, and a repo of forty
            // directories does not want all of them unfolded at once.
            openDepth: 1,
          ),
        for (var row in untracked) _flat(context, row),
      ],
    );
  }

  /// What a rule pinned, and nothing else.
  Widget _important(BuildContext context) {
    var rows = buildImportantRows(set, selected: selected, visible: visible);
    if (rows.isEmpty) {
      // Two different silences, and telling them apart is the whole reason
      // `attentionConfigured` exists: a project that has never written a rule
      // is looking at a feature that appears not to work, and a project whose
      // rules matched nothing is looking at good news.
      return set.attentionConfigured
          ? const _Nothing('No file matched an attention rule.')
          : const _NoRulesYet();
    }
    return ListView(
      key: changesListKey,
      controller: controller,
      children: [for (var row in rows) _flat(context, row)],
    );
  }

  Widget _flat(BuildContext context, ChangeRow row) => switch (row) {
    SectionRow(:var label) => Padding(
      padding: const EdgeInsets.fromLTRB(
        FwSpacing.md,
        FwSpacing.lg,
        FwSpacing.md,
        FwSpacing.xs,
      ),
      child: Text(
        label,
        style: context.type.caption,
        overflow: TextOverflow.ellipsis,
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

/// The two tabs, with their counts.
///
/// **The count is what pays for the tab.** A tab's cost is that half the time
/// it is hiding what it holds; a number on the label means the Important tab
/// still says *there are four files a rule pinned* without being opened, which
/// is most of what the band it replaces was for.
class _Tabs extends StatelessWidget {
  const _Tabs({
    required this.tab,
    required this.all,
    required this.important,
    required this.onTab,
  });

  final IndexTab tab;
  final int all;
  final int important;
  final ValueChanged<IndexTab> onTab;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: context.colors.line)),
      ),
      child: Row(
        children: [
          _Tab(
            label: 'All',
            count: all,
            on: tab == IndexTab.all,
            onTap: () => onTab(IndexTab.all),
          ),
          _Tab(
            label: 'Important',
            count: important,
            on: tab == IndexTab.important,
            onTap: () => onTab(IndexTab.important),
          ),
        ],
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.label,
    required this.count,
    required this.on,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    return Tappable.builder(
      onTap: onTap,
      builder: (context, hovered) => Container(
        padding: const EdgeInsets.fromLTRB(
          FwSpacing.lg,
          FwSpacing.md,
          FwSpacing.lg,
          FwSpacing.md,
        ),
        decoration: BoxDecoration(
          color: hovered && !on ? colors.hoverOverlay : null,
          border: Border(
            // Two pixels, drawn where the divider is, so the selected tab sits
            // on the list it is naming.
            bottom: BorderSide(
              color: on ? colors.accent : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              label,
              style: context.type.bodySmall.copyWith(
                color: on ? colors.accent : colors.mut2,
              ),
            ),
            const Gap(FwSpacing.xs),
            Text(
              '$count',
              style: context.type.micro.copyWith(
                color: on ? colors.accent : colors.mut3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One line, centred, for a list that has nothing in it.
class _Nothing extends StatelessWidget {
  const _Nothing(this.message);

  final String message;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(FwSpacing.xl),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: context.type.bodySmall.copyWith(color: context.colors.mut2),
      ),
    ),
  );
}

/// What the **Important** tab says to a project that has never written an
/// `attention:` rule.
///
/// **There are no built-in ones**, so without this the tab is empty and the
/// whole ranking reads as a feature that does not work. It is the empty state
/// rather than a line above the list, which is where it used to sit: a note
/// that a band could not fit is a full pane's worth of room here, and it can
/// say the whole thing.
class _NoRulesYet extends StatelessWidget {
  const _NoRulesYet();

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(FwSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Nothing is pinned yet.',
              style: context.type.bodySmall.copyWith(color: colors.mut),
            ),
            const Gap(FwSpacing.sm),
            Text(
              'Name what you want to see first in tool/flutterware.dart:',
              style: context.type.micro.copyWith(color: colors.mut2),
            ),
            const Gap(FwSpacing.sm),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(FwSpacing.sm),
              decoration: BoxDecoration(
                color: colors.panel2,
                borderRadius: BorderRadius.circular(context.radii.radiusSmall),
              ),
              child: Text(
                "fw.changes(ChangesConfig(\n  attention: ['lib/api/**'],\n));",
                style: diffTextStyle(context).copyWith(color: colors.mut2),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The lens, drawn only when it would say something.
///
/// **It appears when it becomes true, which is exactly when it is useful.**
/// Nothing has moved on arrival, so there is no chip; the first time the agent
/// writes something, one shows up saying so. A chip reading `0` is a control
/// that does nothing, which is worse than no control — the same rule the
/// section headings follow.
class _LensRow extends StatelessWidget {
  const _LensRow({
    required this.justChanged,
    required this.justChangedOnly,
    required this.onToggleJustChanged,
  });

  /// How many paths have moved since the screen opened. A count, not the set:
  /// the count is all this draws, and taking the set invited reading it.
  final int justChanged;

  final bool justChangedOnly;
  final VoidCallback onToggleJustChanged;

  @override
  Widget build(BuildContext context) {
    if (justChanged == 0) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        FwSpacing.md,
        0,
        FwSpacing.md,
        FwSpacing.sm,
      ),
      // The index stretches its children; a chip that fills 320 px is a button
      // pretending to be a banner.
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: IndexLens(
          label: 'just changed',
          count: justChanged,
          on: justChangedOnly,
          onTap: onToggleJustChanged,
        ),
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
          Tappable.builder(
            onTap: () => setState(() => _open = !_open),
            builder: (context, hovered) => Container(
              color: hovered ? colors.hoverOverlay : null,
              // **A row you can hit.** Two pixels above and below a 14 px line
              // is a 18 px target between two other targets, and the folder is
              // the row you click most: it is the only one that folds.
              padding: EdgeInsets.only(
                left: FwSpacing.md + (widget.depth - 1) * FwSpacing.lg,
                right: FwSpacing.md,
                top: FwSpacing.sm,
                bottom: FwSpacing.sm,
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
            if (widget.ranking.forPath(file.path) case var ranked)
              Padding(
                padding: EdgeInsets.only(
                  left: isRoot ? 0 : widget.depth * FwSpacing.lg,
                ),
                child: IndexFileRow(
                  file: file,
                  selected: file.path == widget.selected,
                  uncommitted: widget.uncommitted.contains(file.path),
                  // The second place attention is surfaced: a pinned file says
                  // what pinned it here too, where you are browsing, not only
                  // in the tab you may not have opened.
                  reason: ranked?.reason,
                  pinned: ranked?.tier == RankTier.attention,
                  // **No directory line under a file in the tree.** Its
                  // position already says where it is, and repeating the path
                  // is what the tree exists to remove.
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
    required this.tokens,
    required this.controller,
  });

  final FileChange? file;
  final UntrackedEntry? untracked;

  /// The path the address named, so a selection that no longer exists can say
  /// so instead of falling silently back to nothing.
  final String? missing;

  final Set<String> uncommitted;
  final HunkLineCache lines;

  /// Null when nothing is selected, and carrying a null language for a file
  /// this build has no grammar for.
  final HunkTokenCache? tokens;

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
                  tokens: tokens,
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
          'All is every path in this delta, as a tree. Important is what a '
          'rule in tool/flutterware.dart pinned.',
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

  static String _statusWord(ChangeStatus status) => statusWord(status);
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
        // **Nothing here says anything about colour**, and that is the point of
        // the chunked tokeniser: there is no size at which this screen quietly
        // stops colouring, so there is nothing to announce. It briefly had a
        // `not coloured · 1109-line hunk` note beside a 500-line cap — a note
        // that existed only because the cap did.
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
