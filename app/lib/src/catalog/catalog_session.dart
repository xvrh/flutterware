import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutterware/ui_catalog.dart';
import 'package:path/path.dart' as p;

import '../embedder/embedded_engine.dart';
import '../embedder/guest_vm_service.dart';
import 'catalog_params.dart';
import 'devices.dart';
import 'catalog_entry.dart';
import 'compiler_daemon_client.dart';
import 'package_config_locator.dart';
import 'protocol.dart';

enum CatalogSessionPhase { starting, ready, error }

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
    unawaited(_pushAxes().then((_) => _readAxes()));
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
    unawaited(_pushKnobs());
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
    return null;
  }

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
        config: DaemonConfig(
          appPackageRoot: appPackageRoot,
          projectRoot: projectRoot,
          // The *project's* config, not the GUI's: it is the one that resolves
          // the demos' own package as well as flutter and flutterware.
          packageConfig: requirePackageConfig(projectRoot),
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

      _vmService = await GuestVmService.connect(await engine.vmServiceUri);
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
    selected = entry;
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
        var vmService = _vmService;
        if (vmService == null) return;
        var payload = jsonEncode(paramPayloadFor(knobs.knobs, _knobSelections));
        if (payload == sent || payload == _pushedKnobs) break;
        sent = payload;
        _pushedKnobs = payload;
        await vmService.callExtension(
          'ext.flutterware.setParameters',
          args: {'payload': payload},
        );
        if (_disposed) return;
      }
      // Once, after the last one: a demo's build decides what knobs exist, so
      // turning one can reveal or retire another — but only the settled state
      // is worth drawing.
      await _readKnobs();
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
    var vmService = _vmService;
    var shellId = axes.shellId;
    if (vmService == null || shellId == null) return;
    // Compared encoded rather than with [mapEquals], which is shallow: the
    // payload is a map of maps, and a fresh copy of an unchanged one is a
    // different object every time.
    var payload = jsonEncode({
      shellId: paramPayloadFor(axes.axes, _axisSelections),
    });
    if (payload == _pushed) return;
    _pushed = payload;
    await vmService.callExtension(
      'ext.flutterware.setAxes',
      args: {'payload': payload},
    );
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
    var vmService = _vmService;
    var entryId = (selected ?? active)?.id;
    if (vmService == null || entryId == null) return;
    for (var attempt = 0; attempt < 10; attempt++) {
      var json = await vmService.callExtension('ext.flutterware.axes');
      if (_disposed) return;
      if (json == null) return; // A guest from before the extension existed.
      var report = AxisReport.fromJson(json);
      if (report.entryId == entryId) {
        axes = report;
        notifyListeners();
        // The shell may only just have said who it is. Nothing could be pushed
        // before that — [_pushAxes] needs a shell id — so a selection made
        // while the previous entry was on screen would otherwise never reach
        // this one. Self-dedupes when there is nothing new to send.
        await _pushAxes();
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 30));
    }
  }

  /// Asks the guest what the entry on screen offers.
  ///
  /// Retried while the report names another entry: the knobs are recorded by
  /// the demo's *build*, so a read that lands between the reload and the frame
  /// describes the entry that was there before. Giving up quietly after a few
  /// tries beats a panel that spins.
  Future<void> _readKnobs() async {
    var vmService = _vmService;
    var entry = selected;
    if (vmService == null || entry == null) return;
    for (var attempt = 0; attempt < 10; attempt++) {
      var json = await vmService.callExtension('ext.flutterware.parameters');
      if (_disposed) return;
      if (json == null) return; // A guest without the extension: no knobs.
      var report = KnobReport.fromJson(json);
      if (report.entryId == entry.id) {
        knobs = report;
        notifyListeners();
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 30));
    }
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
  Future<void> reload() {
    var entry = selected ?? active;
    return entry == null ? Future.value() : switchTo(entry);
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
    browsing
      ..removeListener(notifyListeners)
      ..dispose();
    staging
      ..removeListener(notifyListeners)
      ..dispose();
    _engine?.removeListener(_onEngineChanged);
    _engine?.dispose();
    unawaited(_vmService?.close());
    unawaited(_changes?.cancel());
    unawaited(_daemon?.close());
    super.dispose();
  }
}
