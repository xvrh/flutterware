import 'dart:async';
import 'dart:convert';

import 'package:device_frame/device_frame.dart';
import 'package:flutter/foundation.dart';
import 'package:flutterware/ui_catalog.dart';
import 'package:path/path.dart' as p;

import '../embedder/embedded_engine.dart';
import '../embedder/guest_vm_service.dart';
import 'catalog_entry.dart';
import 'compiler_daemon_client.dart';
import 'shell_descriptor.dart';
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
  /// The device the guest is sized to, or null to fill the panel.
  DeviceInfo? get device => _device;
  DeviceInfo? _device;
  set device(DeviceInfo? value) {
    if (value?.identifier == _device?.identifier) return;
    _device = value;
    notifyListeners();
  }

  /// Sets the device the entry asks for, if it asks for one.
  ///
  /// `@Demo(formFactor: FormFactor.mobile)` is the author saying what this
  /// entry is *for*, so arriving at it should show it that way — which is what
  /// the enum meant in the previous catalog, where it picked the toolbar's
  /// device bucket. An explicit pick lasts until the next entry that has an
  /// opinion; `all` is an entry saying it has none, and means the panel.
  void followEntry(String? formFactor) {
    switch (formFactor) {
      case 'mobile':
        device = Devices.ios.iPhone13;
      case 'desktop':
        device = Devices.macOS.macBookPro;
      case 'all':
        device = null;
      default:
        break; // No opinion: leave whatever is on screen alone.
    }
  }

  /// Whether the device's chrome is drawn around the screen. Off leaves a
  /// plain rectangle of the right size, which is what you want once you are
  /// looking at the layout rather than at the phone.
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

/// What each shell's axes are set to, which is the host's to remember.
///
/// Keyed by shell rather than by entry, and that is the whole difference
/// between an axis and a knob: moving between entries that share a shell
/// changes nothing, and coming back to a shell finds what you had chosen.
class ShellSelections {
  final _byShell = <String, Map<String, Object?>>{};

  /// Null means the default the signature declares.
  void choose(String shellId, String name, Object? value) {
    (_byShell[shellId] ??= {})[name] = value;
  }

  Object? chosen(String shellId, String name) => _byShell[shellId]?[name];

  /// What to send the guest for [shell].
  ///
  /// Every axis it declares is named, with a null for the ones nothing has
  /// chosen. The nulls are the point: the guest keys selections by axis name
  /// alone, so two shells that both call something `flavor` would otherwise
  /// inherit each other's — and a null is the instruction to go back to the
  /// signature's default rather than merely the absence of one.
  Map<String, Object?> payloadFor(ShellDescriptor shell) {
    var chosen = _byShell[shell.id] ?? const <String, Object?>{};
    return {for (var axis in shell.axes) axis.name: chosen[axis.name]};
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

  SwitchReport? lastSwitch;
  Duration? coldCompile;

  /// The controls the entry on screen declared while it built, or an empty
  /// report for one that declares none.
  KnobReport knobs = KnobReport.empty;

  /// Every `@CatalogShell` discovery found. A shell decides what the top bar
  /// offers, so an entry with none has a bare one.
  List<ShellDescriptor> shells = const [];

  /// The axes the shell on screen declared, with what each is set to.
  ///
  /// Read from the guest rather than derived from [shells] because a signature
  /// carries a type name and not what its values are called — the guest is
  /// handed the enum itself and reports from there.
  AxisReport axes = AxisReport.empty;

  /// What each shell is set to. Host state, and the reason an axis outlives an
  /// entry — see [ShellSelections].
  final selections = ShellSelections();

  /// The last payload sent, so a switch that changes nothing costs no frame.
  Map<String, Object?>? _pushed;

  ShellDescriptor? get _activeShell {
    var shellId = (selected ?? active)?.shellId;
    if (shellId == null) return null;
    for (var shell in shells) {
      if (shell.id == shellId) return shell;
    }
    return null;
  }

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
      shells = ready.shells;
      diagnostics = ready.diagnostics;
      _changes = daemon.catalogChanges.listen(_onCatalogChanged);
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

      active = selected = entries.first;
      staging.followEntry(entries.first.formFactor);
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
    _queue = _queue
        .then((_) => _switchTo(entry, ifChanged: ifChanged))
        .catchError((Object e) {
          _fail('$e');
        });
    return _queue;
  }

  /// Sets a knob and rebuilds the demo in place.
  ///
  /// No compile and no reload: the value goes into the object the demo reads
  /// while building, and the guest rebuilds. Turning a knob costs a frame, and
  /// the demo keeps whatever state it was holding.
  ///
  /// Drawn straight away, then sent — one at a time, keeping only the latest of
  /// whatever piled up behind the one in flight — and read back afterwards,
  /// because a demo's build decides what knobs exist and turning one can reveal
  /// or retire another.
  ///
  /// A slider sends a value per frame of a drag and each one is a round trip
  /// that waits for the guest's frame. Sent concurrently they can land out of
  /// order, which is a slider that jumps backwards under the pointer; sent one
  /// at a time without coalescing, the drag queues up and the demo finishes the
  /// gesture seconds after your hand does.
  Future<void> setKnob(String name, Object? value) async {
    // Optimistic, so the control follows the pointer at the panel's frame rate
    // rather than the guest's round trip. The read below is what makes it true.
    knobs = KnobReport(
      entryId: knobs.entryId,
      declared: knobs.declared,
      revision: knobs.revision,
      knobs: [
        for (var knob in knobs.knobs)
          knob.name == name ? knob.withValue(value) : knob,
      ],
    );
    notifyListeners();

    _pendingKnobs[name] = value;
    if (_settingKnobs) return;
    _settingKnobs = true;
    try {
      while (_pendingKnobs.isNotEmpty) {
        var vmService = _vmService;
        if (vmService == null) return;
        var next = _pendingKnobs.keys.first;
        var pending = _pendingKnobs.remove(next);
        await vmService.callExtension(
          'ext.flutterware.setParameter',
          args: {
            'payload': jsonEncode({'name': next, 'value': pending}),
          },
        );
      }
      // Once, after the last one: a demo's build decides what knobs exist, so
      // turning one can reveal or retire another — but only the settled state
      // is worth drawing.
      await _readKnobs();
    } finally {
      _settingKnobs = false;
    }
  }

  final _pendingKnobs = <String, Object?>{};
  var _settingKnobs = false;

  /// Sets one of the shell's axes: a picker to an option's name, a flag to a
  /// bool, or either to null for the default its signature declares.
  ///
  /// Recorded against the shell rather than the entry, which is what makes an
  /// axis outlive a switch.
  Future<void> setAxis(String name, Object? value) async {
    var shellId = axes.shellId;
    if (shellId == null) return;
    selections.choose(shellId, name, value);

    // Drawn before it is sent, like a knob: the guest confirms by reporting,
    // and a control that waited for a round trip to move would feel stuck.
    axes = AxisReport(
      shellId: shellId,
      axes: [
        for (var axis in axes.axes)
          if (axis.name == name)
            axis.withValue(value ?? axis.defaultValue)
          else
            axis,
      ],
    );
    notifyListeners();

    await _pushAxes(shellId);
    await _readAxes();
  }

  /// Sends a shell's selections to the guest. See [ShellSelections.payloadFor]
  /// for why every axis is named, including the ones nothing has chosen.
  Future<void> _pushAxes(String? shellId) async {
    var vmService = _vmService;
    if (vmService == null || shellId == null) return;
    var shell = _activeShell;
    if (shell == null || shell.id != shellId) return;
    var payload = selections.payloadFor(shell);
    if (payload.isEmpty || mapEquals(payload, _pushed)) return;
    _pushed = payload;
    await vmService.callExtension(
      'ext.flutterware.setAxes',
      args: {'payload': jsonEncode(payload)},
    );
  }

  /// Asks the guest what the shell on screen offers.
  ///
  /// Retried while the report names another shell, for the reason a knob read
  /// is: the axes are recorded by the *call* the generated wrapper makes, so a
  /// read landing between the reload and the frame describes the shell that was
  /// there before.
  Future<void> _readAxes() async {
    var vmService = _vmService;
    var shellId = (selected ?? active)?.shellId;
    if (vmService == null) return;
    if (shellId == null) {
      // An entry with no shell has no axes, and nothing to wait for.
      if (axes.axes.isNotEmpty) {
        axes = AxisReport.empty;
        notifyListeners();
      }
      return;
    }
    for (var attempt = 0; attempt < 10; attempt++) {
      var json = await vmService.callExtension('ext.flutterware.axes');
      if (_disposed) return;
      if (json == null) return; // A guest from before the extension existed.
      var report = AxisReport.fromJson(json);
      if (report.shellId == shellId) {
        axes = report;
        notifyListeners();
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

  Future<void> _switchTo(CatalogEntry entry, {required bool ifChanged}) async {
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
    var reloaded = entry.id == selected?.id || entry.id == active?.id;
    selected = entry;
    // Only on a real switch: re-selecting the entry you are already on is a
    // reload, and a reload that undoes the device you just picked would make
    // the picker feel like it forgets.
    if (!reloaded) staging.followEntry(entry.formFactor);
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
    await _pushAxes(entry.shellId);

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
    shells = change.shells;

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
