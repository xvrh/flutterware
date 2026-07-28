import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutterware_app/src/catalog/asset_bundle.dart';
import 'package:flutterware_app/src/catalog/catalog_entry.dart';
import 'package:flutterware_app/src/catalog/compile_blame.dart';
import 'package:flutterware_app/src/catalog/daemon_address.dart';
import 'package:flutterware_app/src/catalog/discovery.dart';
import 'package:flutterware_app/src/catalog/protocol.dart';
import 'package:flutterware_app/src/catalog/entrypoint_generator.dart';
import 'package:flutterware_app/src/embedder/embedder_build.dart';
import 'package:flutterware_app/src/embedder/flutter_cache.dart';
import 'package:flutterware_app/src/embedder/resident_compiler.dart';
import 'package:flutterware_app/src/embedder/source_invalidator.dart';
import 'package:path/path.dart' as p;

/// The catalog's build and compile half, as a plain Dart process shared by
/// every client that wants the same catalog.
///
/// It runs outside the GUI so that a screenshot, a `fw` command and an agent
/// reach the same pipeline the panel does, without a window open — and it is
/// *one* process rather than one per consumer, so the second consumer pays for
/// none of the scanning, bundling, host-building or compiling the first already
/// did. [DaemonAddress] is how they find each other.
///
/// Usage — clients spawn this themselves; the address is derived from the
/// config, so this is only ever run by hand for debugging:
///
/// ```sh
/// dart run tool/catalog/compiler_daemon.dart <config.json>
/// ```
Future<void> main(List<String> args) async {
  if (args.length != 1) {
    stderr.writeln('usage: compiler_daemon.dart <config.json>');
    exit(64);
  }

  var config = DaemonConfig.fromJson(
    jsonDecode(File(args.single).readAsStringSync()) as Map<String, dynamic>,
  );
  var address = DaemonAddress(config);
  address.ensureRunDir();

  ServerSocket server;
  try {
    server = await ServerSocket.bind(
      InternetAddress(address.socketPath, type: InternetAddressType.unix),
      0,
    );
  } on SocketException catch (e) {
    // Another daemon holds the address. That is a correct outcome of two
    // clients racing, not a failure — the loser exits and the winner serves.
    stderr.writeln('[catalog] address already served, exiting: ${e.message}');
    exit(0);
  }

  var daemon = _Daemon(config, address, server);
  for (var signal in [ProcessSignal.sigint, ProcessSignal.sigterm]) {
    signal.watch().listen((_) => daemon.stop());
  }
  await daemon.serve();
}

/// Where pub keeps its packages, so the invalidator can skip them. A dependency
/// is immutable by construction — the way you change one is to resolve a
/// different version, which rewrites the package config and recompiles anyway.
List<String> get _pubCacheRoots {
  var env = Platform.environment;
  var home = env[Platform.isWindows ? 'LOCALAPPDATA' : 'HOME'];
  return [
    ?env['PUB_CACHE'],
    if (home != null)
      Platform.isWindows
          ? p.join(home, 'Pub', 'Cache')
          : p.join(home, '.pub-cache'),
  ];
}

class _Daemon {
  _Daemon(this.config, this.address, this._server)
    // Keyed by address, so two daemons never share a working directory. They
    // all run out of the *GUI's* package — one catalog per project, but one
    // `app/build/catalog` — and everything in here is per-daemon state: the
    // generated entrypoint, the compiler's output, the published kernel, the
    // session directories. Sharing it meant two catalogs generating wrappers
    // over each other and compiling to the same file, which resolves a name to
    // whichever project wrote last.
    : _buildDir = p.join(
        config.appPackageRoot,
        'build',
        'catalog',
        address.key,
      );

  final DaemonConfig config;
  final DaemonAddress address;
  final ServerSocket _server;
  final String _buildDir;

  late final FlutterCache _cache;
  late final EntrypointGenerator _generator;
  late final CatalogScanner _scanner;

  /// What the roots looked like when [_discovered] was produced.
  var _scanned = '';

  /// Bumped whenever a rescan adds a library to the compiler's baseline.
  ///
  /// A delta is relative to that baseline, not to any particular guest: once a
  /// new wrapper has been compiled in, a later delta no longer carries it —
  /// it is unchanged — and a guest that never had the library reloads nothing
  /// and renders nothing. Sessions that are behind get the whole program
  /// instead. `EntrypointGenerator.registerAll` avoids the same divergence at
  /// startup by registering everything before anyone connects; entries that
  /// appear later cannot be handled that way.
  var _baseline = 0;
  ResidentCompiler? _compiler;

  /// What turns an edit into a recompile. Every request sweeps: the daemon has
  /// no watcher, so a client asking for something is the only moment it can
  /// notice the files moved — which is exactly what a client's reload button
  /// is for.
  late final _invalidator = SourceInvalidator(
    ignoredRoots: [
      config.flutterSdkRoot,
      ..._pubCacheRoots,
      // Generated, and already invalidated by name when the generator rewrites
      // them. Statting them would only report what we just did ourselves.
      _generator.outputDir,
    ],
  );

  /// Everything discovery found, in tree order. Fixed until a rescan.
  var _discovered = <CatalogEntry>[];

  /// Entries the compiler could not build, by id. See [_compileServingWhatWorks].
  final _quarantine = <String, _Quarantined>{};

  /// What the daemon will actually serve.
  List<CatalogEntry> get _entries => [
    for (var entry in _discovered)
      if (!_quarantine.containsKey(entry.id)) entry,
  ];

  CatalogEntry? _active;

  final _sessions = <_Session>[];
  final _timings = <String, int>{};
  var _sessionCounter = 0;
  Duration _coldCompile = Duration.zero;
  List<String> _diagnostics = const [];
  String? _hostPath;

  /// Completes when [prepare] has run — successfully or not. Sessions that
  /// connect while it is pending wait on it rather than being turned away.
  final _prepared = Completer<void>();

  /// Every request runs through here. The compiler, the entrypoint on disk and
  /// the generated wrappers are one shared, mutable thing; interleaving two
  /// clients' selects would mean compiling a file the other client is midway
  /// through rewriting.
  Future<void> _queue = Future.value();

  Timer? _idle;

  /// How long the daemon outlives its last client. Long enough that closing a
  /// panel and running `fw screenshot` costs nothing, short enough that a
  /// forgotten daemon does not hold a compiler open overnight.
  static const _idleTimeout = Duration(minutes: 10);

  /// The bundle every session symlinks, including a `kernel_blob.bin` for the
  /// entry [_prepare] compiled.
  ///
  /// Nothing writes here after [_prepare] returns. The compiler's output goes
  /// to [_outputDill] instead, so a session that has asked for nothing can
  /// still launch a guest against a kernel no later compile can move under it.
  String get _sharedAssetsDir => p.join(_buildDir, 'assets');

  String get _outputDill => p.join(_buildDir, 'out', 'kernel_blob.bin');

  /// Re-runs discovery when the files under the roots have moved, so an entry
  /// added, renamed or deleted while the catalog is open shows up.
  ///
  /// Guarded by a fingerprint rather than run every time: discovery reads and
  /// parses, and this sits on the reload loop.
  ///
  /// A scan that comes back with errors is *reported and dropped* — the entry
  /// set stays as it was. Refusing to serve is right at startup, where nothing
  /// is on screen yet and a catalog that lies is worse than none; mid-session
  /// it would take away a working panel because someone was midway through
  /// typing a duplicate id.
  /// What a rescan changed and the next compile has to invalidate.
  ///
  /// Held rather than returned, because a rescan is no longer always part of a
  /// compile: a refresh rescans and stops there, and the files it rewrote
  /// still have to reach the compiler whenever the next one happens.
  final _pending = <Uri>{};

  void _rescanIfNeeded() {
    var fingerprint = _scanner.fingerprint();
    if (fingerprint == _scanned) return;
    _scanned = fingerprint;

    var watch = Stopwatch()..start();
    var scan = _scanner.scan();
    if (!scan.ok) {
      stderr.writeln(
        '[catalog] rescan found errors, keeping the previous entries:\n'
        '${scan.diagnostics.where((d) => d.isError).join('\n')}',
      );
      return;
    }

    var before = {for (var entry in _discovered) entry.id: entry};
    var after = {for (var entry in scan.entries) entry.id: entry};
    var gone = <CatalogEntry>[
      for (var entry in _discovered)
        if (!after.containsKey(entry.id)) entry,
    ];
    var fresh = <CatalogEntry>[
      for (var entry in scan.entries)
        // Rewritten as well as added: the wrapper bakes in the annotation and
        // the demo file's imports, so an entry whose declaration changed needs
        // a new one even though its id did not.
        if (!before.containsKey(entry.id) || _differs(before[entry.id]!, entry))
          entry,
    ];
    if (gone.isEmpty && fresh.isEmpty) return;

    _discovered = scan.entries;
    _diagnostics = [
      for (var d in scan.diagnostics)
        if (!d.isError) '$d',
    ];
    // A quarantine is about a build that no longer describes these entries.
    for (var entry in [...gone, ...fresh]) {
      _quarantine.remove(entry.id);
    }

    // Dropped before they are registered again: a changed entry needs a fresh
    // wrapper, and the generator never reuses an index, so this is what makes
    // the entrypoint point at the new one.
    _pending.addAll([
      ..._generator.drop([...gone, ...fresh]),
      ..._generator.registerAll([
        for (var entry in _entries)
          if (fresh.any((f) => f.id == entry.id)) entry,
      ]),
    ]);
    // The entrypoint imports what is registered, so it is rewritten last —
    // after the new wrappers exist and whatever went away is gone.
    if (_entries.isNotEmpty) {
      var active = _active;
      _pending.addAll(
        _makeActive(
          active != null && after.containsKey(active.id)
              ? _entryById(active.id)
              : _entries.first,
        ),
      );
    }

    if (fresh.isNotEmpty) _baseline++;
    stderr.writeln(
      '[catalog] rescanned in ${watch.elapsedMilliseconds}ms: '
      '${fresh.length} new or changed, ${gone.length} gone',
    );
    _catalogChanged();
  }

  /// Whether the generated wrapper for [before] would be written differently
  /// for [after] — everything the wrapper or the entrypoint reads.
  static bool _differs(CatalogEntry before, CatalogEntry after) =>
      before.annotation != after.annotation ||
      before.name != after.name ||
      before.group != after.group ||
      before.symbol != after.symbol ||
      before.formFactor != after.formFactor;

  /// Looked up among everything discovered, not only what is servable: an entry
  /// that does not compile has to stay selectable, because selecting it is how
  /// a client retries it.
  CatalogEntry _entryById(String id) => _discovered.firstWhere(
    (e) => e.id == id,
    orElse: () => throw ArgumentError.value(id, 'id', 'no such entry'),
  );

  Future<void> serve() async {
    _server.listen(_accept);
    _armIdleTimer();
    try {
      await _prepare();
      _prepared.complete();
    } catch (e, s) {
      var failure = DaemonFailed(message: '$e', stackTrace: '$s');
      stderr.writeln(failure);
      for (var session in [..._sessions]) {
        session.send(failure);
      }
      _prepared.completeError(e, s);
      await _shutdown();
      exit(1);
    }
    for (var session in [..._sessions]) {
      unawaited(session.sendReady());
    }
  }

  void _accept(Socket socket) {
    _idle?.cancel();
    var session = _Session(this, socket, 'session-${_sessionCounter++}');
    _sessions.add(session);
    try {
      session.start();
      if (_prepared.isCompleted) unawaited(session.sendReady());
    } catch (e, s) {
      // One client that cannot be served is not a reason to drop the others.
      stderr.writeln('[catalog] could not serve ${session.id}: $e\n$s');
      session.send(DaemonFailed(message: '$e', stackTrace: '$s'));
      _detach(session);
    }
  }

  void _detach(_Session session) {
    _sessions.remove(session);
    session.dispose();
    if (_sessions.isEmpty) _armIdleTimer();
  }

  void _armIdleTimer() {
    _idle?.cancel();
    _idle = Timer(_idleTimeout, () {
      if (_sessions.isEmpty) stop();
    });
  }

  Future<void> stop() async {
    await _shutdown();
    exit(0);
  }

  Future<void> _shutdown() async {
    _idle?.cancel();
    for (var session in [..._sessions]) {
      session.dispose();
    }
    await _compiler?.shutdown();
    await _server.close();
    var socket = File(address.socketPath);
    if (socket.existsSync()) socket.deleteSync();
  }

  /// Everything slow and one-time: the engine framework, the asset bundle, the
  /// first compile, and the C host. Paid once per daemon, not once per client.
  Future<void> _prepare() async {
    var phase = Stopwatch()..start();
    void mark(String what) {
      _timings[what] = phase.elapsedMilliseconds;
      stderr.writeln('[catalog] $what ${phase.elapsedMilliseconds}ms');
      phase.reset();
    }

    _cache = FlutterCache(p.join(config.flutterSdkRoot, 'bin', 'cache'));

    _scanner = CatalogScanner(
      projectRoot: config.projectRoot,
      roots: config.roots,
      previewAnnotations: config.previewAnnotations,
    );
    _scanned = _scanner.fingerprint();
    var scan = _scanner.scan();
    if (!scan.ok) {
      // A duplicate id or an uncallable target means an entry would be missing
      // or unreachable; refusing beats starting a catalog that lies.
      throw StateError(
        'discovery failed:\n'
        '${scan.diagnostics.where((d) => d.isError).join('\n')}',
      );
    }
    mark('scan');
    _discovered = scan.entries;
    _diagnostics = [
      for (var d in scan.diagnostics)
        if (!d.isError) '$d',
    ];
    if (_entries.isEmpty) {
      throw StateError(
        'no catalog entries found under ${config.roots.join(', ')} — is the '
        'annotation registered? (looking for '
        '${config.previewAnnotations.map((a) => '@$a').join(', ')})',
      );
    }
    _generator = EntrypointGenerator(
      outputDir: p.join(_buildDir, 'entrypoint'),
      projectRoot: config.projectRoot,
      emitProbe: config.emitProbe,
    );
    _generator.registerAll(_entries);
    _makeActive(_entries.first);

    var engineDir = p.join(config.appPackageRoot, '.engine');
    await ensureEmbedderFramework(_cache, engineDir);
    mark('engine framework');
    await _ensureAssetBundle();
    mark('asset bundle');

    var watch = Stopwatch()..start();
    var compiler = _compiler = await _startCompiler();
    mark('compiler start');
    var cold = await _compileServingWhatWorks();
    mark('cold compile');
    if (!cold.ok) {
      throw StateError(
        'the catalog did not compile, and no single entry could be blamed:\n'
        '${cold.output.join('\n')}',
      );
    }
    if (_quarantine.isNotEmpty) {
      stderr.writeln(
        '[catalog] quarantined ${_quarantine.length} entries that do not '
        'compile: ${_quarantine.keys.join(', ')}',
      );
      // The successful compile was a *recompile* — round zero failed — so it
      // wrote a delta, and the whole-program file still holds the kernel of
      // the compile that failed. Publishing that gives every guest an
      // incomplete program: reloads then fail to resolve libraries it never
      // had, and appear to heal as later deltas patch them in one by one.
      cold = await _fullCompile();
      if (!cold.ok) {
        throw StateError(
          'the catalog compiled, but rebuilding it whole did not:\n'
          '${cold.output.join('\n')}',
        );
      }
      mark('rebuild after quarantine');
    }
    _coldCompile = watch.elapsed;
    // The baseline every later sweep reads against. Taken here rather than on
    // the first request: a file edited between startup and that request would
    // otherwise be recorded *as* the baseline, and the edit would never compile.
    _invalidator.sweep(compiler.sources);
    mark('source baseline (${_invalidator.watched} files)');
    compiler.saveWarmStart();
    File(_outputDill).copySync(p.join(_sharedAssetsDir, 'kernel_blob.bin'));
    mark('publish prepared kernel');

    _hostPath = await buildHost(
      nativeSourceDir: p.join(config.appPackageRoot, 'native'),
      nativeBuildDir: p.join(_buildDir, 'native'),
      engineDir: engineDir,
    );
    mark('host build');

    // Sessions from a previous daemon are meaningless now.
    var sessions = Directory(p.join(_buildDir, 'sessions'));
    if (sessions.existsSync()) sessions.deleteSync(recursive: true);
  }

  DaemonReady readyFor(_Session session) => DaemonReady(
    sessionId: session.id,
    hostPath: _hostPath!,
    assetsDir: session.assetsDir,
    icuData: _cache.icuData,
    coldCompile: _coldCompile,
    entries: _entries,
    quarantined: [
      for (var q in _quarantine.values)
        QuarantinedEntry(entry: q.entry, error: q.error),
    ],
    reused: session.arrivedAfterPrepare,
    timings: _timings,
    diagnostics: _diagnostics,
  );

  /// Looks for entries that appeared or disappeared. Compiles nothing.
  Future<void> refresh() {
    var result = _queue.then((_) => _rescanIfNeeded());
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }

  /// Compiles [id] for [session], one request at a time.
  Future<DaemonCompiled> select(
    _Session session,
    int requestId,
    String id, {
    required bool full,
    required bool ifChanged,
  }) {
    var result = _queue.then(
      (_) => _select(session, requestId, id, full: full, ifChanged: ifChanged),
    );
    // The queue must survive a failed request, or one bad select wedges every
    // client behind it.
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<DaemonCompiled> _select(
    _Session session,
    int requestId,
    String id, {
    required bool full,
    required bool ifChanged,
  }) async {
    // Before the id is resolved: it may be an entry that only exists now, or
    // one that has just stopped existing.
    _rescanIfNeeded();
    var rescanned = _pending.toList();
    _pending.clear();
    var entry = _entryById(id);

    // Then: what the user edited. Re-selecting the entry that
    // is already active is how a client asks for a reload, and without this it
    // would recompile an entrypoint whose imports all resolve to the state the
    // compiler is already holding — a switch that reports success and changes
    // nothing on screen.
    var edited = _invalidator.sweep(_compiler!.sources);
    if (edited.isNotEmpty) {
      stderr.writeln(
        '[catalog] ${edited.length} of ${_invalidator.watched} sources edited '
        '(swept in ${_invalidator.lastSweep.inMilliseconds}ms)',
      );
    }

    // Nothing moved, and the entry asked for is the one already compiled in.
    // Saying so is the whole value of `ifChanged`: the caller is a reflex, not
    // a decision, and a reload it did not need still reassembles the guest and
    // resets the demo's state.
    if (ifChanged &&
        rescanned.isEmpty &&
        edited.isEmpty &&
        _active?.id == id &&
        !_quarantine.containsKey(id)) {
      return DaemonCompiled(
        requestId: requestId,
        id: id,
        compile: Duration.zero,
        newSourceCount: 0,
        unchanged: true,
      );
    }

    // Asking for a quarantined entry *is* the retry: let it back into the
    // entrypoint and let the compile decide again. Answering from the
    // quarantine instead would leave an entry that only some other file's edit
    // could ever bring back — and would report the stale error even when the
    // compile below succeeds.
    if (_quarantine.remove(id) != null) _catalogChanged();

    var invalidated = {...rescanned, ...edited, ..._makeActive(entry)};
    // Whole program, not a delta: this guest is missing libraries that entered
    // the baseline while it was elsewhere, and a delta would leave them out.
    var behind = session.baseline != _baseline;
    if (full || behind) {
      // A guest spawned from scratch loads kernel_blob.bin off disk, and a
      // delta is not a program. `reset` makes the next compile emit the whole
      // thing without restarting the compiler — which matters because the
      // compiler is shared, and one client's launch must not throw away
      // another's warm state.
      _compiler!.reset();
    }
    var compiled = await _compileServingWhatWorks(invalidated.toList());

    // The requested entry may be exactly what the compile just quarantined, in
    // which case the compile "succeeded" — without it. Say so rather than hand
    // back a kernel rendering something else.
    var quarantined = _quarantine[id];
    if (quarantined != null) {
      return DaemonCompiled(
        requestId: requestId,
        id: id,
        compile: compiled.elapsed,
        newSourceCount: 0,
        editedCount: edited.length,
        error: 'this entry does not compile:\n${quarantined.error}',
      );
    }

    if (compiled.ok) session.baseline = _baseline;
    return DaemonCompiled(
      requestId: requestId,
      id: id,
      dill: compiled.ok
          ? session.takeKernel(compiled.dillOutput!, requestId, full: full)
          : null,
      compile: compiled.elapsed,
      newSourceCount: compiled.newSourceCount,
      editedCount: edited.length,
      error: compiled.ok ? null : compiled.output.join('\n'),
    );
  }

  /// Rebuilds the whole program at [_outputDill].
  ///
  /// Only a compile that has not failed leaves a valid program there — the
  /// compiler writes deltas elsewhere, and a failed compile leaves its own
  /// broken output behind. Anything that publishes [_outputDill] must be sure
  /// the last thing to write it succeeded and was whole.
  Future<CompileOutcome> _fullCompile() async {
    _compiler!.reset();
    return _compiler!.compile();
  }

  /// Makes [entry] the one the entrypoint renders, remembering it so a
  /// quarantine can tell when it needs to pick another.
  List<Uri> _makeActive(CatalogEntry entry) {
    _active = entry;
    return _generator.select(entry);
  }

  /// Compiles, and on failure drops whatever it can blame rather than failing
  /// the whole catalog.
  ///
  /// The entrypoint imports every entry — that is what makes one compiler safe
  /// to share — so a single demo mid-edit fails the compile for all of them.
  /// This reads the compiler's own diagnostics, quarantines the entries
  /// declared in the files it reported, and tries again with the rest.
  ///
  /// Errors nobody declares an entry in — a shared helper, the app itself —
  /// cannot be fixed by dropping anything, so they stay fatal. The caller gets
  /// the failed outcome and reports it.
  Future<CompileOutcome> _compileServingWhatWorks([
    List<Uri> invalidated = const [],
  ]) async {
    var pending = [..._readmitRepairedEntries(), ...invalidated];

    // Bounded: each round quarantines at least one entry, and errors in one
    // file routinely hide errors in the next.
    late CompileOutcome outcome;
    for (var round = 0; round < 10; round++) {
      outcome = await _compiler!.compile(pending);
      if (outcome.ok) return outcome;

      var blame = CompileBlame.of(
        outcome.output,
        entries: _entries,
        projectRoot: config.projectRoot,
        // Diagnostics name paths relative to the compiler's working directory,
        // which is the daemon's.
        workingDirectory: config.appPackageRoot,
      );
      if (blame.isEmpty) {
        stderr.writeln(
          '[catalog] compile failed and nothing could be blamed; errors in '
          '${blame.unattributed.join(', ')}',
        );
        return outcome;
      }

      var broken = [
        for (var entry in _entries)
          if (blame.entryIds.contains(entry.id)) entry,
      ];
      var error = outcome.output.join('\n');
      for (var entry in broken) {
        _quarantine[entry.id] = _Quarantined(
          entry: entry,
          error: error,
          sourceModified: _sourceModified(entry),
        );
      }
      _catalogChanged();

      pending = _generator.drop(broken);
      if (_entries.isEmpty) return outcome;
      if (_active == null || _quarantine.containsKey(_active!.id)) {
        pending.addAll(_makeActive(_entries.first));
      }
    }
    return outcome;
  }

  /// Brings back quarantined entries whose source has been edited since it
  /// failed, so fixing a demo is enough to get it back.
  ///
  /// Cheap to attempt: if it still does not compile it is quarantined again,
  /// with the new timestamp, so this cannot loop.
  List<Uri> _readmitRepairedEntries() {
    var repaired = <CatalogEntry>[];
    for (var quarantined in _quarantine.values.toList()) {
      var modified = _sourceModified(quarantined.entry);
      if (modified == null || modified == quarantined.sourceModified) continue;
      _quarantine.remove(quarantined.entry.id);
      repaired.add(quarantined.entry);
    }
    if (repaired.isEmpty) return [];
    _catalogChanged();
    return _generator.registerAll(repaired);
  }

  DateTime? _sourceModified(CatalogEntry entry) {
    var file = File(p.join(config.projectRoot, entry.path));
    return file.existsSync() ? file.statSync().modified : null;
  }

  /// Tells every client the servable set moved under it.
  void _catalogChanged() {
    if (!_prepared.isCompleted) return;
    var message = CatalogChanged(
      entries: _entries,
      quarantined: [
        for (var q in _quarantine.values)
          QuarantinedEntry(entry: q.entry, error: q.error),
      ],
    );
    for (var session in [..._sessions]) {
      session.send(message);
    }
  }

  Future<ResidentCompiler> _startCompiler() => ResidentCompiler.start(
    entrypoint: _generator.entrypointPath,
    outputDill: _outputDill,
    packageConfig: config.packageConfig,
    cache: _cache,
    warmDill: _warmDill,
  );

  late final String? _warmDill = _resolveWarmDill();

  /// The kernel a previous daemon left behind, for the compiler to start from.
  ///
  /// Discarded when the stamp says it was produced under different conditions.
  /// The compiler tolerates a stale *source* — that is the whole point, it
  /// recompiles what changed — but a kernel built against another engine or
  /// another package resolution is not a starting point, it is a wrong answer.
  String? _resolveWarmDill() {
    var dill = p.join(_buildDir, 'warm.dill');
    var stamp = File('$dill.stamp');
    var current = [
      _cache.engineRevision,
      config.packageConfig,
      '${File(config.packageConfig).statSync().modified.millisecondsSinceEpoch}',
    ].join(' ');

    if (stamp.existsSync() && stamp.readAsStringSync() == current) return dill;
    if (File(dill).existsSync()) File(dill).deleteSync();
    stamp.parent.createSync(recursive: true);
    stamp.writeAsStringSync(current);
    return dill;
  }

  /// The asset directory the guest reads: manifests written here, payloads
  /// symlinked. Milliseconds, against seconds for `flutter build bundle` —
  /// see [AssetBundleBuilder]. Rebuilt every start, since it is cheap and a
  /// stale manifest is worse than a rebuild.
  Future<void> _ensureAssetBundle() async {
    await AssetBundleBuilder(
      cache: _cache,
      // The *project's* package owns the unprefixed asset keys: a demo saying
      // `AssetImage('assets/logo.png')` means its own project's file, not the
      // GUI's. These were the same package until the catalog started running
      // against somebody else's project.
      rootPackageRoot: config.projectRoot,
      packageConfigPath: config.packageConfig,
    ).build(_sharedAssetsDir);
  }
}

/// An entry held back because it does not compile.
class _Quarantined {
  _Quarantined({
    required this.entry,
    required this.error,
    required this.sourceModified,
  });

  final CatalogEntry entry;
  final String error;

  /// The demo file's timestamp when it was quarantined. A newer one means
  /// somebody has been editing, which is grounds for trying again.
  final DateTime? sourceModified;
}

/// One connected client.
///
/// Owns the only things a client may not share: the kernel its guest loads and
/// the deltas its guest reloads. Both are files the compiler rewrites in place,
/// so handing two clients the same path would let one decide what the other
/// renders — the failure mode that once produced byte-identical screenshots of
/// the wrong entry.
class _Session {
  _Session(this._daemon, this._socket, this.id)
    : arrivedAfterPrepare = _daemon._prepared.isCompleted;

  final _Daemon _daemon;
  final Socket _socket;
  final String id;

  /// Whether this client attached to an already-prepared daemon, and so paid
  /// nothing for it.
  final bool arrivedAfterPrepare;

  /// The compiler baseline this session's guest has been fed up to. Behind the
  /// daemon's own means the next kernel it is given has to be a whole program.
  int baseline = 0;

  String get _dir => p.join(_daemon._buildDir, 'sessions', id);
  String get assetsDir => p.join(_dir, 'assets');

  final _deltas = <String>[];

  void start() {
    _socket
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          _onLine,
          onError: (_) => _daemon._detach(this),
          onDone: () => _daemon._detach(this),
        );
  }

  /// A directory that looks exactly like the shared bundle to the engine.
  ///
  /// Entirely symlinks, so it costs microseconds — including `kernel_blob.bin`,
  /// which points at the prepared kernel until this session asks for one of its
  /// own. That is what lets a client that has just attached launch a guest
  /// immediately, without a compile.
  void _prepareAssetsDir() {
    var target = Directory(assetsDir);
    if (target.existsSync()) target.deleteSync(recursive: true);
    target.createSync(recursive: true);
    for (var entity in Directory(_daemon._sharedAssetsDir).listSync()) {
      Link(p.join(assetsDir, p.basename(entity.path))).createSync(entity.path);
    }
  }

  /// Moves the compiler's output somewhere only this session reads.
  ///
  /// A [full] kernel becomes this session's `kernel_blob.bin`, which its guest
  /// loads at launch. A delta gets a per-request name, because the compiler
  /// writes every delta to the same path and the next client's compile would
  /// otherwise land there before this client's guest had reloaded.
  String takeKernel(String produced, int requestId, {required bool full}) {
    if (full) {
      var kernel = p.join(assetsDir, 'kernel_blob.bin');
      // Replaces the symlink to the prepared kernel; copying onto it would
      // write through to the shared bundle every other session reads.
      var link = Link(kernel);
      if (link.existsSync()) link.deleteSync();
      File(produced).copySync(kernel);
      return kernel;
    }
    var delta = p.join(_dir, 'deltas', '$requestId.dill');
    Directory(p.dirname(delta)).createSync(recursive: true);
    File(produced).copySync(delta);
    _deltas.add(delta);
    // The guest only ever reloads the newest; a couple of predecessors are kept
    // in case one is still in flight.
    while (_deltas.length > 4) {
      var stale = File(_deltas.removeAt(0));
      if (stale.existsSync()) stale.deleteSync();
    }
    return delta;
  }

  Future<void> sendReady() async {
    try {
      await _daemon._prepared.future;
    } catch (_) {
      return; // The failure was already sent.
    }
    try {
      // After preparing, not on connect: the shared bundle this mirrors does
      // not exist until then, and a client may well connect before it does.
      _prepareAssetsDir();
      send(_daemon.readyFor(this));
    } catch (e, s) {
      // This runs off the accept callback, so an escape here would be an
      // unhandled async error and take the whole daemon with it.
      stderr.writeln('[catalog] could not serve $id: $e\n$s');
      send(DaemonFailed(message: '$e', stackTrace: '$s'));
      _daemon._detach(this);
    }
  }

  Future<void> _onLine(String line) async {
    var json = tryDecodeLine(line);
    if (json == null) return;
    switch (DaemonRequest.decode(json)) {
      case SelectRequest(:var requestId, :var id, :var full, :var ifChanged):
        try {
          send(
            await _daemon.select(
              this,
              requestId,
              id,
              full: full,
              ifChanged: ifChanged,
            ),
          );
        } catch (e, s) {
          send(
            DaemonCompiled(
              requestId: requestId,
              id: id,
              compile: Duration.zero,
              newSourceCount: 0,
              error: '$e\n$s',
            ),
          );
        }
      case RefreshRequest():
        // Through the queue like any other work: a rescan rewrites the
        // generated wrappers and the entrypoint, which a compile in flight is
        // reading. Nothing is sent back — whatever it finds goes out as a
        // CatalogChanged, to every client rather than just this one.
        await _daemon.refresh();
      case StopDaemonRequest():
        await _daemon.stop();
    }
  }

  void send(DaemonResponse message) {
    try {
      _socket.writeln(encodeLine(message));
    } on SocketException {
      // The client left mid-request; _detach will follow.
    }
  }

  void dispose() {
    try {
      _socket.destroy();
    } catch (_) {}
    var dir = Directory(_dir);
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  }
}
