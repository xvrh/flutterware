import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutterware/ui_catalog.dart';
import 'package:path/path.dart' as p;

import '../embedder/embedded_engine.dart';
import '../embedder/guest_vm_service.dart';
import 'catalog_params.dart';
import 'devices.dart';
import 'catalog_entry.dart';
import 'compiler_daemon_client.dart';
import 'inspect_client.dart';
import 'live_session.dart';
import 'protocol.dart';

enum CatalogSessionPhase { starting, ready, error }

/// Which pane of the inspection panel is showing.
///
/// Lives here rather than beside the widget because the session outlives the
/// panel — the shell rebuilds it from scratch whenever you come back to it, and
/// returning to the tab you had open is the same courtesy as returning to the
/// entry you had selected.
///
/// **Deliberately not on the address**, unlike the node selection beside it.
/// `inspect.*` is dropped when the entry segment changes — it must be, since a
/// node id names a position in one particular tree and would otherwise name
/// some unrelated widget of the next demo with complete confidence. A tab
/// dropped with it would flip back to Elements on every click through the entry
/// list, which is exactly when you least want it to.
///
/// **Controls is first and is the default.** It is the everyday loop — turn a
/// knob, watch the demo — where the tree is what you go to when something is
/// wrong. Opening straight onto a wall of widget rows reads as the panel having
/// an opinion about what you came here to do.
enum InspectTab {
  controls('Controls'),
  elements('Elements'),
  problems('Problems'),
  console('Console');

  const InspectTab(this.label);

  final String label;
}

/// What the guest is being rendered *as*, which the top bar owns.
///
/// A device here is not decoration around the picture. The guest's window is
/// resized to the device's screen at the device's own pixel ratio, so a demo
/// reads the phone's size from `MediaQuery` rather than the panel's — which is
/// the difference between looking at a layout and testing one.
class CatalogStaging extends ChangeNotifier {
  /// Whether the device's chrome is drawn around the screen. Off leaves a
  /// plain rectangle of the right size, which is what you want once you are
  /// looking at the layout rather than at the phone.
  ///
  /// The only thing left here. The **device** used to live beside it, with a
  /// flag saying whether a person or an entry had last set it, and the panel
  /// copied it into the address a frame after every change. That copy loop was
  /// the bug: a pick was read back from an address that had not caught up yet
  /// and erased. A device is now a function of the address and the entry —
  /// see [resolveDevice] — held nowhere, so there is nothing to fall out of
  /// step.
  bool get frameVisible => _frameVisible;
  var _frameVisible = true;
  set frameVisible(bool value) {
    if (value == _frameVisible) return;
    _frameVisible = value;
    notifyListeners();
  }
}

/// The entry browser's own state, which is about looking rather than compiling.
///
/// Folders are tracked by what has been *closed*, not by what has been opened:
/// a folder that appears after a rescan is then open like everything around it,
/// where an expanded-set would have hidden it until someone thought to look.
class CatalogBrowsing extends ChangeNotifier {
  final _closed = <String>{};

  bool isOpen(String branchId) => !_closed.contains(branchId);

  void toggle(String branchId) {
    if (!_closed.remove(branchId)) _closed.add(branchId);
    notifyListeners();
  }

  /// Whether anything is folded away at all, which is what makes one button
  /// enough for both directions.
  bool get anyClosed => _closed.isNotEmpty;

  void closeAll(Iterable<String> branchIds) {
    _closed.addAll(branchIds);
    notifyListeners();
  }

  void openAll() {
    if (_closed.isEmpty) return;
    _closed.clear();
    notifyListeners();
  }

  /// What was typed in the filter box. Empty shows everything.
  String get filter => _filter;
  var _filter = '';
  set filter(String value) {
    if (value == _filter) return;
    _filter = value;
    notifyListeners();
  }

  /// Whether the entry list is showing at all, so the guest can have the panel.
  bool get listVisible => _listVisible;
  var _listVisible = true;
  set listVisible(bool value) {
    if (value == _listVisible) return;
    _listVisible = value;
    notifyListeners();
  }
}

/// How the last switch went, for the UI to show.
class SwitchReport {
  SwitchReport({
    required this.entry,
    required this.compile,
    required this.reload,
    required this.newSourceCount,
    required this.editedCount,
    this.reloaded = false,
    this.error,
  });

  final CatalogEntry entry;
  final Duration compile;
  final Duration reload;
  final int newSourceCount;

  /// How many edited files the daemon picked up. The interesting number when
  /// [reloaded] — it is the difference between "your save is on screen" and
  /// "nothing was saved".
  final int editedCount;

  /// This was a reload of the entry already showing, not a switch to another.
  final bool reloaded;

  /// Compiler diagnostics when the entry did not build. The guest keeps
  /// rendering whatever it had.
  final String? error;

  bool get ok => error == null;
}

/// Owns the warm catalog loop from the GUI's side: the compiler daemon, one
/// embedder guest, and the VM-service connection that pushes entries into it.
///
/// Switching an entry is a hot reload, not a restart — the engine, the isolate
/// and the compiler all stay warm.
///
/// **Nothing here compiles in-process.** All building and compiling happens in
/// the daemon, a separate plain-Dart process; see [CompilerDaemonClient] for
/// why that is not a style preference.
class CatalogSession extends ChangeNotifier {
  CatalogSession({
    required this.appPackageRoot,
    required this.flutterSdkRoot,
    required this.projectRoot,
    this.worktreeRoot,
    this.roots = const ['demo'],
  }) {
    // Forwarded, so a renderer has one thing to listen to.
    browsing.addListener(notifyListeners);
    staging.addListener(notifyListeners);
  }

  /// Where the browser was left: what is folded away, what was typed, whether
  /// the list is showing.
  ///
  /// On the session because the session outlives the panel — the shell builds
  /// the panel from scratch each time you come back to it, and returning to a
  /// tree you had arranged and a filter you had typed is the same courtesy as
  /// returning to the entry you had selected.
  final browsing = CatalogBrowsing();

  /// What the guest is rendered as: a device, or the panel.
  final staging = CatalogStaging();

  /// Everything discovery found, populated when the daemon reports ready.
  List<CatalogEntry> entries = const [];

  /// Entries discovery found but the compiler cannot build, with the error to
  /// show for each. Kept out of [entries] rather than hidden: a demo you are
  /// midway through editing should say why it is unavailable.
  List<QuarantinedEntry> quarantined = const [];

  /// Warnings the scan produced; the daemon refuses to start on errors.
  List<String> diagnostics = const [];

  /// The `flutterware_app` package root, which owns `native/` and the build dir.
  final String appPackageRoot;
  final String flutterSdkRoot;

  /// Root the entries' paths are relative to.
  final String projectRoot;

  /// The worktree the project sits in, for shortening what is shown.
  ///
  /// An absolute URI is the truth and a relative path is what anybody reading
  /// it wants — and worktree-relative rather than package-relative so a source
  /// location read off the panel is byte-identical to the one `fw run
  /// ui_catalog inspect --tree` prints, which is what lets you paste one where
  /// the other was expected. Falls back to [projectRoot] when nothing said.
  final String? worktreeRoot;

  /// What a path shown in the panel is measured against.
  String get displayRoot => worktreeRoot ?? projectRoot;

  /// Directories to scan, relative to [projectRoot].
  final List<String> roots;

  CatalogSessionPhase phase = CatalogSessionPhase.starting;
  String? errorMessage;

  /// What the guest is currently rendering.
  CatalogEntry? active;

  /// What the user last asked for, which is not the same thing: an entry that
  /// does not compile stays selected — and stays the one a reload retries —
  /// while the guest goes on rendering whatever it last managed to load.
  CatalogEntry? selected;

  /// The entry the address names, which is **a request rather than a call**.
  ///
  /// Nothing here can be selected until the daemon reports what exists, and on
  /// a cold start the address arrives long before that — clicking a search hit
  /// is what *starts* the compile it would be waiting for. So this is written
  /// whenever it is known and applied whenever it becomes possible: at [start],
  /// and again whenever the entry list moves. Setting it while ready switches
  /// immediately.
  ///
  /// Null means the address named no entry, and the session picks for itself.
  String? get wantedEntryId => _wantedEntryId;
  String? _wantedEntryId;

  set wantedEntryId(String? id) {
    if (_wantedEntryId == id) return;
    _wantedEntryId = id;
    if (phase == CatalogSessionPhase.ready) _applyWanted();
  }

  /// The entry [wantedEntryId] names, if the catalog has one.
  ///
  /// Looks in [allEntries] rather than [entries]: an address naming a demo that
  /// currently does not compile should land on it and show the error, which is
  /// the useful answer. Being sent somewhere else instead is how a broken
  /// build turns into "the link is wrong".
  CatalogEntry? get wantedEntry {
    var id = _wantedEntryId;
    return id == null ? null : allEntries.where((e) => e.id == id).firstOrNull;
  }

  /// Set when the address names an entry this catalog does not have at all.
  ///
  /// Deliberately not repaired by moving somewhere that does exist. A pasted
  /// address that quietly becomes a different one is indistinguishable from a
  /// broken app; saying "there is no such entry" is information, and silently
  /// showing the first demo is not.
  ///
  /// Only once the session is ready. Before that *nothing* exists yet, and
  /// "there is no such entry" would be the first thing every cold start said
  /// about a perfectly good address.
  String? get missingEntryId =>
      phase == CatalogSessionPhase.ready &&
          _wantedEntryId != null &&
          wantedEntry == null
      ? _wantedEntryId
      : null;

  void _applyWanted() {
    var entry = wantedEntry;
    if (entry == null || entry.id == selected?.id) return;
    unawaited(switchTo(entry));
  }

  SwitchReport? lastSwitch;
  Duration? coldCompile;

  /// The controls the entry on screen declared while it built, or an empty
  /// report for one that declares none.
  KnobReport knobs = KnobReport.empty;

  /// The axes the shell on screen declared, with what each is set to.
  ///
  /// The only place shells are known at all. Nothing discovers them: a shell is
  /// whatever the entry's wrapper builds, and it says so by declaring its axes
  /// while it builds — so the host learns which shell an entry uses from this
  /// report and from nowhere else.
  AxisReport axes = AxisReport.empty;

  /// The widget tree the guest last reported, whichever entry it was of.
  ///
  /// Read from the **live** guest rather than through a `PluginAction`, which
  /// is the point: an action renders its own headless copy, and a copy has
  /// none of the state a person put this one into. Prefer [treeForSelection]
  /// for anything that draws.
  InspectTree? tree;

  /// The tree, but only when it describes what is selected.
  ///
  /// A tree naming another entry is a read from before the switch, not an
  /// empty one — the same rule `KnobReport.entryId` follows. Drawing it under
  /// a selection it does not belong to is how you end up wondering why your
  /// edit did nothing, which is the mistake `_CompileError` exists to avoid
  /// one pane over.
  InspectTree? get treeForSelection =>
      tree?.entryId == (selected ?? active)?.id ? tree : null;

  /// What the entry on screen reported while building and painting.
  ///
  /// **Read after every build regardless of which tab is open**, unlike the
  /// tree. A badge exists to tell you about something you did not ask about,
  /// and one that only appears once you open the tab it is on would be telling
  /// you what you had just gone and looked up. It is also a much smaller answer
  /// than a tree: a handful of distinct errors, counted rather than repeated.
  InspectErrors? renderErrors;

  /// The errors, but only when they describe what is selected — the same rule
  /// [treeForSelection] follows, and for the same reason.
  InspectErrors? get errorsForSelection =>
      renderErrors?.entryId == (selected ?? active)?.id ? renderErrors : null;

  /// Which pane of the panel is showing. See [InspectTab] for why it is here
  /// and not on the address.
  InspectTab inspectTab = InspectTab.controls;

  /// Whether the tree is **on screen** — the Elements tab showing, and the
  /// panel not collapsed.
  ///
  /// Deliberately narrower than "the panel is mounted". A tree nobody is
  /// looking at is a round trip on every entry switch, paid by everyone who
  /// never opens that tab; and since the panel now opens on Controls, tying it
  /// to the mount would have meant every session reading trees for a pane
  /// nobody had asked to see.
  /// **Does not notify.** Nothing draws this flag, and the panel turns it off
  /// from `dispose` — where notifying would rebuild listeners around a widget
  /// on its way out. Turning it on notifies soon enough, when the tree lands.
  bool get inspecting => _inspecting;
  var _inspecting = false;
  set inspecting(bool value) {
    if (value == _inspecting) return;
    _inspecting = value;
    // Opening the panel is itself a request — the entry on screen arrived
    // before anybody asked for its tree.
    if (value) unawaited(readTree());
  }

  /// What the entry on screen has printed, oldest first.
  ///
  /// **Its own notifier**, for the reason [watchedBox] is: a demo printing from
  /// `build` prints on every frame, and rebuilding the entry list and the top
  /// bar to append a line would be absurd. Only the console listens.
  final guestLogs = ValueNotifier<List<InspectLogLine>>(const []);

  /// How many lines the guest dropped off the front of its buffer, so the
  /// console can say the scrollback is not the beginning.
  int get logsDropped => _logsDropped;
  var _logsDropped = 0;

  /// The highest sequence already held, which is what makes taking the buffer
  /// and subscribing at the same moment safe. The two overlap by however long
  /// the round trip took; the overlap is dropped by number.
  var _lastLogSequence = 0;

  StreamSubscription<InspectLogLine>? _logStream;

  /// Bounded here as well as in the guest. The guest keeps 500; this keeps the
  /// same, so a session left open for a day holds a screenful of scrollback
  /// rather than a day of it.
  static const _logLimit = 500;

  /// Empties both ends — the console's clear button.
  ///
  /// The guest's buffer too, and not only this one: clearing the host alone
  /// would put every line straight back on the next read.
  Future<void> clearLogs() async {
    var inspect = _inspect;
    guestLogs.value = const [];
    _logsDropped = 0;
    if (inspect == null) return;
    await inspect.clearLogs();
    // Not reset to zero: the guest goes on counting from where it was, and a
    // host that started again from nothing would discard every line until the
    // guest's counter caught back up.
  }

  /// Reads the guest's buffer, then keeps up with it.
  void _startLogs() {
    var inspect = _inspect;
    if (inspect == null || _logStream != null) return;
    // Subscribed before the read, so nothing printed while the read is in
    // flight falls between the two.
    _logStream = inspect.logLines.listen(_onLogLine);
    unawaited(readLogs());
  }

  void _stopLogs() {
    unawaited(_logStream?.cancel());
    _logStream = null;
  }

  void _onLogLine(InspectLogLine line) {
    if (_disposed || line.sequence <= _lastLogSequence) return;
    _hold([...guestLogs.value, line]);
  }

  /// Keeps the last [_logLimit] of [lines], in order, and remembers how far it
  /// has got.
  ///
  /// One place, because the cap and the high-water mark were written twice —
  /// once for a pushed line and once for a pulled buffer — and a cap enforced
  /// in two places is a cap that will eventually be two different caps.
  void _hold(List<InspectLogLine> lines) {
    lines.sort((a, b) => a.sequence.compareTo(b.sequence));
    if (lines.length > _logLimit) {
      lines = lines.sublist(lines.length - _logLimit);
    }
    _lastLogSequence = lines.isEmpty ? _lastLogSequence : lines.last.sequence;
    guestLogs.value = lines;
  }

  /// Takes whatever the guest is holding that this has not seen.
  ///
  /// Called on open and after a reload, which is when the stream alone is not
  /// enough: a reload prints before anything here has subscribed.
  Future<void> readLogs() async {
    var inspect = _inspect;
    var entry = selected ?? active;
    if (inspect == null || entry == null) return;
    var report = await inspect.logs(entry.id);
    if (report == null || _disposed) return;
    _logsDropped = report.dropped;

    // **Merged and re-sorted, not appended.** The obvious version took
    // everything newer than the highest sequence held — and lost the entire
    // scrollback on open, because the stream is subscribed first and one line
    // arriving during the round trip would push the mark past every line the
    // buffer was about to deliver. What the buffer holds is history; history
    // does not go on the end.
    var known = {for (var line in guestLogs.value) line.sequence};
    var fresh = [
      for (var line in report.lines)
        if (!known.contains(line.sequence)) line,
    ];
    if (fresh.isEmpty) return;
    _hold([...guestLogs.value, ...fresh]);
  }

  /// Whether the panel is mounted at all — which is the watch's lifetime.
  ///
  /// **Deliberately wider than [inspecting].** The watch costs the guest
  /// 0.3ms a frame on the largest tree in the repo, measured, and nothing at
  /// all on a frame that is not drawn; what is expensive is the *tree read* it
  /// can ask for, and that stays behind [inspecting]. Tying the watch to the
  /// Elements tab instead would have left the Problems tab — the one place
  /// where resizing the preview genuinely changes the answer, because that is
  /// what makes a `Row` overflow or stop overflowing — with no way to know the
  /// preview had been resized at all.
  ///
  /// **Does not notify**, for the reason [inspecting] does not: the panel
  /// clears it from `dispose`.
  bool get panelOpen => _panelOpen;
  var _panelOpen = false;
  set panelOpen(bool value) {
    if (value == _panelOpen) return;
    _panelOpen = value;
    if (value) {
      _startWatch();
      _startLogs();
    } else {
      _stopWatch();
      _stopLogs();
    }
  }

  /// The box the guest last reported for [watchedNode], live.
  ///
  /// **A notifier of its own, not a field behind [notifyListeners].** This
  /// arrives sixty times a second on an animating demo, and rebuilding the
  /// whole catalog view at that rate — entry list, panel, tree and all — to
  /// move one rectangle would cost far more than the watch saves. Only the
  /// painter listens.
  final watchedBox = ValueNotifier<WatchBox?>(null);

  /// The node whose box the guest should report.
  ///
  /// Whatever the pointer is over, which is the only thing that draws a
  /// rectangle — see the overlay's own note on why a *selection* deliberately
  /// draws nothing.
  ///
  /// **Debounced, and this is the whole reason it is a setter rather than a
  /// call.** Resolving an id costs the guest a full summary-tree walk — 8ms on
  /// the largest tree in the repo, measured — so sweeping the pointer down
  /// fifty rows would spend half a second of guest time resolving forty-nine
  /// nodes nobody stopped on. Highlighting stays instant regardless: it is
  /// drawn from the tree already in hand. What waits is only the *tracking*,
  /// which matters exactly when you have come to rest.
  String? get watchedNode => _watchedNode;
  String? _watchedNode;
  Timer? _watchSettle;
  set watchedNode(String? id) {
    if (id == _watchedNode) return;
    _watchedNode = id;
    // The old box named the old node. Kept for the moment it takes to resolve
    // the new one, it would draw the previous row's rectangle around this one.
    watchedBox.value = null;
    _watchSettle?.cancel();
    _watchSettle = Timer(const Duration(milliseconds: 120), () {
      if (_disposed || !_panelOpen) return;
      if (_inspect case var inspect?) _armWatch(inspect, 'tracking a node');
    });
  }

  StreamSubscription<WatchPush>? _watch;

  /// Subscribes, then turns the guest's watch on.
  ///
  /// That order matters: the guest starts pushing the moment the extension
  /// returns, and a subscription taken afterwards misses whatever landed in
  /// between.
  void _startWatch() {
    var inspect = _inspect;
    if (inspect == null || _watch != null) return;
    _watch = inspect.watches.listen(_onWatch);
    _armWatch(inspect, 'starting the watch');
  }

  /// Turns the guest's watch on, and turns it straight back off if the panel
  /// went away while the call was in flight.
  ///
  /// Which it can be for a while at startup. `watch` is one of the *required*
  /// extensions, and [GuestVmService.requireExtension] waits for a guest that
  /// has not registered yet rather than calling it missing — so this can be
  /// mid-wait when the panel closes, and [_stopWatch]'s own `unwatch` has run
  /// and returned by the time the watch actually starts. A guest left watching
  /// for nobody pays for it every frame.
  void _armWatch(InspectClient inspect, String what) {
    _fireAndForget(
      inspect.watch(nodeId: _watchedNode).then((_) {
        if (_disposed || !_panelOpen) unawaited(inspect.unwatch());
      }),
      what,
    );
  }

  void _stopWatch() {
    _watchSettle?.cancel();
    _watchSettle = null;
    _resizeSettle?.cancel();
    _resizeSettle = null;
    unawaited(_watch?.cancel());
    _watch = null;
    watchedBox.value = null;
    // Fire and forget: a guest going away is the common case here, and the
    // tolerant form is what makes that a non-event.
    unawaited(_inspect?.unwatch());
  }

  void _onWatch(WatchPush push) {
    if (_disposed) return;
    // A push from before a switch describes a demo that is no longer on
    // screen. Not dropped in the guest, so that this can tell the difference
    // between "nothing moved" and "you are a switch behind".
    if (push.entryId != (selected ?? active)?.id) return;
    if (push.geometry case var box?) watchedBox.value = box;
    // Promptly, because a shape change is rare by nature — an animation moves
    // geometry, not structure — so there is nothing here to smooth out.
    if (push.structureChanged && _inspecting) unawaited(_rereadTree());
    if (push.resized) _settleResize();
  }

  Timer? _resizeSettle;

  /// Catches up after the preview has been given a different box.
  ///
  /// Waited out rather than acted on, because a resize is a **drag**: the size
  /// changes on every frame of it, and each one would otherwise queue a tree
  /// read and a round of error clearing for a layout the pointer has already
  /// left behind.
  ///
  /// The errors go with it, and that is the half worth explaining. The record
  /// is of what the framework *said*, and nothing ever arrives to say an
  /// overflow stopped — so a `Row` that overflowed at one width went on being
  /// listed under Problems at every width after it, including the ones where it
  /// fits. Dragging the panel divider is precisely how you make that happen,
  /// and was how it was found.
  void _settleResize() {
    _resizeSettle?.cancel();
    _resizeSettle = Timer(const Duration(milliseconds: 250), () {
      if (_disposed || !_panelOpen) return;
      if (_inspecting) unawaited(_rereadTree());
      unawaited(forgetErrors());
    });
  }

  var _treeReading = false;
  var _treeReadPending = false;

  /// Re-reads the tree, at most one read at a time.
  ///
  /// The guest's structure push is a flag and costs it nothing; the read it
  /// asks for costs **17ms on the largest tree in the repo**, measured. So a
  /// demo whose shape moves on every frame — a list ticking, a menu animating
  /// open — would queue reads faster than they complete and never catch up.
  /// Coalescing here rather than debouncing in the guest keeps the decision
  /// where the cost is: the guest cannot know this reader is still busy.
  Future<void> _rereadTree() async {
    if (_treeReading) {
      _treeReadPending = true;
      return;
    }
    _treeReading = true;
    try {
      do {
        _treeReadPending = false;
        await readTree();
      } while (_treeReadPending && !_disposed && _inspecting);
    } finally {
      _treeReading = false;
    }
  }

  /// What the guest says is under a point, innermost last.
  ///
  /// The authoritative half of the picker. [InspectTree.nodeAtPoint] answers
  /// the same question from rectangles alone and answers it every frame, which
  /// is what the highlight follows; this runs the framework's own `hitTest`
  /// over the real render tree and is what a *click* commits to. Optimistic
  /// while you move, correct when you choose.
  ///
  /// Null when there is no guest or nothing of the demo is under the point —
  /// which is an answer, not a failure.
  Future<String?> nodeUnder(double x, double y) async {
    var inspect = _inspect;
    if (inspect == null) return null;
    var ids = await inspect.hitTest(x, y);
    return ids.isEmpty ? null : ids.last;
  }

  /// Forgets what the entry has reported, then reads it back.
  ///
  /// What the panel's refresh does, and what a reload does before it rebuilds.
  /// Nothing ever arrives to say a problem *stopped* — an overflow that a
  /// resize fixed goes on being reported, because the record is of what was
  /// said rather than of what is true now — so forgetting has to be somebody's
  /// decision, and it belongs to whoever asked for the rebuild.
  ///
  /// The read that follows will usually come back empty and fill again on the
  /// next poll, which is honest: the frame that would re-report has not been
  /// painted yet.
  Future<void> forgetErrors() async {
    var inspect = _inspect;
    if (inspect == null) return;
    await inspect.clearErrors();
    if (_disposed) return;
    renderErrors = null;
    notifyListeners();
    await readErrors();
  }

  /// Asks the guest what the entry on screen reported.
  ///
  /// The guest forgets the previous entry's errors when it switches, so this
  /// describes this demo rather than the one before it.
  Future<void> readErrors() async {
    var inspect = _inspect;
    var entry = selected ?? active;
    if (inspect == null || entry == null) return;
    var report = await inspect.errors(entry.id);
    if (report == null || _disposed) return;
    renderErrors = report;
    notifyListeners();
  }

  /// Asks the guest for the tree of the entry on screen.
  ///
  /// Public because the panel offers a refresh: a demo's own state moves
  /// without anything here being told — you tapped, a menu opened — and until
  /// the watch lands (S5e) pressing the button is how the tree catches up.
  Future<void> readTree() async {
    var inspect = _inspect;
    var entry = selected ?? active;
    if (inspect == null || entry == null) return;
    var read = await inspect.tree(entry.id);
    if (read == null || _disposed) return;
    tree = read;
    notifyListeners();
  }

  /// What the address asks each of the shell's axes to be, as slugs.
  ///
  /// A **request**, like [wantedEntryId], and for the same reason: which axes
  /// exist is something only the guest can say, and it cannot say it until the
  /// shell has built. So this is written whenever the address moves and
  /// resolved whenever resolving becomes possible.
  ///
  /// Slugs rather than the labels the guest wants — see [catalog_params.dart].
  /// Turning one into the other needs the declaration, which arrives later.
  Map<String, String> get axisSelections => _axisSelections;
  var _axisSelections = const <String, String>{};

  set axisSelections(Map<String, String> value) {
    if (mapEquals(value, _axisSelections)) return;
    _axisSelections = Map.unmodifiable(value);
    // Deliberately silent. This is written while the view is building — the
    // address is a dependency, so it arrives in `didChangeDependencies` — and
    // notifying there would mark the builder listening to this session dirty
    // mid-build. Nothing needs the notification anyway: the controls draw from
    // the address, not from here, and the guest is told below.
    //
    // Read back afterwards, like a knob: a shell's build decides what axes
    // exist, and setting one can reveal or retire another.
    _fireAndForget(_pushAxes().then((_) => _readAxes()), 'setting an axis');
  }

  /// What the address asks each of the entry's knobs to be, as slugs.
  ///
  /// The same shape as [axisSelections] and for the same reasons — a request
  /// resolved once the declaration arrives — differing only in lifetime. A knob
  /// belongs to the entry, so these go when the entry does; an axis belongs to
  /// the shell and does not.
  Map<String, String> get knobSelections => _knobSelections;
  var _knobSelections = const <String, String>{};

  set knobSelections(Map<String, String> value) {
    if (mapEquals(value, _knobSelections)) return;
    _knobSelections = Map.unmodifiable(value);
    // Silent, and read back afterwards — see [axisSelections].
    _fireAndForget(_pushKnobs(), 'turning a knob');
  }

  /// The last payload sent, encoded, so a switch that changes nothing costs no
  /// frame. Starts as the empty selection, which is what a guest begins with.
  var _pushed = '{}';

  /// Everything discovery found, broken or not, in discovery's own order.
  ///
  /// Sorted by id because that is how the scanner sorts, so merging the two
  /// lists puts a quarantined entry back exactly where it was rather than in a
  /// section of its own. A demo you are midway through editing should not move.
  List<CatalogEntry> get allEntries =>
      [...entries, ...quarantined.map((q) => q.entry)]
        ..sort((a, b) => a.id.compareTo(b.id));

  /// The compiler's complaint about [entry], or null if it builds.
  String? compileErrorFor(CatalogEntry entry) {
    for (var broken in quarantined) {
      if (broken.entry.id == entry.id) return broken.error;
    }
    // Still broken as far as anybody knows. Asking for a quarantined entry
    // *is* the retry, so the daemon drops it from the quarantine and announces
    // that **before it has compiled anything** — which left the row looking
    // healthy for the several seconds the compile took, and then changing its
    // mind. Not a flicker: a claim, held long enough to read, that we had no
    // reason to make.
    //
    // So the last known error stands until the retry has actually decided. If
    // it compiles, nothing re-quarantines it and the marker goes for good; if
    // it does not, the announcement arrives before the switch returns and the
    // list above answers again.
    if (_retrying?.$1 == entry.id) return _retrying?.$2;
    return null;
  }

  /// The entry whose quarantine is being retried, and the error it had.
  (String, String)? _retrying;

  /// Why [selected] is not what the guest is showing, or null when it is.
  ///
  /// Covers both ways that happens: the entry does not compile, or it compiled
  /// and the reload was refused. Either way the guest keeps rendering the last
  /// thing that worked, and this is the text that explains the difference.
  String? get selectedError {
    var entry = selected;
    if (entry == null) return null;
    if (compileErrorFor(entry) case var error?) return error;
    var report = lastSwitch;
    if (report != null && report.entry.id == entry.id && !report.ok) {
      return report.error;
    }
    return null;
  }

  EmbeddedEngine? get engine => _engine;
  EmbeddedEngine? _engine;

  CompilerDaemonClient? _daemon;
  GuestVmService? _vmService;

  /// The inspection reads and writes, shared with the headless path that `fw`
  /// and MCP go through — see [InspectClient]. Impatient compared with that
  /// one: this session drove the reload itself, so it is waiting only on the
  /// frame after it rather than on a whole cold build.
  InspectClient? _inspect;

  /// Whether this session announced itself — so a teardown that never got as
  /// far as a guest does not delete a handle belonging to another window.
  var _published = false;
  StreamSubscription<CatalogChanged>? _changes;
  Future<void> _queue = Future.value();
  bool _disposed = false;

  /// What the session is busy doing, or null when it is idle. A steady word,
  /// not a number: this is what a sidebar shows while the compiler works, and a
  /// figure that changes every second reads as movement rather than as news.
  String? get busyWith => _busyWith;
  String? _busyWith;

  /// How long the current [busyWith] has been running.
  ///
  /// Only counts up on screen where a counter is the point — the cold-start
  /// screen, which is a spinner and nothing else.
  Duration get busyFor => _busySince.elapsed;
  final _busySince = Stopwatch();
  Timer? _ticker;

  /// [tick] rebuilds listeners each second so an elapsed readout advances. Off
  /// by default: everywhere but a dedicated loading screen, the label alone
  /// says what is happening and its disappearance says when it stopped.
  void _busy(String what, {bool tick = false}) {
    if (_disposed) return;
    _busyWith = what;
    _busySince
      ..reset()
      ..start();
    _ticker?.cancel();
    _ticker = !tick
        ? null
        : Timer.periodic(const Duration(seconds: 1), (_) {
            if (!_disposed && _busyWith != null) notifyListeners();
          });
    notifyListeners();
  }

  void _idle() {
    _busyWith = null;
    _busySince.stop();
    _ticker?.cancel();
    _ticker = null;
    if (!_disposed) notifyListeners();
  }

  /// Brings up the daemon, the guest and the reload channel.
  Future<void> start({int width = 900, int height = 700}) async {
    // The one place a counter earns its keep: a cold compile is tens of seconds
    // behind a spinner, and the screen has nothing else on it.
    _busy('building', tick: true);
    try {
      var (daemon, ready) = await CompilerDaemonClient.connect(
        dartExecutable: p.join(flutterSdkRoot, 'bin', 'dart'),
        // Through the shared builder, so this panel and `fw run ui_catalog`
        // arrive at the same socket. See [DaemonConfig.forPackage] for what
        // happened when each side built its own.
        config: DaemonConfig.forPackage(
          appToolDirectory: appPackageRoot,
          packageRoot: projectRoot,
          flutterSdkRoot: flutterSdkRoot,
          roots: roots,
        ),
        onLog: (line) => debugPrint('[catalog] $line'),
      );
      _daemon = daemon;
      coldCompile = ready.coldCompile;
      entries = ready.entries;
      quarantined = ready.quarantined;
      diagnostics = ready.diagnostics;
      _changes = daemon.catalogChanges.listen(_onCatalogChanged);
      // Then whatever changed between the handshake and that subscription. The
      // ready message is a snapshot of the moment the daemon prepared, which for
      // a client attaching to a daemon that has been up a while is not the same
      // as now — another client's compile may have quarantined an entry since,
      // and the notice for it was addressed to a listener that did not exist yet.
      if (daemon.lastChange case var missed?) _onCatalogChanged(missed);
      if (_disposed) return;

      // What the address asked for if the daemon turned out to have it, else
      // the first — the fallback is for an address that named no entry, not a
      // correction of one that named the wrong entry.
      var first = wantedEntry ?? entries.first;
      // Compiled before the guest exists, and whole.
      //
      // A session's bundle symlinks the kernel the daemon compiled when it
      // *started*, which lets a client that has just attached launch without
      // paying for a compile. What it costs is that the first frame is neither
      // necessarily this entry — the daemon prepared whichever one was first —
      // nor necessarily this source: every compile since has been a delta hot
      // reloaded into a guest that was already up, and nothing rewrites the
      // kernel a new guest boots from. So a panel opened against a daemon that
      // has been running a while names one entry and renders another, or renders
      // this one as it was written some edits ago, and then silently corrects
      // itself the first time anything reloads.
      //
      // Asking for a whole kernel first is what closes that: ~40ms on a warm
      // daemon, once per session, and it is what `HeadlessCatalog` has always
      // done before it launches a guest.
      var compiled = await daemon.select(first.id, full: true);
      if (_disposed) return;

      var engine = _engine = EmbeddedEngine(
        appPackageRoot: appPackageRoot,
        flutterSdkRoot: flutterSdkRoot,
        // Keyed by session, so a second panel — or an agent taking a
        // screenshot — does not bind over this guest's socket.
        name: ready.sessionId,
        buildGuest: () async => (
          hostPath: ready.hostPath,
          assetsDir: ready.assetsDir,
          icuData: ready.icuData,
        ),
      );
      engine.addListener(_onEngineChanged);
      await engine.start(width: width, height: height);
      if (_disposed) return;

      var vmService = _vmService = await GuestVmService.connect(
        await engine.vmServiceUri,
      );
      _inspect = InspectClient(
        vmService,
        patience: InspectPatience.live,
        abandoned: () => _disposed,
      );
      // The panel usually mounts *before* this — a cold start puts it on screen
      // with a spinner while the daemon compiles — and both of these need a
      // client to attach to. Asked for once at mount and once here, because
      // either can be the one that comes second; both are idempotent.
      if (_panelOpen) {
        _startWatch();
        _startLogs();
      }
      // Announced only now: a URI published before the service answers is a
      // URI that fails to connect. From here on `fw` and an agent can read the
      // entry on screen rather than rendering their own copy of it.
      LiveSession.publish(
        LiveSession(
          projectRoot: projectRoot,
          vmServiceUri: await engine.vmServiceUri,
          pid: pid,
        ),
      );
      _published = true;
      if (_disposed) return;

      selected = first;
      // [active] is what the guest actually holds. A demo that did not compile
      // leaves it on the daemon's own kernel, so naming this entry there would
      // be a claim the status bar goes on repeating; the report below is what
      // puts the compiler's error where the widget would have been.
      if (compiled.ok) {
        active = first;
      } else {
        lastSwitch = SwitchReport(
          entry: first,
          compile: compiled.compile,
          reload: Duration.zero,
          newSourceCount: compiled.newSourceCount,
          editedCount: compiled.editedCount,
          error: compiled.error,
        );
      }
      phase = CatalogSessionPhase.ready;
      _idle();
    } catch (e) {
      _fail('$e');
    }
  }

  /// Switches the guest to [entry] by hot reload.
  ///
  /// Switches are serialised: the daemon and the isolate each tolerate one
  /// in-flight operation, and a click-happy user must not interleave them.
  Future<void> switchTo(CatalogEntry entry, {bool ifChanged = false}) {
    // **Selected now, not when the compile finishes.** [selected] is what the
    // user last *asked for*, and asking happens here; assigning it at the far
    // end of the queue left a window where everything else read the previous
    // entry as the current intent.
    //
    // That window was a real bug, not a tidiness point. Opening the catalog at
    // an address queues a switch, and then `CatalogView` mounts and reloads
    // "whatever is selected" — which was still the entry before it. The reload
    // queued *behind* the address's switch and won, so arriving from search
    // landed on the last entry you had open, but only when the panel was not
    // already mounted.
    var previous = selected;
    // Remembered before anything moves: selecting a quarantined entry is how
    // you ask the daemon to try again, and the row must go on saying so until
    // it has. See [compileErrorFor].
    if (compileErrorFor(entry) case var error?) _retrying = (entry.id, error);
    selected = entry;
    // **And this is now what the address wants**, said here rather than waited
    // for. The panel writes the address back from a *post-frame callback*, so
    // between a click and the next frame boundary `_wantedEntryId` still names
    // the entry you came from — and anything that calls [_applyWanted] in that
    // window switches you back to it.
    //
    // Which is a race the daemon is unusually good at winning. Asking for a
    // **quarantined** entry *is* the retry, so the daemon drops it from the
    // quarantine and announces the change immediately, before it has compiled
    // anything (`compiler_daemon.dart:550`). That announcement arrives as a
    // `CatalogChanged`, `_onCatalogChanged` calls `_applyWanted`, and if the
    // frame has not turned over yet your click is undone. Whether it has is a
    // coin toss, which is exactly how it presented: clicking the entry that
    // does not compile takes somewhere between four and eight goes, at random.
    //
    // Selecting *is* wanting. Saying so closes the window without changing
    // what any of it means, and the address write that follows sets the same
    // value, which the setter already treats as nothing.
    _wantedEntryId = entry.id;
    // **And say so now.** Setting the field without this left the click
    // invisible until the queue reached [_switchTo] and `_busy` notified —
    // which for an entry the daemon has quarantined means waiting out a *fresh
    // compile attempt*, seconds of it. Nothing moved, so you clicked again,
    // which queued another compile behind the first. Five clicks, five
    // compiles, and the selection finally appearing looked like the fifth one
    // having worked.
    //
    // The comment above was already right that `selected` is what the user
    // asked for and that asking happens here. It just never told anybody.
    notifyListeners();
    _queue = _queue
        .then((_) => _switchTo(entry, previous: previous, ifChanged: ifChanged))
        .catchError((Object e) {
          _fail('$e');
        });
    return _queue;
  }

  /// Sends the entry's knobs what the address asks of them, and reads back
  /// what the demo made of it.
  ///
  /// **Coalesced, not queued.** A slider writes a value per frame of a drag,
  /// and each push is a round trip that waits for the guest's frame. Sent
  /// concurrently they land out of order — a slider that jumps backwards under
  /// the pointer; sent one at a time in a queue, the drag finishes seconds
  /// after your hand does. So one is in flight at a time and the rest is
  /// simply the latest state, which the address already holds: whatever the
  /// push catches up with is what gets sent.
  ///
  /// That works because a push is the *whole* set rather than a change. There
  /// is nothing to miss by skipping an intermediate value.
  Future<void> _pushKnobs() async {
    if (_pushingKnobs) return;
    _pushingKnobs = true;
    try {
      String? sent;
      while (true) {
        var inspect = _inspect;
        if (inspect == null) return;
        var payload = jsonEncode(paramPayloadFor(knobs.knobs, _knobSelections));
        if (payload == sent || payload == _pushedKnobs) break;
        sent = payload;
        _pushedKnobs = payload;
        await inspect.setKnobs(payload);
        if (_disposed) return;
      }
      // Once, after the last one: a demo's build decides what knobs exist, so
      // turning one can reveal or retire another — but only the settled state
      // is worth drawing.
      await _readKnobs();
      // And which *widgets* exist, which is the same fact one layer down —
      // and whether the build that produced them complained.
      await readErrors();
      if (_inspecting) await readTree();
    } finally {
      _pushingKnobs = false;
    }
  }

  var _pushingKnobs = false;

  /// The last payload sent, so a push that would repeat itself costs nothing.
  var _pushedKnobs = '';

  /// Sends the shell on screen what the address asked for, in the labels it
  /// declared.
  ///
  /// Resolved here rather than held anywhere: [axisSelections] is slugs, the
  /// guest wants labels, and only the declaration joins the two. So this is
  /// recomputed on every push and nothing can fall out of step with the
  /// address.
  ///
  /// Only the shell on screen. This used to send every shell it had ever seen,
  /// so that one building for the first time had its values in hand rather than
  /// showing a frame of defaults first — but that needed a store of selections
  /// per shell, which is the thing the address replaced. A shell appearing for
  /// the first time now shows its defaults for one frame and is corrected as
  /// soon as it says what it declares.
  Future<void> _pushAxes() async {
    var inspect = _inspect;
    var shellId = axes.shellId;
    if (inspect == null || shellId == null) return;
    // Compared encoded rather than with [mapEquals], which is shallow: the
    // payload is a map of maps, and a fresh copy of an unchanged one is a
    // different object every time.
    var payload = jsonEncode({
      shellId: paramPayloadFor(axes.axes, _axisSelections),
    });
    if (payload == _pushed) return;
    _pushed = payload;
    await inspect.setAxes(payload);
  }

  /// Asks the guest what the shell on screen offers.
  ///
  /// Retried while the report names another *entry*, exactly as a knob read is,
  /// and for the same reason: the axes are recorded by the shell's build, so a
  /// read landing between the reload and the frame describes what was there
  /// before. Matching on the entry rather than the shell is what lets an entry
  /// whose wrapper is not a shell settle — it reports no shell and no axes, and
  /// that is an answer rather than something to keep waiting for.
  Future<void> _readAxes() async {
    var inspect = _inspect;
    var entryId = (selected ?? active)?.id;
    if (inspect == null || entryId == null) return;
    var report = await inspect.axes(entryId);
    // The guest never named this entry, or has no such extension. Either way
    // what is held describes a build nobody has replaced, so leave it.
    if (report == null || _disposed) return;
    axes = report;
    notifyListeners();
    // The shell may only just have said who it is. Nothing could be pushed
    // before that — [_pushAxes] needs a shell id — so a selection made while
    // the previous entry was on screen would otherwise never reach this one.
    // Self-dedupes when there is nothing new to send.
    await _pushAxes();
  }

  /// Asks the guest what the entry on screen offers.
  ///
  /// Retried while the report names another entry: the knobs are recorded by
  /// the demo's *build*, so a read that lands between the reload and the frame
  /// describes the entry that was there before. Giving up quietly after a few
  /// tries beats a panel that spins.
  Future<void> _readKnobs() async {
    var inspect = _inspect;
    var entry = selected;
    if (inspect == null || entry == null) return;
    var report = await inspect.knobs(entry.id);
    if (report == null || _disposed) return;
    knobs = report;
    notifyListeners();
  }

  /// Rebuilds what is on screen from the files as they are now.
  ///
  /// Literally a switch to the entry already selected: the daemon sweeps for
  /// edits on every request, so re-selecting is the whole of a reload — and
  /// because the daemon retries a quarantined entry on request, this is also
  /// how a demo that stopped compiling is asked again.
  ///
  /// Explicit rather than automatic on save: nothing watches the project yet,
  /// and a catalog that reloads itself mid-refactor is its own annoyance.
  Future<void> reload() async {
    var entry = selected ?? active;
    if (entry == null) return;
    // Forgotten first, because the guest only resets its own record when the
    // *entry* changes — a reload of the one already on screen would otherwise
    // keep reporting the problem you have just been fixing. You edit, reload,
    // and the fixed overflow is still in the list.
    await forgetErrors();
    await switchTo(entry);
  }

  /// Asks the daemon whether entries have appeared or disappeared.
  ///
  /// Deliberately not a [reloadIfChanged]: this runs on a timer while you are
  /// looking at the panel, and a catalog that reloaded itself every few
  /// seconds — resetting the demo's state mid-refactor — is the thing we chose
  /// not to build. This notices new *entries* and nothing else.
  void refresh() => _daemon?.refresh();

  /// A [reload] that costs nothing when nothing was edited.
  ///
  /// For the triggers the user did not press — coming back to the window, or
  /// to the panel. The daemon answers `unchanged` rather than working, so the
  /// guest is not reassembled and the demo keeps whatever state it was holding;
  /// alt-tabbing must not be a way to lose your place.
  Future<void> reloadIfChanged() {
    var entry = selected ?? active;
    if (entry == null || phase != CatalogSessionPhase.ready) {
      return Future.value();
    }
    return switchTo(entry, ifChanged: true);
  }

  Future<void> _switchTo(
    CatalogEntry entry, {
    required CatalogEntry? previous,
    required bool ifChanged,
  }) async {
    var daemon = _daemon;
    var vmService = _vmService;
    if (_disposed ||
        phase != CatalogSessionPhase.ready ||
        daemon == null ||
        vmService == null) {
      return;
    }

    // Told apart by where the user already was, so that asking again for the
    // entry on screen — or for the broken one they are fixing — reports what it
    // did rather than what a switch would have done.
    //
    // Against the selection as it stood when this was *asked for*, handed down
    // by [switchTo]: `selected` has already moved to `entry` by the time this
    // runs, so reading it here would call every switch a reload.
    var reloaded = entry.id == previous?.id || entry.id == active?.id;
    // Nothing to do about the device here any more. This used to push the
    // entry's `formFactor` into the staging, guarded so a reload would not undo
    // a pick — a mutation, an ordering rule, and a whole class of bug. The
    // entry's declaration is now a *default* read at build time behind whatever
    // the address says, so a switch changes what is on screen simply by
    // changing which entry is selected.
    _busy(reloaded ? 'reloading' : 'compiling');
    try {
      await _switchOnce(
        daemon,
        vmService,
        entry,
        reloaded: reloaded,
        ifChanged: ifChanged,
      );
    } finally {
      // Whatever it decided, the answer is in [quarantined] now — the daemon
      // re-files a failure before the request it came from returns.
      if (_retrying?.$1 == entry.id) _retrying = null;
      _idle();
    }
  }

  Future<void> _switchOnce(
    CompilerDaemonClient daemon,
    GuestVmService vmService,
    CatalogEntry entry, {
    required bool reloaded,
    required bool ifChanged,
  }) async {
    var compiled = await daemon.select(entry.id, ifChanged: ifChanged);
    // Nothing on disk moved. Leave everything alone — including [lastSwitch],
    // which still describes the last thing that actually happened.
    if (compiled.unchanged) return;
    if (!compiled.ok) {
      // The guest keeps rendering the previous entry; a broken demo is a
      // reportable event, not the end of the session.
      lastSwitch = SwitchReport(
        entry: entry,
        compile: compiled.compile,
        reload: Duration.zero,
        newSourceCount: compiled.newSourceCount,
        editedCount: compiled.editedCount,
        reloaded: reloaded,
        error: compiled.error,
      );
      notifyListeners();
      return;
    }

    // Before the reload, not after: the shell reads its axes as it builds, so
    // a push that landed afterwards would mean one frame rendered with the
    // previous shell's selections and then a second correcting it.
    await _pushAxes();

    var watch = Stopwatch()..start();
    try {
      await vmService.reload(compiled.dill!);
    } catch (e) {
      // A refused reload leaves the guest exactly as it was, still rendering
      // the previous entry, so this is reportable rather than fatal — the same
      // rule a failed compile already follows. Ending the session would throw
      // away a working engine over one bad switch.
      lastSwitch = SwitchReport(
        entry: entry,
        compile: compiled.compile,
        reload: watch.elapsed,
        newSourceCount: compiled.newSourceCount,
        editedCount: compiled.editedCount,
        reloaded: reloaded,
        error: 'hot reload was refused: $e',
      );
      notifyListeners();
      return;
    }
    watch.stop();

    active = entry;
    unawaited(_readKnobs());
    unawaited(_readAxes());
    // Not gated on the panel: this is what puts a badge on the Problems tab,
    // and a demo that throws should say so whether or not you were looking.
    unawaited(readErrors());
    if (_inspecting) unawaited(readTree());
    // The guest cleared its own buffer on the switch, so this one has to go
    // too — otherwise the console reads as the new demo having printed what the
    // old one did. The sequence mark is deliberately *not* reset: the guest
    // goes on counting, and starting again from nothing here would discard
    // every line until its counter caught back up.
    guestLogs.value = const [];
    _logsDropped = 0;
    // A reload prints before anything has had a chance to hear it — the stream
    // is live, but the lines the demo wrote while starting are already in the
    // buffer and nowhere else.
    if (_panelOpen) unawaited(readLogs());
    lastSwitch = SwitchReport(
      entry: entry,
      compile: compiled.compile,
      reload: watch.elapsed,
      newSourceCount: compiled.newSourceCount,
      editedCount: compiled.editedCount,
      reloaded: reloaded,
    );
    notifyListeners();
  }

  /// The daemon serves several clients, so the set of buildable entries can
  /// move without this session having asked for anything — somebody edits a
  /// demo and it breaks, or they fix it and it comes back.
  void _onCatalogChanged(CatalogChanged change) {
    entries = change.entries;
    quarantined = change.quarantined;

    // An entry that stopped *compiling* keeps its place and stays selected —
    // the panel says why it is not rendering, and moving the user somewhere
    // else is what made a typo feel like losing your place.
    //
    // An entry that stopped *existing* is a different thing: it was deleted or
    // renamed, there is nothing to go back to, and staying on it would leave
    // the guest showing something the catalog no longer lists.
    var selectedId = selected?.id;
    if (selectedId != null &&
        !allEntries.any((e) => e.id == selectedId) &&
        entries.isNotEmpty) {
      unawaited(switchTo(entries.first));
    }

    // An entry the address asked for may have only just appeared — somebody
    // finished writing the demo the link points at. This is the second half of
    // "a request, not a call".
    if (phase == CatalogSessionPhase.ready) _applyWanted();
    notifyListeners();
  }

  void _onEngineChanged() {
    if (_engine?.phase == EmbeddedEnginePhase.error) {
      _fail(_engine!.errorMessage ?? 'the embedder guest failed');
    } else {
      notifyListeners();
    }
  }

  /// Runs [work] with nobody waiting on it, and says so if it fails.
  ///
  /// The panel drives the guest from setters and timers — an address changing,
  /// a pointer coming to rest — where there is no caller left to hand a failure
  /// to. `unawaited` alone hands it to the zone instead, which prints
  /// `Unhandled Exception` and a stack trace; and since these are the *required*
  /// writes rather than the tolerant reads (see [InspectClient.watch] for why
  /// they are required), throwing is something they genuinely do.
  ///
  /// Reported rather than swallowed, which is the whole point of those calls
  /// being strict: a watch that never started looks exactly like a demo that is
  /// not moving, and this is the line that tells the two apart.
  void _fireAndForget(Future<void> work, String what) {
    unawaited(
      work.then<void>(
        (_) {},
        onError: (Object e) {
          if (_disposed) return;
          debugPrint('[catalog] $what: $e');
        },
      ),
    );
  }

  void _fail(String message) {
    if (_disposed) return;
    // Also to stdout: a failure that only lands in the UI is invisible to
    // whoever is driving the harness through `flutter run`.
    debugPrint('[catalog] failed: $message');
    errorMessage = message;
    phase = CatalogSessionPhase.error;
    _idle();
  }

  @override
  void dispose() {
    _disposed = true;
    _ticker?.cancel();
    _watchSettle?.cancel();
    _resizeSettle?.cancel();
    unawaited(_watch?.cancel());
    unawaited(_logStream?.cancel());
    watchedBox.dispose();
    guestLogs.dispose();
    browsing
      ..removeListener(notifyListeners)
      ..dispose();
    staging
      ..removeListener(notifyListeners)
      ..dispose();
    _engine?.removeListener(_onEngineChanged);
    _engine?.dispose();
    // Withdraw the invitation before the guest goes. A handle left behind is
    // not fatal — the next reader fails to connect and deletes it — but it
    // costs that reader a timeout, and this session is the one thing that
    // knows for certain the guest is going away.
    if (_published) LiveSession.clear(projectRoot);
    unawaited(_vmService?.close());
    unawaited(_changes?.cancel());
    unawaited(_daemon?.close());
    super.dispose();
  }
}
