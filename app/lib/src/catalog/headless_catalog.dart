import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

// The knob types, not the umbrella `ui_catalog.dart`: that one exports the
// demo annotations, which reach `package:flutter/widgets.dart` and would make
// `fw` unlinkable. `knob.dart` is plain Dart by design and says so.
// ignore: implementation_imports
import 'package:flutterware/src/inspect/error.dart';
// ignore: implementation_imports
import 'package:flutterware/src/inspect/node.dart';
// ignore: implementation_imports
import 'package:flutterware/src/ui_catalog/axis.dart';
// ignore: implementation_imports
import 'package:flutterware/src/ui_catalog/knob.dart';

import '../embedder/protocol.dart';
import '../embedder/raw_frame.dart';
import 'catalog_params.dart';
import 'debug_flags.dart';
import 'devices.dart';
import 'catalog_entry.dart';
import '../embedder/guest_vm_service.dart';
import '../utils/run_dir.dart';
import 'compiler_daemon_client.dart';
import 'protocol.dart';

/// The catalog pipeline with no GUI involved: render an entry, ask what builds,
/// ask what knobs an entry declares.
///
/// The same pipeline the GUI drives, invoked by whoever asks — a button, `fw`,
/// or an agent. Nothing here touches Flutter, so it runs anywhere the daemon
/// does.
///
/// The guest is spawned with `--capture-raw`, which writes the composited frame
/// the user would have seen rather than re-rasterising it.
class HeadlessCatalog {
  HeadlessCatalog({required this.dartExecutable, required this.config});

  /// A real Dart VM — the Flutter SDK's `dart`, never the running executable
  /// when that is a Flutter app.
  final String dartExecutable;

  final DaemonConfig config;

  /// Screenshots [entryId] into [output], optionally with its knobs turned.
  ///
  /// Starts a daemon, compiles the entry, renders one frame, and shuts
  /// everything down. Fine for one entry; a batch wants a session that stays
  /// warm, which is why [captureAll] exists.
  ///
  /// [knobs] are raw strings — a flag and a JSON object both arrive as text —
  /// and are coerced to whatever kind the demo declared. A name the entry does
  /// not declare is an error naming the ones it does: a silently ignored knob
  /// produces a picture that looks right and is not.
  Future<CatalogCapture> capture({
    required String entryId,
    required String output,
    CaptureViewport viewport = CaptureViewport.panel,
    Map<String, String> knobs = const {},
    Map<String, String> axes = const {},
    Map<String, String> debug = const {},

    /// Cut the picture down to this node, by the id a tree read gave.
    String? node,

    /// Draw every node of the tree over the picture, id and all.
    bool annotate = false,
  }) async {
    if (knobs.isEmpty &&
        axes.isEmpty &&
        debug.isEmpty &&
        node == null &&
        !annotate) {
      var results = await captureAll(
        entryIds: [entryId],
        outputFor: (_) => output,
        viewport: viewport,
      );
      return CatalogCapture(file: results.values.single, knobs: const []);
    }
    return _withGuest(entryId: entryId, viewport: viewport, (guest) async {
      // Axes first: they belong to the shell *around* the demo, and a shell
      // rebuild can change what the demo is handed. Turning the knobs after
      // means the knob report describes the build that was actually captured.
      if (axes.isNotEmpty) await guest.applyAxes(entryId, axes);
      await guest.applyDebug(debug);
      var applied = knobs.isEmpty
          ? await guest.settledKnobs(entryId)
          : await guest.applyKnobs(entryId, knobs);

      // Read after the knobs and axes have landed: a crop is a rect, and a rect
      // measured against a different build is a picture of the wrong thing.
      InspectLayout? crop;
      var boxes = const <InspectNode>[];
      if (node != null || annotate) {
        var tree = await guest.settledTree(entryId);
        if (node != null) {
          var found = tree.nodeAt(node);
          if (found == null) {
            throw ArgumentError.value(
              node,
              'node',
              'no node with that id in $entryId. An id names a position in the '
                  'tree, so one from before an edit may no longer name '
                  'anything — read the tree again.',
            );
          }
          crop = found.layout;
          if (crop == null) {
            throw ArgumentError.value(
              node,
              'node',
              '${found.type} has no box of its own to crop to. Providers and '
                  'builders lay nothing out; ask for one of its children.',
            );
          }
        }
        if (annotate) boxes = tree.nodes.toList();
      }

      return CatalogCapture(
        file: await guest.capture(
          output,
          crop: crop,
          annotate: boxes,
          pixelRatio: viewport.pixelRatio,
        ),
        knobs: applied.knobs,
      );
    });
  }

  /// Connects, compiles [entryId], launches one guest and hands it to [body].
  ///
  /// Everything that needs a *running* entry goes through here — a capture with
  /// knobs turned, and reading what knobs there are — so the daemon handshake,
  /// the entry check and the teardown exist once.
  Future<T> _withGuest<T>(
    Future<T> Function(_GuestSession guest) body, {
    required String entryId,
    required CaptureViewport viewport,
  }) async {
    var (daemon, ready) = await CompilerDaemonClient.connect(
      dartExecutable: dartExecutable,
      config: config,
    );
    _GuestSession? guest;
    try {
      var known = {for (var entry in ready.entries) entry.id};
      if (!known.contains(entryId)) {
        throw ArgumentError.value(
          entryId,
          'entryId',
          'no such entry. Known ids: ${known.join(', ')}',
        );
      }
      // A whole kernel, not a delta: the guest loads it from disk at launch.
      var compiled = await daemon.select(entryId, full: true);
      if (!compiled.ok) {
        throw StateError('$entryId did not compile:\n${compiled.error}');
      }
      guest = await _GuestSession.start(
        hostPath: ready.hostPath,
        assetsDir: ready.assetsDir,
        icuData: ready.icuData,
        workDir: p.join(config.appPackageRoot, 'build', 'catalog'),
        viewport: viewport,
      );
      return await body(guest);
    } finally {
      await guest?.close();
      await daemon.close();
    }
  }

  /// Screenshots several entries against **one** daemon and **one** guest.
  ///
  /// The first entry pays a cold compile and a guest launch. Every entry after
  /// it is a hot reload and a capture request — the same economics as browsing,
  /// because it is the same mechanism.
  Future<Map<String, File>> captureAll({
    required List<String> entryIds,
    required String Function(String entryId) outputFor,
    CaptureViewport viewport = CaptureViewport.panel,
  }) async {
    var (daemon, ready) = await CompilerDaemonClient.connect(
      dartExecutable: dartExecutable,
      config: config,
    );
    _GuestSession? guest;
    try {
      var known = {for (var entry in ready.entries) entry.id};
      for (var id in entryIds) {
        if (!known.contains(id)) {
          throw ArgumentError.value(
            id,
            'entryId',
            'no such entry. Known ids: ${known.join(', ')}',
          );
        }
      }

      var captured = <String, File>{};
      for (var id in entryIds) {
        if (guest == null) {
          // The guest loads the kernel from disk at launch, so the first entry
          // needs a whole one; afterwards a delta is all a live isolate wants.
          var compiled = await daemon.select(id, full: true);
          if (!compiled.ok) {
            throw StateError('$id did not compile:\n${compiled.error}');
          }
          guest = await _GuestSession.start(
            // The daemon builds the host and reports where it put it. Taking
            // it from the handshake rather than a caller's guess means there
            // is one answer to "where is the host binary", and it is the one
            // that was actually built.
            hostPath: ready.hostPath,
            assetsDir: ready.assetsDir,
            icuData: ready.icuData,
            workDir: p.join(config.appPackageRoot, 'build', 'catalog'),
            viewport: viewport,
          );
        } else {
          var compiled = await daemon.select(id);
          if (!compiled.ok) {
            throw StateError('$id did not compile:\n${compiled.error}');
          }
          await guest.reload(compiled.dill!);
        }
        captured[id] = await guest.capture(outputFor(id));
      }
      return captured;
    } finally {
      await guest?.close();
      await daemon.close();
    }
  }

  /// Which entries the compiler can actually build, and why the rest cannot.
  ///
  /// Needs no guest: the daemon compiles every wrapper into one program while
  /// it prepares, and quarantines the ones that fail. So the answer is already
  /// in the handshake, and this is one connection rather than one compile per
  /// entry.
  ///
  /// The scan cannot answer this. It parses and finds an entry; whether the
  /// entry *compiles* is a fact only the compiler holds, which is why nothing
  /// but the panel could ask before now.
  Future<CatalogCheck> check() async {
    var (daemon, ready) = await CompilerDaemonClient.connect(
      dartExecutable: dartExecutable,
      config: config,
    );
    try {
      return CatalogCheck(
        servable: ready.entries,
        quarantined: ready.quarantined,
      );
    } finally {
      await daemon.close();
    }
  }

  /// The knobs [entryId] declares, read from a live guest.
  ///
  /// A knob is a runtime fact — a demo declares one by *asking* for it while it
  /// builds — so no amount of parsing finds them. The guest registers
  /// `ext.flutterware.parameters` and answers with what its last build
  /// declared.
  ///
  /// Empty when the entry declares none, or when the guest is old enough not to
  /// register the extension. That is an answer, not a failure.
  Future<KnobReport> knobs({
    required String entryId,
    CaptureViewport viewport = CaptureViewport.panel,
  }) => _withGuest(
    entryId: entryId,
    viewport: viewport,
    (guest) => guest.settledKnobs(entryId),
  );

  /// The axes the shell around [entryId] offers, read from a live guest.
  ///
  /// Like [knobs], and runtime for the same reason: a shell declares an axis by
  /// *asking* for it while it builds.
  Future<AxisReport> axes({
    required String entryId,
    CaptureViewport viewport = CaptureViewport.panel,
  }) => _withGuest(
    entryId: entryId,
    viewport: viewport,
    (guest) => guest.settledAxes(entryId),
  );

  /// What [entryId] reports when it is actually rendered.
  ///
  /// `check` answers whether an entry *compiles*, which is a different
  /// question and the only one anything could ask before now.
  Future<InspectErrors> errors({
    required String entryId,
    CaptureViewport viewport = CaptureViewport.panel,
    Map<String, String> knobs = const {},
    Map<String, String> axes = const {},
  }) => _withGuest(entryId: entryId, viewport: viewport, (guest) async {
    if (axes.isNotEmpty) await guest.applyAxes(entryId, axes);
    if (knobs.isNotEmpty) await guest.applyKnobs(entryId, knobs);
    return guest.settledErrors(entryId);
  });

  /// Renders **every** entry against one warm guest and reports what each said.
  ///
  /// The economics of [captureAll], which is the reason this is affordable at
  /// all: the first entry pays a cold compile and a guest launch, and every one
  /// after it is a hot reload and a frame. Measured on this repo at ~120ms per
  /// entry after the first.
  ///
  /// Entries the compiler refused never get a guest — they are in the
  /// handshake, and an entry that does not build cannot be rendered to find out
  /// what it would have said.
  Future<CatalogAudit> auditAll({List<String>? entryIds}) async {
    var (daemon, ready) = await CompilerDaemonClient.connect(
      dartExecutable: dartExecutable,
      config: config,
    );
    _GuestSession? guest;
    try {
      // Both halves filtered. Leaving the quarantine unfiltered would report a
      // compile failure from a file nobody asked about, under a flag whose
      // whole purpose is to narrow what is looked at.
      var quarantined = [
        for (var broken in ready.quarantined)
          if (entryIds == null || entryIds.contains(broken.entry.id)) broken,
      ];
      var servable = [
        for (var entry in ready.entries)
          if (entryIds == null || entryIds.contains(entry.id)) entry,
      ];

      var rendered = <String, InspectErrors>{};
      for (var entry in servable) {
        if (guest == null) {
          var compiled = await daemon.select(entry.id, full: true);
          if (!compiled.ok) continue;
          guest = await _GuestSession.start(
            hostPath: ready.hostPath,
            assetsDir: ready.assetsDir,
            icuData: ready.icuData,
            workDir: p.join(config.appPackageRoot, 'build', 'catalog'),
            viewport: CaptureViewport.panel,
          );
        } else {
          var compiled = await daemon.select(entry.id);
          if (!compiled.ok) continue;
          await guest.reload(compiled.dill!);
        }
        rendered[entry.id] = await guest.settledErrors(entry.id);
      }
      return CatalogAudit(
        entries: servable,
        quarantined: quarantined,
        rendered: rendered,
      );
    } finally {
      await guest?.close();
      await daemon.close();
    }
  }

  /// The widget tree [entryId] builds, read from a live guest.
  ///
  /// Same shape as [knobs] and for the same reason: a tree is what a build
  /// produced, so it takes a compile, a guest and a frame. [knobs] are applied
  /// first when given, because a tree is of one particular build and turning a
  /// knob can change which widgets there are.
  Future<InspectTree> tree({
    required String entryId,
    CaptureViewport viewport = CaptureViewport.panel,
    Map<String, String> knobs = const {},
    Map<String, String> axes = const {},
    Map<String, String> debug = const {},
  }) => _withGuest(entryId: entryId, viewport: viewport, (guest) async {
    if (axes.isNotEmpty) await guest.applyAxes(entryId, axes);
    if (knobs.isNotEmpty) await guest.applyKnobs(entryId, knobs);
    // Before the read, not after: `platform` and `brightness` change what the
    // demo *builds*, not only how it is painted.
    await guest.applyDebug(debug);
    return guest.settledTree(entryId);
  });

  /// The tree, and the ids under one point of it.
  ///
  /// Both from one guest, because they have to agree: an id means a position
  /// in a particular tree, and a hit resolved against a second reading of it
  /// would be answering about a tree the caller was never shown.
  Future<(InspectTree, List<String>)> hitTest({
    required String entryId,
    required double x,
    required double y,
    CaptureViewport viewport = CaptureViewport.panel,
    Map<String, String> knobs = const {},
    Map<String, String> axes = const {},
  }) => _withGuest(entryId: entryId, viewport: viewport, (guest) async {
    if (axes.isNotEmpty) await guest.applyAxes(entryId, axes);
    if (knobs.isNotEmpty) await guest.applyKnobs(entryId, knobs);
    return (
      await guest.settledTree(entryId),
      await guest.settledHitTest(entryId, x, y),
    );
  });
}

/// Turns a knob value written as text into whatever kind the demo declared.
///
/// Everything arrives as text: a shell flag has no types, and a JSON object
/// from an agent may disagree with the demo about int versus double. The demo
/// is the authority, so this follows [KnobDescriptor.kind] rather than guessing
/// from the characters — `count=5` is an int for a demo that declared an int
/// and a string for one that declared a string.
Object? coerceKnob(KnobDescriptor knob, String value) => switch (knob.kind) {
  KnobKind.boolean => switch (value.toLowerCase()) {
    'true' || 'yes' || '1' => true,
    'false' || 'no' || '0' => false,
    _ => throw ArgumentError.value(value, knob.name, 'expected true or false'),
  },
  KnobKind.integer =>
    int.tryParse(value) ??
        (throw ArgumentError.value(value, knob.name, 'expected an integer')),
  KnobKind.number =>
    num.tryParse(value) ??
        (throw ArgumentError.value(value, knob.name, 'expected a number')),
  KnobKind.picker =>
    knob.options.contains(value)
        ? value
        : throw ArgumentError.value(
            value,
            knob.name,
            'expected one of: ${knob.options.join(', ')}',
          ),
  KnobKind.string => value,
};

/// A captured frame, and the knobs it was rendered with.
class CatalogCapture {
  CatalogCapture({required this.file, required this.knobs});

  final File file;

  /// What the entry reported *after* the values were applied — so a clamped or
  /// ignored value is visible rather than assumed.
  final List<KnobDescriptor> knobs;
}

/// Every entry, and what each one said when it was rendered.
class CatalogAudit {
  CatalogAudit({
    required this.entries,
    required this.quarantined,
    required this.rendered,
  });

  /// The entries the compiler accepted, in scan order.
  final List<CatalogEntry> entries;

  /// The ones it refused, with the compiler's own diagnostics.
  final List<QuarantinedEntry> quarantined;

  /// What each rendered entry reported, keyed by id. An entry missing from
  /// here is one that failed to compile on its own after the handshake.
  final Map<String, InspectErrors> rendered;
}

/// What the compiler could and could not build.
class CatalogCheck {
  CatalogCheck({required this.servable, required this.quarantined});

  final List<CatalogEntry> servable;

  /// Entries the compiler refused, each with its diagnostics verbatim.
  final List<QuarantinedEntry> quarantined;

  bool get ok => quarantined.isEmpty;
}

/// One embedder guest, kept alive across captures.
class _GuestSession {
  _GuestSession._(
    this._guest,
    this._connection,
    this._server,
    this._reader,
    this._vmService,
    this._workDir,
  );

  final Process _guest;
  final Socket _connection;
  final ServerSocket _server;
  final FrameReader _reader;
  final GuestVmService _vmService;
  final String _workDir;

  final _captures = <String, Completer<void>>{};

  static Future<_GuestSession> start({
    required String hostPath,
    required String assetsDir,
    required String icuData,
    required String workDir,
    required CaptureViewport viewport,
  }) async {
    // Not under [workDir]: a unix socket path is capped at 104 bytes, and a
    // build directory inside a worktree already spends most of that. The
    // derived name keeps two concurrent captures from colliding.
    var key = sha1.convert(utf8.encode(workDir)).toString().substring(0, 12);
    var socketPath = checkSocketPath(
      p.join(flutterwareRunDir(), 'shot-$key.sock'),
    );
    var socket = File(socketPath);
    if (socket.existsSync()) socket.deleteSync();
    var server = await ServerSocket.bind(
      InternetAddress(socketPath, type: InternetAddressType.unix),
      0,
    );

    var guest = await Process.start(hostPath, [
      assetsDir,
      icuData,
      socketPath,
      '${viewport.width}',
      '${viewport.height}',
    ]);
    var vmServiceUri = Completer<String>();
    guest.stdout
        .transform(const SystemEncoding().decoder)
        .transform(const LineSplitter())
        .listen((line) {
          var match = RegExp(r'(http://127\.0\.0\.1:\S+/)').firstMatch(line);
          if (match != null && !vmServiceUri.isCompleted) {
            vmServiceUri.complete(match.group(1));
          }
        });
    unawaited(guest.stderr.drain<void>());

    var connected = await Future.any<Object?>([server.first, guest.exitCode]);
    if (connected is! Socket) {
      throw StateError('the guest exited before connecting');
    }

    var session = _GuestSession._(
      guest,
      connected,
      server,
      FrameReader(),
      await GuestVmService.connect(await vmServiceUri.future),
      workDir,
    );
    connected.listen(session._onData);
    // Argv carried the buffer size; this carries what the buffer *means*. The
    // ratio and the safe areas have no other way in, and without them a phone
    // capture is a correctly-sized picture of the wrong layout.
    session._resize(viewport);
    return session;
  }

  void _resize(CaptureViewport viewport) => _connection.add(
    encodeMessage(
      ResizeMessage(
        width: viewport.width,
        height: viewport.height,
        pixelRatio: viewport.pixelRatio,
        insetTop: viewport.insetTop,
        insetRight: viewport.insetRight,
        insetBottom: viewport.insetBottom,
        insetLeft: viewport.insetLeft,
      ),
    ),
  );

  void _onData(List<int> chunk) {
    for (var message in _reader.addBytes(chunk)) {
      if (message is CapturedMessage) {
        _captures.remove(message.path)?.complete();
      } else if (message is ErrorMessage) {
        for (var pending in _captures.values) {
          if (!pending.isCompleted) {
            pending.completeError(StateError(message.message));
          }
        }
        _captures.clear();
      }
    }
  }

  Future<void> reload(String dill) => _vmService.reload(dill);

  /// What [entryId] declares, once the guest has actually built it.
  ///
  /// **Renders a frame first, and throws it away.** A knob is declared while
  /// the demo builds, and a headless host draws nothing until a frame is asked
  /// for — so without this the answer is always "no knobs". The panel never
  /// meets this because it drives frames continuously; measured here by
  /// getting an empty report from a demo that plainly has three.
  ///
  /// Then retried while the report names another entry, exactly as the panel
  /// does: a read landing between the reload and the frame describes whatever
  /// was on screen before.
  Future<KnobReport> settledKnobs(String entryId) async {
    await _renderScratchFrame();
    for (var attempt = 0; attempt < 20; attempt++) {
      var json = await _vmService.callExtension('ext.flutterware.parameters');
      // A guest without the extension: not an error, just no knobs.
      if (json == null) return KnobReport.empty;
      var report = KnobReport.fromJson(json);
      if (report.entryId == entryId) return report;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    return KnobReport.empty;
  }

  /// The tree [entryId] built, once it has actually built.
  ///
  /// The same frame-first, retry-until-it-names-the-entry dance as
  /// [settledKnobs], for the same two reasons: a headless host draws nothing
  /// until a frame is asked for, and a read landing between the reload and the
  /// frame describes whatever was on screen before.
  Future<InspectTree> settledTree(String entryId) async {
    await _renderScratchFrame();
    for (var attempt = 0; attempt < 20; attempt++) {
      var json = await _vmService.callExtension('ext.flutterware.tree');
      // A guest from before the extension existed: not an error, no tree.
      if (json == null) return InspectTree.empty;
      var tree = InspectTree.fromJson(json);
      if (tree.entryId == entryId) return tree;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    return InspectTree.empty;
  }

  /// The node ids under a point, outermost first.
  ///
  /// Reads the tree first for the same settling reason [settledTree] does, and
  /// then asks — so a hit landing between a reload and its frame cannot answer
  /// about the entry that was on screen before.
  Future<List<String>> settledHitTest(
    String entryId,
    double x,
    double y,
  ) async {
    var tree = await settledTree(entryId);
    if (tree.root == null) return const [];
    var json = await _vmService.callExtension(
      'ext.flutterware.hitTest',
      args: {'x': '$x', 'y': '$y'},
    );
    return [for (var id in json?['ids'] as List? ?? const []) '$id'];
  }

  /// What the shell around [entryId] offers, once it has built.
  ///
  /// Empty when the entry's wrapper is not a shell — an answer, not something
  /// to keep waiting for, which is why this settles on the *entry* rather than
  /// on a shell ever appearing.
  Future<AxisReport> settledAxes(String entryId) async {
    await _renderScratchFrame();
    for (var attempt = 0; attempt < 20; attempt++) {
      var json = await _vmService.callExtension('ext.flutterware.axes');
      if (json == null) return AxisReport.empty;
      var report = AxisReport.fromJson(json);
      if (report.entryId == entryId) return report;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    return AxisReport.empty;
  }

  /// Turns the shell's axes, and reports what it says afterwards.
  ///
  /// The mirror of [applyKnobs], down to the whole-state rule — but filed under
  /// the shell rather than the entry, because that is the lifetime an axis has:
  /// a knob belongs to the entry and goes with it, an axis belongs to the shell
  /// and does not.
  ///
  /// Values arrive as text and are resolved against what the shell *declared*,
  /// so `theme=dark` works whether the shell spelled the option `dark` or
  /// `Dark` — a slug and a label both land, and a name the shell does not offer
  /// is an error naming the ones it does.
  Future<AxisReport> applyAxes(
    String entryId,
    Map<String, String> values,
  ) async {
    var declared = await settledAxes(entryId);
    var shellId = declared.shellId;
    if (values.isEmpty) return declared;
    if (shellId == null) {
      throw ArgumentError.value(
        values.keys.join(', '),
        'axes',
        'this entry has no shell, so it offers no axes. Axes are declared by a '
            'CatalogShell around the demo.',
      );
    }

    var known = {for (var axis in declared.axes) axis.name: axis};
    var payload = <String, Object?>{};
    for (var axis in declared.axes) {
      var raw = values[axis.name];
      payload[axis.name] = raw == null
          ? null
          : paramOptionFor(axis, paramSlug(raw)) ??
                paramOptionFor(axis, raw) ??
                (throw ArgumentError.value(
                  raw,
                  axis.name,
                  axis.options.isEmpty
                      ? 'not a ${axis.kind.name}'
                      : 'no such option. Declared: ${axis.options.join(', ')}',
                ));
    }
    for (var name in values.keys) {
      if (known.containsKey(name)) continue;
      throw ArgumentError.value(
        name,
        'axes',
        'no such axis on this shell. Declared: ${known.keys.join(', ')}',
      );
    }

    var json = await _vmService.requireExtension(
      'ext.flutterware.setAxes',
      args: {
        'payload': jsonEncode({shellId: payload}),
      },
    );
    return json == null ? declared : AxisReport.fromJson(json);
  }

  /// What [entryId] reported while building and painting.
  ///
  /// Frame-first like every other runtime read, and here it is the whole point
  /// rather than a precondition: a build error needs a build, and a layout
  /// overflow is reported from `paint`, so an entry nobody has drawn has
  /// nothing to confess.
  Future<InspectErrors> settledErrors(String entryId) async {
    await _renderScratchFrame();
    for (var attempt = 0; attempt < 20; attempt++) {
      var json = await _vmService.callExtension('ext.flutterware.errors');
      if (json == null) return InspectErrors.empty;
      var report = InspectErrors.fromJson(json);
      if (report.entryId == entryId) return report;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    return InspectErrors.empty;
  }

  /// Sets the framework's debug switches, once the guest can hear them.
  ///
  /// **Renders a frame first**, and it is not the usual reason. Knobs and the
  /// tree need a frame because a demo declares them by building; these are
  /// registered by the binding whether anything builds or not — but the *VM
  /// service* learns about them asynchronously, and a call that lands between
  /// connect and registration comes back "method not found". Measured: every
  /// flag failed that way until a frame went first, and the spike missed it
  /// only because it happened to render before asking.
  Future<void> applyDebug(Map<String, String> values) async {
    if (values.isEmpty) return;
    await _renderScratchFrame();
    await applyDebugFlags(_vmService, values);
  }

  /// Draws one frame nobody looks at, so the demo has built.
  Future<void> _renderScratchFrame() async {
    var scratch = p.join(_workDir, 'knobs.scratch.png');
    await capture(scratch);
    var file = File(scratch);
    if (file.existsSync()) file.deleteSync();
  }

  /// Turns [values] on [entryId], and reports what the entry says afterwards.
  ///
  /// Coerced to the kind the demo declared, because everything arrives as text:
  /// a shell flag has no types and a JSON object from an agent may disagree
  /// with the demo about int versus double.
  Future<KnobReport> applyKnobs(
    String entryId,
    Map<String, String> values,
  ) async {
    var declared = await settledKnobs(entryId);
    var known = {for (var knob in declared.knobs) knob.name: knob};

    for (var name in values.keys) {
      if (known.containsKey(name)) continue;
      throw ArgumentError.value(
        name,
        'knob',
        known.isEmpty
            ? 'this entry declares no knobs'
            : 'no such knob on $entryId. Declared: ${known.keys.join(', ')}',
      );
    }

    // One call carrying every declared knob, not one call per knob: a write is
    // the whole state, and a name absent from the payload is what says "leave
    // this at its default". The panel builds the same shape in
    // `paramPayloadFor`.
    await _vmService.requireExtension(
      'ext.flutterware.setParameters',
      args: {
        'payload': jsonEncode({
          for (var knob in declared.knobs)
            knob.name: switch (values[knob.name]) {
              var raw? => coerceKnob(knob, raw),
              null => null,
            },
        }),
      },
    );

    // Read once at the end: a demo's build decides what knobs exist, so
    // turning one can reveal or retire another, and only the settled set is
    // worth reporting.
    return values.isEmpty ? declared : await settledKnobs(entryId);
  }

  /// Asks the guest to write its next frame, and waits for the ack.
  Future<File> capture(
    String output, {

    /// Crop to this rect, in the guest's logical coordinates — the same space
    /// [InspectLayout] reports, which is why a node's rect crops its own
    /// picture without a transform.
    InspectLayout? crop,

    /// Draw a box and a node id over each of these.
    List<InspectNode> annotate = const [],

    /// Logical-to-physical, for turning either of the above into pixels.
    double pixelRatio = 1,
  }) async {
    var rawFrame = p.join(_workDir, 'screenshot.rawframe');
    var raw = File(rawFrame);
    if (raw.existsSync()) raw.deleteSync();

    var done = _captures[rawFrame] = Completer<void>();
    _connection.add(encodeMessage(CaptureMessage(rawFrame)));
    await _connection.flush();
    await done.future.timeout(const Duration(seconds: 30));

    var image = decodeRawFrame(raw.readAsBytesSync());
    // Annotate before cropping, so a box on a node partly outside the crop is
    // clipped with the picture rather than drawn against its edge.
    if (annotate.isNotEmpty) image = _annotate(image, annotate, pixelRatio);
    if (crop != null) image = _crop(image, crop, pixelRatio);
    var file = File(output);
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(img.encodePng(image));
    raw.deleteSync();
    return file;
  }

  /// One node per distinct box, outermost kept.
  ///
  /// Most of a summary tree lays nothing out of its own: a provider, a builder
  /// and the widget under them share one rect, so drawing every node draws the
  /// same rectangle six times and stacks six labels on one corner. The first
  /// version did exactly that and was unreadable — which is the difference
  /// between a feature that exists and one that answers the question.
  ///
  /// Outermost wins because it is the shorter id and the one a caller is more
  /// likely to have meant; the inner ones are still in the tree for anyone who
  /// wants them.
  static List<InspectNode> _distinctBoxes(List<InspectNode> nodes) {
    var seen = <String>{};
    return [
      for (var node in nodes)
        if (node.layout case var l?)
          if (seen.add('${l.x},${l.y},${l.width},${l.height}')) node,
    ];
  }

  /// The frame, cut to one node's box.
  ///
  /// Cropped out of the real composited frame rather than re-rendered in
  /// isolation, which is what `ext.flutter.inspector.screenshot` would do: a
  /// widget photographed away from its surroundings is a different picture, and
  /// usually not the one the question was about.
  ///
  /// Clamped to the frame, because a node may legitimately sit partly outside
  /// it — that is what an overflow *is* — and a crop that threw would refuse to
  /// show the one case worth looking at.
  static img.Image _crop(img.Image image, InspectLayout rect, double ratio) {
    var x = (rect.x * ratio).round().clamp(0, image.width - 1);
    var y = (rect.y * ratio).round().clamp(0, image.height - 1);
    return img.copyCrop(
      image,
      x: x,
      y: y,
      width: (rect.width * ratio).round().clamp(1, image.width - x),
      height: (rect.height * ratio).round().clamp(1, image.height - y),
    );
  }

  /// A box and an id over each node.
  ///
  /// The point is the id: an agent reads a tree, gets `0/1/2`, and then gets a
  /// picture with `0/1/2` written on the thing it names. Without that the tree
  /// and the screenshot are two observations of the same frame with nothing
  /// joining them.
  static img.Image _annotate(
    img.Image image,
    List<InspectNode> nodes,
    double ratio,
  ) {
    for (var node in _distinctBoxes(nodes)) {
      if (node.layout case var layout?) {
        var x = (layout.x * ratio).round();
        var y = (layout.y * ratio).round();
        var w = (layout.width * ratio).round();
        var h = (layout.height * ratio).round();
        img.drawRect(
          image,
          x1: x,
          y1: y,
          x2: x + w - 1,
          y2: y + h - 1,
          color: img.ColorRgb8(255, 0, 128),
        );
        var label = node.id.isEmpty ? 'root' : node.id;
        // A filled strip behind it: these are drawn over a rendered UI, and
        // magenta-on-whatever-was-there is not always legible.
        var labelX = x + 2;
        var labelY = y < 16 ? y + 2 : y - 15;
        img.fillRect(
          image,
          x1: labelX - 1,
          y1: labelY - 1,
          x2: labelX + label.length * 8,
          y2: labelY + 14,
          color: img.ColorRgb8(255, 0, 128),
        );
        img.drawString(
          image,
          label,
          font: img.arial14,
          x: labelX,
          y: labelY,
          color: img.ColorRgb8(255, 255, 255),
        );
      }
    }
    return image;
  }

  Future<void> close() async {
    await _vmService.close();
    _connection.add(encodeMessage(const ShutdownMessage()));
    await _connection.flush();
    await _connection.close();
    _guest.kill();
    await _server.close();
  }
}
