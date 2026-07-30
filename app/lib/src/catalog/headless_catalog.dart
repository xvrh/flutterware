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
import 'package:flutterware/src/inspect/log.dart';
// ignore: implementation_imports
import 'package:flutterware/src/inspect/node.dart';
// ignore: implementation_imports
import 'package:flutterware/src/ui_catalog/axis.dart';
// ignore: implementation_imports
import 'package:flutterware/src/ui_catalog/knob.dart';

import '../embedder/frame_capture.dart';
import '../embedder/protocol.dart';
import 'catalog_params.dart';
import 'debug_flags.dart';
import 'devices.dart';
import 'catalog_entry.dart';
import 'inspect_client.dart';
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
    var observed = await observe(
      entryId: entryId,
      viewport: viewport,
      knobs: knobs,
      axes: axes,
      debug: debug,
      screenshot: output,
      annotate: annotate,
      cropNode: node,
      wantKnobs: true,
    );
    return CatalogCapture(
      // `observe` was asked for a screenshot, so it took one or threw.
      file: observed.screenshot!,
      knobs: observed.knobs?.knobs ?? const [],
    );
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

  /// What [entryId] printed when it was rendered.
  ///
  /// **No `PluginAction` of its own, deliberately.** The panel spec names
  /// `logs` as the sixth projection of one rendered build that was about to be
  /// added to the action list by reflex, and S6 collapses all of them into one
  /// `inspect` — so shipping a `logs` action here would be shipping the thing
  /// that step exists to remove. The capability lands now; the CLI surface for
  /// it lands with the re-cut.
  Future<InspectLogs> logs({
    required String entryId,
    CaptureViewport viewport = CaptureViewport.panel,
    Map<String, String> knobs = const {},
    Map<String, String> axes = const {},
  }) => _withGuest(entryId: entryId, viewport: viewport, (guest) async {
    if (axes.isNotEmpty) await guest.applyAxes(entryId, axes);
    if (knobs.isNotEmpty) await guest.applyKnobs(entryId, knobs);
    return guest.settledLogs(entryId);
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

  /// Everything asked about **one** rendered build.
  ///
  /// The point of the whole thing. `tree`, `find`, `at`, `errors` and `logs`
  /// are not five capabilities — they are five projections of one observation,
  /// with the same inputs and the same precondition, and each used to pay a
  /// full compile-launch-render to answer one question about a frame the others
  /// also had to produce. Three questions was three renders, which for an agent
  /// in an edit loop is the dominant per-iteration cost.
  ///
  /// It also removes an assumption rather than only a cost. `screenshot
  /// --annotate` read its own tree, so a caller that ran `tree` and then
  /// `screenshot --annotate` got two trees from two processes; the ids on the
  /// picture matched the ids in the tree because the build is deterministic,
  /// not because they were the same object. Closing that loop was the entire
  /// point of `--annotate`. One render, one tree, both projections off it.
  ///
  /// Order matters and is not arbitrary: axes before knobs because a shell
  /// rebuild changes what the demo is handed; debug before any read because
  /// `platform` and `brightness` change what the demo *builds*; the tree before
  /// the hit test because a hit is only meaningful against a particular tree;
  /// and the capture last, because a picture should be of the state everything
  /// else described.
  Future<CatalogObservation> observe({
    required String entryId,
    CaptureViewport viewport = CaptureViewport.panel,
    Map<String, String> knobs = const {},
    Map<String, String> axes = const {},
    Map<String, String> debug = const {},
    bool wantTree = false,
    bool wantLogs = false,
    bool wantKnobs = false,
    (double, double)? at,
    String? screenshot,
    bool annotate = false,
    String? cropNode,
  }) => _withGuest(entryId: entryId, viewport: viewport, (guest) async {
    if (axes.isNotEmpty) await guest.applyAxes(entryId, axes);
    if (knobs.isNotEmpty) await guest.applyKnobs(entryId, knobs);
    await guest.applyDebug(debug);

    // Read whenever anything needs it, which is more often than the caller asked
    // for it: a hit resolves ids against a tree, a crop needs a node's rect, and
    // `--annotate` needs every node's.
    var needsTree =
        wantTree || at != null || annotate || (cropNode?.isNotEmpty ?? false);
    var framed = annotate || (cropNode?.isNotEmpty ?? false);

    // **One frame, then every read off it.** This is the actual content of "one
    // render", and it was not true before: each `settled*` drew its own scratch
    // frame, so an observation asking five questions drew five or six — and
    // `settledHitTest` read a *second* tree to resolve against, which is the
    // assumption collapsing the actions was supposed to remove rather than
    // preserve.
    //
    // When a picture is wanted and nothing has to be read *before* it is taken,
    // the picture **is** the settling frame. That is not a micro-optimisation:
    // a plain `screenshot` is the commonest call there is, and every frame here
    // writes a PNG to disk and deletes it again. A crop or an annotation needs
    // the tree first, so those still settle separately.
    File? picture;
    if (screenshot != null && !framed) {
      picture = await guest.capture(
        screenshot,
        pixelRatio: viewport.pixelRatio,
      );
    } else {
      await guest.settle();
    }

    var tree = needsTree ? await guest.readTree(entryId) : null;

    // Against the tree above, by argument rather than by luck.
    var hits = at == null || tree == null
        ? null
        : await guest.readHitTest(tree, at.$1, at.$2);

    var errors = await guest.readErrors(entryId);
    var logs = wantLogs ? await guest.readLogs(entryId) : null;
    var applied = wantKnobs ? await guest.readKnobs(entryId) : null;

    if (screenshot != null && picture == null) {
      var framing = _Framing.of(
        // `framed` is what put us here, and `needsTree` covers it, so the tree
        // has been read.
        tree!,
        node: cropNode,
        annotate: annotate,
        entryId: entryId,
      );
      picture = await guest.capture(
        screenshot,
        crop: framing.crop,
        annotate: framing.boxes,
        pixelRatio: viewport.pixelRatio,
      );
    }

    return CatalogObservation(
      tree: tree,
      errors: errors,
      logs: logs,
      knobs: applied,
      hits: hits,
      screenshot: picture,
    );
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

/// What `--node` and `--annotate` mean against one tree: a rect to crop to, and
/// the boxes to draw.
///
/// **One implementation, because there were briefly two.** `observe` was written
/// with a copy of `capture`'s version — the same lookup, the same two error
/// messages, byte for byte — which is precisely the drift that produced every
/// other defect this file carries a note about: `settledAxes` beside
/// `_readAxes`, the panel's tolerant writes, `setParameter` surviving a rename.
/// A rule about what a node id means belongs in one place.
class _Framing {
  const _Framing({this.crop, this.boxes = const []});

  /// Resolves [node] and [annotate] against [tree], refusing rather than
  /// approximating: an id that names nothing, and a widget with no box of its
  /// own, are different mistakes and each gets its own answer.
  factory _Framing.of(
    InspectTree tree, {
    required String? node,
    required bool annotate,
    required String entryId,
  }) {
    InspectLayout? crop;
    if (node != null && node.isNotEmpty) {
      var found = tree.nodeAt(node);
      if (found == null) {
        throw ArgumentError.value(
          node,
          'node',
          'no node with that id in $entryId. An id names a position in the '
              'tree, so one from before an edit may no longer name anything — '
              'read the tree again.',
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
    return _Framing(
      crop: crop,
      boxes: annotate ? tree.nodes.toList() : const [],
    );
  }

  final InspectLayout? crop;
  final List<InspectNode> boxes;
}

/// One rendered build, and everything anybody asked about it.
///
/// Nullable per section rather than empty-per-section, and the distinction is
/// load-bearing: null means **nobody asked**, empty means *asked and there is
/// nothing*. A demo that printed nothing and a demo whose logs were not
/// requested are different answers, and a caller that could not tell them apart
/// would read the second as the first.
///
/// The same shape whether the reading came from a fresh guest or from the
/// session a person has open, so the two paths cannot drift in what they can
/// report.
class CatalogObservation {
  const CatalogObservation({
    required this.errors,
    this.tree,
    this.logs,
    this.knobs,
    this.hits,
    this.screenshot,
  });

  /// Always read, whatever was asked for. It is the answer to "is this one
  /// broken", which is the question behind asking anything at all — and it
  /// costs a round trip against a guest that is already running.
  final InspectErrors errors;

  final InspectTree? tree;
  final InspectLogs? logs;

  /// The knobs the captured build declared, when they were asked for.
  ///
  /// Here rather than only on `capture` because a picture and a list of the
  /// controls that produced it are two projections of one frame, like everything
  /// else here.
  final KnobReport? knobs;

  /// The node ids under the probed point, outermost first. Empty is an answer:
  /// there is nothing of the demo's there.
  final List<String>? hits;

  final File? screenshot;
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

  /// The inspection reads, shared with the panel — see [InspectClient]. Patient
  /// here because this guest has just been handed a kernel and has to build,
  /// lay out and paint before it can describe the entry it was asked about.
  late final _inspect = InspectClient(
    _vmService,
    patience: InspectPatience.headless,
  );

  /// The capture exchange, shared with the GUI's live engine — see
  /// [FrameCapture].
  late final _capture = FrameCapture(
    send: (message) async {
      _connection.add(encodeMessage(message));
      await _connection.flush();
    },
    workDir: _workDir,
  );

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
      if (_capture.acknowledge(message)) continue;
      if (message is ErrorMessage) {
        _capture.failAll(StateError(message.message));
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
  /// Then [InspectClient] retries while the report names another entry.
  Future<KnobReport> settledKnobs(String entryId) async {
    await settle();
    return readKnobs(entryId);
  }

  /// The knobs the last frame declared. Reads only — see [settle].
  Future<KnobReport> readKnobs(String entryId) async =>
      await _inspect.knobs(entryId) ?? KnobReport.empty;

  /// The tree [entryId] built, once it has actually built.
  ///
  /// Frame-first for the same reason [settledKnobs] is.
  Future<InspectTree> settledTree(String entryId) async {
    await settle();
    return readTree(entryId);
  }

  /// The tree the last frame built. Reads only — see [settle].
  Future<InspectTree> readTree(String entryId) async =>
      await _inspect.tree(entryId) ?? InspectTree.empty;

  /// The node ids under a point, outermost first.
  ///
  /// Reads the tree first so the hit is resolved against the build the caller
  /// is shown, rather than against a second reading of it.
  Future<List<String>> settledHitTest(
    String entryId,
    double x,
    double y,
  ) async {
    await settle();
    return readHitTest(await readTree(entryId), x, y);
  }

  /// The node ids under a point of [tree].
  ///
  /// Takes the tree rather than reading one, which is the whole point: an id
  /// names a position in a particular tree, so a hit resolved against a second
  /// reading answers about a tree the caller was never shown.
  Future<List<String>> readHitTest(
    InspectTree tree,
    double x,
    double y,
  ) async => tree.root == null ? const [] : _inspect.hitTest(x, y);

  /// What the shell around [entryId] offers, once it has built.
  ///
  /// Empty when the entry's wrapper is not a shell — an answer, not something
  /// to keep waiting for, which is why [InspectClient.axes] settles on the
  /// *entry* rather than on a shell ever appearing.
  Future<AxisReport> settledAxes(String entryId) async {
    await settle();
    return readAxes(entryId);
  }

  /// The axes the last frame's shell declared. Reads only — see [settle].
  Future<AxisReport> readAxes(String entryId) async =>
      await _inspect.axes(entryId) ?? AxisReport.empty;

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

    return await _inspect.setAxes(jsonEncode({shellId: payload})) ?? declared;
  }

  /// What [entryId] reported while building and painting.
  ///
  /// Frame-first like every other runtime read, and here it is the whole point
  /// rather than a precondition: a build error needs a build, and a layout
  /// overflow is reported from `paint`, so an entry nobody has drawn has
  /// nothing to confess.
  Future<InspectErrors> settledErrors(String entryId) async {
    await settle();
    return readErrors(entryId);
  }

  /// What the frames so far reported. Reads only — see [settle].
  Future<InspectErrors> readErrors(String entryId) async =>
      await _inspect.errors(entryId) ?? InspectErrors.empty;

  /// What [entryId] printed while building and painting.
  ///
  /// Frame-first for exactly the reason [settledErrors] is: a demo prints from
  /// `build`, so an entry nobody has drawn has said nothing.
  Future<InspectLogs> settledLogs(String entryId) async {
    await settle();
    return readLogs(entryId);
  }

  /// What the frames so far printed. Reads only — see [settle].
  Future<InspectLogs> readLogs(String entryId) async =>
      await _inspect.logs(entryId) ?? InspectLogs.empty;

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
  ///
  /// **Separated from the reads because there were seven of these per
  /// observation.** Every `settled*` rendered its own, which was right when each
  /// was a standalone call and wrong the moment one call wanted five answers:
  /// `observe` drew a frame per projection, and `settledHitTest` drew *another*
  /// tree to resolve against — so the ids on an annotated screenshot matched the
  /// ids in the reported tree because the build is deterministic, not because
  /// they were the same tree. Which is exactly the assumption collapsing the
  /// actions was supposed to remove.
  Future<void> settle() => _renderScratchFrame();

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
    await _inspect.setKnobs(
      jsonEncode({
        for (var knob in declared.knobs)
          knob.name: switch (values[knob.name]) {
            var raw? => coerceKnob(knob, raw),
            null => null,
          },
      }),
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
    var image = await _capture.capture(
      crop: crop,
      annotate: annotate,
      pixelRatio: pixelRatio,
    );
    var file = File(output);
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(img.encodePng(image));
    return file;
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
