import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import '../motion/filmstrip.dart';
import '../motion/video.dart';

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
  /// everything down. Fine for one entry, which is the shape of every caller
  /// left: catalog-wide batches — the audit, the comparison — render under
  /// `flutter_tester` instead, where a demo that animates for ever costs fake
  /// clock rather than real seconds.
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

    /// Cut the picture down to one widget, by name or by a tree id.
    String? node,

    /// Draw every node of the tree over the picture, id and all.
    bool annotate = false,

    /// Where to park the entry's motion, 0..1.
    double? motionT,
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
      motionT: motionT,
    );
    return CatalogCapture(
      // `observe` was asked for a screenshot, so it took one or threw.
      file: observed.screenshot!,
      knobs: observed.knobs?.knobs ?? const [],
    );
  }

  /// N frames of one entry's motion, as one contact sheet.
  ///
  /// One guest, N seeks. Calling [capture] in a loop would compile, launch and
  /// tear down a guest per frame, which is most of the cost and all of the wall
  /// clock — the seek itself is a frame. That is why the filmstrip is a method
  /// here rather than a loop in the caller.
  Future<CatalogFilmstrip> filmstrip({
    required String entryId,
    required String output,
    required List<double> stops,
    CaptureViewport viewport = CaptureViewport.panel,
    Map<String, String> knobs = const {},
    Map<String, String> axes = const {},
    int cellWidth = 320,
  }) => _withGuest(entryId: entryId, viewport: viewport, (guest) async {
    if (axes.isNotEmpty) await guest.applyAxes(entryId, axes);
    if (knobs.isNotEmpty) await guest.applyKnobs(entryId, knobs);

    var scratch = Directory(p.join(p.dirname(output), 'frames'))
      ..createSync(recursive: true);
    var frames = <FilmstripFrame>[];
    try {
      var durationMs = 0;
      for (var (index, t) in stops.indexed) {
        var landed = await guest.seekMotion(t);
        durationMs = landed.$2;
        var file = await guest.capture(
          p.join(scratch.path, 'frame-$index.png'),
          pixelRatio: viewport.pixelRatio,
        );
        frames.add(FilmstripFrame(file: file, t: t, ms: landed.$1));
      }
      return CatalogFilmstrip(
        file: composeFilmstrip(frames, output: output, cellWidth: cellWidth),
        stops: stops,
        durationMs: durationMs,
      );
    } finally {
      // The sheet is the artifact; the frames were scaffolding.
      if (scratch.existsSync()) scratch.deleteSync(recursive: true);
    }
  });

  /// The whole motion as a video file.
  ///
  /// The same loop as [filmstrip] — one guest, N seeks — with two differences,
  /// and both of them are why this is worth having rather than a filmstrip
  /// with a large `frames`. The stops come from the motion's *own* duration so
  /// the clip plays at the speed it was authored at, and the frames go
  /// straight to the encoder as pixels instead of becoming N PNGs on disk.
  ///
  /// Nothing here plays anything. Every frame is `evaluate(t)` at a stop this
  /// method chose, which is the same call the scrubber makes and the same one
  /// a golden test makes — so a video cannot drift from what the panel shows,
  /// and rendering is not bounded by real time. That is the whole reason the
  /// law is worth keeping: a clock in the motion would make this a recording.
  Future<CatalogVideo> video({
    required String entryId,
    required String output,
    int fps = 30,
    CaptureViewport viewport = CaptureViewport.panel,
    Map<String, String> knobs = const {},
    Map<String, String> axes = const {},
  }) => _withGuest(entryId: entryId, viewport: viewport, (guest) async {
    if (axes.isNotEmpty) await guest.applyAxes(entryId, axes);
    if (knobs.isNotEmpty) await guest.applyKnobs(entryId, knobs);

    // The duration is the motion's, and only the guest knows it — so the
    // first seek is what tells us how many frames there are to render.
    var (_, durationMs) = await guest.seekMotion(0);
    if (durationMs <= 0) {
      throw StateError(
        "this entry's motion reports no duration, so there is nothing to "
        'render at $fps frames a second',
      );
    }
    var stops = videoStops(durationMs: durationMs, fps: fps);

    var render = Stopwatch()..start();
    var (first, _) = await guest.captureImage(pixelRatio: viewport.pixelRatio);
    var encoder = await VideoEncoder.start(
      output: output,
      width: first.width,
      height: first.height,
      fps: fps,
    );
    try {
      encoder.add(first);
      for (var t in stops.skip(1)) {
        await guest.seekMotion(t);
        var (frame, _) = await guest.captureImage(
          pixelRatio: viewport.pixelRatio,
        );
        encoder.add(frame);
      }
    } catch (_) {
      await encoder.abort();
      rethrow;
    }
    render.stop();

    var flush = Stopwatch()..start();
    var file = await encoder.finish();
    flush.stop();

    return CatalogVideo(
      file: file,
      frames: encoder.frames,
      fps: fps,
      durationMs: durationMs,
      renderTime: render.elapsed,
      encodeTime: flush.elapsed,
    );
  });

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
      // The quarantine counts as known, and the difference matters to whoever
      // reads the error: an entry that does not compile exists, and selecting
      // it is how the daemon retries it — so letting it through produces the
      // compiler's own diagnostics below, where refusing here produced "no such
      // entry" for a file the caller is looking at.
      var known = {
        for (var entry in ready.entries) entry.id,
        for (var broken in ready.quarantined) broken.entry.id,
      };
      if (!known.contains(entryId)) {
        throw ArgumentError.value(
          entryId,
          'entryId',
          'no such entry. Known ids: ${(known.toList()..sort()).join(', ')}',
        );
      }
      // A whole kernel, not a delta: the guest loads it from disk at launch.
      var compiled = await daemon.select(entryId, full: true);
      if (!compiled.ok) {
        throw StateError('$entryId did not compile:\n${compiled.error}');
      }
      guest = await _GuestSession.start(
        hostPath: await daemon.hostPath(),
        assetsDir: ready.assetsDir,
        icuData: ready.icuData,
        name: ready.sessionId,
        viewport: viewport,
      );
      return await body(guest);
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
  /// `ext.flutterware.knobs` and answers with what its last build
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

    /// Where to park the entry's motion, 0..1. See [_GuestSession.seekMotion].
    double? motionT,
  }) => _withGuest(entryId: entryId, viewport: viewport, (guest) async {
    if (axes.isNotEmpty) await guest.applyAxes(entryId, axes);
    if (knobs.isNotEmpty) await guest.applyKnobs(entryId, knobs);
    await guest.applyDebug(debug);
    // After the knobs and the axes, because both rebuild the demo and a
    // rebuilt scope would start wherever its controller says rather than where
    // this was asked to put it.
    if (motionT != null) await guest.seekMotion(motionT);

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
}

/// What `--node` and `--annotate` mean against one tree: a rect to crop to, and
/// the boxes to draw.
///
/// One implementation, because there were briefly two. `observe` was written
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
      crop = _cropTo(tree, node, entryId);
    }
    return _Framing(
      crop: crop,
      boxes: annotate ? tree.nodes.toList() : const [],
    );
  }

  /// The box [selector] names — **a widget's name, or a tree id**.
  ///
  /// The name is what this is for, and the id is the fallback rather than the
  /// other way round. Asking for a picture of a widget you are working on is
  /// the common case by a distance, and requiring an id made it a two-step:
  /// read a tree, find the position, ask again — thousands of tokens to
  /// photograph something the caller could already name. `SplitButton` is what
  /// somebody has in their hand.
  ///
  /// Matched by [InspectTree.matching], which is the same matcher `find` uses,
  /// so one grammar covers looking something up and cropping to it.
  ///
  /// Several matches are refused, never guessed. A silently-picked first
  /// match is a picture of the wrong widget that looks like a picture of the
  /// right one, and the refusal carries the ids so the next call is exact.
  static InspectLayout _cropTo(
    InspectTree tree,
    String selector,
    String entryId,
  ) {
    var found = tree.resolve(selector);
    if (found.length == 1) return _boxOf(found.single, selector, entryId);

    var matches = [
      for (var node in found)
        if (node.layout != null) node,
    ];
    if (matches.length == 1) return matches.single.layout!;
    if (matches.isEmpty) {
      throw ArgumentError.value(
        selector,
        'node',
        'nothing in $entryId is called that, and it is not the id of a node '
            'either. `node` takes a widget name — `SplitButton`, `Save` — '
            'matched against every type, description and label on screen, or '
            'an id from a tree read. Read the entry without `node` to see '
            'what is there.',
      );
    }
    var named = matches
        .take(8)
        .map((node) => '${node.type} (${node.id})')
        .join(', ');
    throw ArgumentError.value(
      selector,
      'node',
      '${matches.length} widgets match "$selector" in $entryId, and cropping '
          'to the wrong one produces a picture that looks right: $named'
          '${matches.length > 8 ? ', …' : ''}. Name one by its id, or narrow '
          'the text.',
    );
  }

  static InspectLayout _boxOf(InspectNode found, String named, String entryId) {
    var box = found.layout;
    if (box == null) {
      throw ArgumentError.value(
        named,
        'node',
        '${found.type} has no box of its own to crop to. Providers and '
            'builders lay nothing out; ask for one of its children.',
      );
    }
    return box;
  }

  final InspectLayout? crop;
  final List<InspectNode> boxes;
}

/// One rendered build, and everything the call asked about it.
///
/// Nullable per section rather than empty-per-section, and the distinction is
/// load-bearing: null means *not asked for*, empty means *asked and there is
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

/// A contact sheet, and where on the playhead its frames were taken.
class CatalogFilmstrip {
  CatalogFilmstrip({
    required this.file,
    required this.stops,
    required this.durationMs,
  });

  final File file;
  final List<double> stops;
  final int durationMs;
}

/// A rendered motion, and what it cost to render.
class CatalogVideo {
  CatalogVideo({
    required this.file,
    required this.frames,
    required this.fps,
    required this.durationMs,
    required this.renderTime,
    required this.encodeTime,
  });

  final File file;
  final int frames;
  final int fps;

  /// The motion's own duration, which is what set the frame count.
  final int durationMs;

  /// Seeking and capturing, which is the cost that scales with the clip.
  final Duration renderTime;

  /// Waiting for the encoder after the last frame went in. Small, because
  /// `ffmpeg` was encoding all along.
  final Duration encodeTime;
}

/// A captured frame, and the knobs it was rendered with.
class CatalogCapture {
  CatalogCapture({required this.file, required this.knobs});

  final File file;

  /// What the entry reported *after* the values were applied — so a clamped or
  /// ignored value is visible rather than assumed.
  final List<KnobDescriptor> knobs;
}

/// What the compiler could and could not build.
class CatalogCheck {
  CatalogCheck({required this.servable, required this.quarantined});

  final List<CatalogEntry> servable;

  /// Entries the compiler refused, each with its diagnostics verbatim.
  final List<QuarantinedEntry> quarantined;

  bool get ok => quarantined.isEmpty;
}

/// What a settle counts as quiet, across every entry one guest renders.
///
/// `pendingImageCount` is the whole cache's, and the guest outlives every
/// entry rendered against it. One demo asking for an image that never
/// resolves — a missing asset, a provider that neither completes nor errors —
/// leaves the count above zero for the life of the process. A rule that waits
/// for zero then waits the *full deadline on every entry after it*, including
/// the static ones, and reports each of them as never having settled.
///
/// Measured on this repo's own catalog before this existed: entries 1–4
/// settled in 61–142ms, entry 5 left one load pending, and all 94 after it
/// cost ~3045ms each — **282 seconds of a 324-second audit**, spent waiting on
/// an image no later entry had asked for.
///
/// So the bar is learned rather than assumed. It only rises after a deadline
/// has actually expired with the count stuck above it — never on a guess — and
/// it drops back the moment a settle sees a clean cache, so a stuck completer
/// that is later evicted does not leave it raised behind it.
///
/// Images only. `transientCallbackCount` is tied to mounted tickers and an
/// entry switch remounts, so it returns to zero on its own; giving an
/// animation the same allowance would report a demo that genuinely never stops
/// moving as a settled picture, which is the one thing the count is read for.
class SettleFloor {
  /// How many loads this guest has been shown not to finish.
  int get stuck => _stuck;
  var _stuck = 0;

  /// The bar this pass is judged against, frozen at [begin] so that what the
  /// pass learns cannot move it while it runs.
  var _bar = 0;

  /// The fewest pending loads seen this pass, or -1 before the first poll.
  var _lowest = -1;

  /// Opens one settle.
  void begin() {
    _bar = _stuck;
    _lowest = -1;
  }

  /// Whether this poll looks like a finished frame.
  bool quiet(int pending, int transient) {
    if (_lowest < 0 || pending < _lowest) _lowest = pending;
    return pending <= _bar && transient == 0;
  }

  /// The pass settled, with [pending] loads outstanding.
  void settled(int pending) {
    if (pending == 0) _stuck = 0;
  }

  /// The pass ran out of time.
  ///
  /// When the count never came back down past [_lowest], that many loads are
  /// not coming — remember it, so the next entry waits for its own images
  /// rather than for this one's. A pass that timed out on an *animation*
  /// instead arrives here with [_lowest] at or under the bar and moves it
  /// nowhere.
  void gaveUp() {
    if (_lowest > _bar) _stuck = _lowest;
  }
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
    required String name,
    required CaptureViewport viewport,
  }) async {
    // Keyed by the daemon session, like the GUI's `g-<name>.sock` — the run
    // directory is shared by every project on the machine, so anything less
    // unique means one capture deletes another's socket mid-launch. An earlier
    // version hashed the work directory, which is the *same* directory for
    // every capture on the machine. Not under the build directory: a unix
    // socket path is capped at 104 bytes, and a build directory inside a
    // worktree already spends most of that.
    var socketPath = checkSocketPath(
      p.join(flutterwareRunDir(), 'shot-$name.sock'),
    );
    // The frame scratch gets the same key for the same reason: every capture
    // used to write one shared `screenshot.rawframe`, and two concurrent
    // captures swapped frames.
    var workDir = p.join(flutterwareRunDir(), 'cap-$name');
    var socket = File(socketPath);
    if (socket.existsSync()) socket.deleteSync();
    var server = await ServerSocket.bind(
      InternetAddress(socketPath, type: InternetAddressType.unix),
      0,
    );

    Process? guest;
    try {
      guest = await Process.start(hostPath, [
        assetsDir,
        icuData,
        socketPath,
        '${viewport.width}',
        '${viewport.height}',
      ]);
      var vmServiceUri = Completer<String>();
      // The guest's last few lines, kept rather than drained: an engine that
      // cannot run its kernel says so here and nowhere else, and the connect
      // below is what asks for them.
      var printed = <String>[];
      void remember(String line) {
        printed.add(line);
        if (printed.length > 20) printed.removeAt(0);
      }

      guest.stdout
          .transform(const SystemEncoding().decoder)
          .transform(const LineSplitter())
          .listen((line) {
            remember(line);
            var match = RegExp(r'(http://127\.0\.0\.1:\S+/)').firstMatch(line);
            if (match != null && !vmServiceUri.isCompleted) {
              vmServiceUri.complete(match.group(1));
            }
          });
      guest.stderr
          .transform(const SystemEncoding().decoder)
          .transform(const LineSplitter())
          .listen(remember);

      var connected = await Future.any<Object?>([server.first, guest.exitCode]);
      if (connected is! Socket) {
        throw StateError('the guest exited before connecting');
      }

      // Raced and bounded like the connect above: a guest that binds its
      // socket and then dies — or whose stdout stops matching the scrape —
      // would otherwise hang this await forever with the process orphaned.
      var announced = await Future.any<Object?>([
        vmServiceUri.future,
        guest.exitCode,
      ]).timeout(const Duration(seconds: 30));
      if (announced is! String) {
        throw StateError('the guest exited before announcing its VM service');
      }

      var session = _GuestSession._(
        guest,
        connected,
        server,
        FrameReader(),
        await GuestVmService.connect(
          announced,
          describeGuest: () => printed.join('\n'),
        ),
        workDir,
      );
      connected.listen(session._onData);
      // Argv carried the buffer size; this carries what the buffer *means*. The
      // ratio and the safe areas have no other way in, and without them a phone
      // capture is a correctly-sized picture of the wrong layout.
      session._resize(viewport);
      // And what the buffer is a picture *of*. Awaited, unlike the resize:
      // this one is a round trip over the VM service, and a capture that
      // started before it landed would photograph the demo rendering as this
      // machine. The first frame has not been asked for yet, so nothing is
      // remounted by it — the guest simply builds staged.
      await session._inspect.setStaging(viewport.platform);
      // And how much of that screen a keyboard would take. Awaited for the
      // same reason: a capture that started before it landed would photograph
      // the full screen and file it as the picture of a raised keyboard.
      await session._inspect.setKeyboard(
        mode: viewport.keyboardMode,
        height: viewport.keyboard,
        keypadHeight: viewport.keypadKeyboard,
      );
      return session;
    } catch (_) {
      // Whatever failed above, nothing owns the guest yet.
      guest?.kill();
      await server.close();
      rethrow;
    }
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

  /// Puts [entryId] on screen without recompiling or reloading anything — see
  /// [InspectClient.showEntry], which the panel switches through as well.
  Future<bool> showEntry(String entryId) => _inspect.showEntry(entryId);

  /// What [entryId] declares, once the guest has actually built it.
  ///
  /// Renders a frame first, and throws it away. A knob is declared while
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
  /// Takes the tree rather than reading one, deliberately: an id names a
  /// position in a particular tree, so a hit resolved against a second reading
  /// answers about a tree the caller was never shown.
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
            'PreviewShell around the demo.',
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
  /// Renders a frame first, and it is not the usual reason. Knobs and the
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

  /// Parks the entry's motion at [t], 0..1.
  ///
  /// A frame first, for the reason [applyDebug] gives: a `MotionScope`
  /// registers its extensions when it *mounts*, so a seek asked for before the
  /// demo has built comes back "method not found" rather than seeking.
  ///
  /// The seek itself answers after the guest's next frame, so by the time this
  /// returns the picture is already at `t` and the capture that follows needs no
  /// settling of its own.
  var _motionReady = false;

  Future<(int, int)> seekMotion(double t) async {
    // Only the first one pays for it. Once the scope has mounted the extension
    // stays registered, and a filmstrip that rendered a throwaway frame before
    // every seek would double the cost of the thing it exists to make cheap.
    if (!_motionReady) {
      await _renderScratchFrame();
      _motionReady = true;
    }
    // List first, and seek the scope the duration is read from: the guest
    // resolves a nameless seek only while exactly one scope is mounted, so a
    // demo with two would refuse — and the refusal surfaced here as the
    // misleading "no mounted MotionScope".
    var listed = await _vmService.callExtension('ext.flutterware.motion.list');
    var scope = ((listed?['scopes'] as List?) ?? const []).firstOrNull as Map?;
    var reply = await _vmService.callExtension(
      'ext.flutterware.motion.seek',
      args: {if (scope?['id'] case String id) 'scope': id, 't': '$t'},
    );
    if (reply == null) {
      throw ArgumentError.value(
        t,
        't',
        'this entry has no mounted MotionScope to seek',
      );
    }
    return (
      (reply['ms'] as num?)?.toInt() ?? 0,
      (scope?['durationMs'] as num?)?.toInt() ?? 0,
    );
  }

  /// Draws one throwaway frame, so the demo has built.
  ///
  /// Separated from the reads because there were seven of these per
  /// observation. Every `settled*` rendered its own, which was right when each
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
  /// Coerced to the kind the preview declared, because everything arrives as text:
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

  /// The guest's next frame, decoded and not written anywhere.
  ///
  /// What [capture] does minus the PNG: a batch comparing pixels never wants
  /// the file, and the encoder it skips costs ~7.5ms a picture — measured on
  /// `ScenarioRunArgs.captureRaw`, along with what it costs in bytes.
  /// The frame, and what the guest could say about it having stopped moving.
  Future<(img.Image, ({bool settled, bool seesAnimations}))> captureImage({
    double pixelRatio = 1,
  }) async {
    var settled = await _settle();
    return (await _capture.capture(pixelRatio: pixelRatio), settled);
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
    await _settle();
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

  final _floor = SettleFloor();

  /// Waits until the guest has no image loads in flight, bounded.
  ///
  /// A demo's images arrive after its layout: `Image.asset` registers the load
  /// during build and the decode lands asynchronously, so a frame photographed
  /// in between shows the layout without the pixels — measured on
  /// `asset_smoke.dart`, where both images were simply absent from an otherwise
  /// perfect capture. Every call to the extension renders a frame, which is
  /// what starts the loads on a fresh guest and paints whatever has been
  /// delivered since; see [GuestImages].
  ///
  /// Zero twice in a row, because one asynchronous hop can separate a
  /// build from the `Image` it creates — a `FutureBuilder` over
  /// `rootBundle.load` reads zero pending while its future is still in flight,
  /// and by the next frame the image it built is either delivered or counted.
  ///
  /// Bounded, never a hang: a demo that streams images forever costs a
  /// slightly-early picture, the same trade [SettleRegistry] makes for busy
  /// plugins.
  ///
  /// [GuestVmService.requireExtension] rather than the tolerant form, which is
  /// this bug's whole history: the first capture of a fresh
  /// guest lands before `main` has registered anything, and a call that treats
  /// "not registered yet" as "no answer needed" skips the wait on exactly the
  /// capture most likely to race the decode — intermittently, which is how the
  /// missing images stayed invisible in the first place.
  ///
  /// Draws frames until nothing is still moving, or until the deadline.
  ///
  /// Returns false when it gave up — a looping animation never drains, and a
  /// picture taken in the middle of one is worth having *and* worth labelling.
  ///
  /// `transient` is absent from an older guest's reply and reads as zero, which
  /// is the old behaviour: images only. That is the graceful half of a version
  /// skew — the base side of a comparison against a checkout that predates the
  /// field settles for images alone rather than failing to answer at all.
  ///
  /// What counts as quiet is [SettleFloor]'s, because one guest renders every
  /// entry of a catalog-wide run and a stuck load is not that run's to wait
  /// for twice.
  Future<({bool settled, bool seesAnimations})> _settle() async {
    var deadline = Stopwatch()..start();
    var zeros = 0;
    var seesAnimations = true;
    _floor.begin();
    while (deadline.elapsed < const Duration(seconds: 3)) {
      var report = await _vmService.requireExtension(
        'ext.flutterware.imagesSettled',
      );
      if (report == null) return (settled: true, seesAnimations: true);
      // Absent from a guest built before the field existed. Reported rather
      // than silently treated as zero: that guest settles for images alone, so
      // its frames can be taken mid-transition — and a comparison whose two
      // sides settle by different rules differs for a reason that is not the
      // branch's.
      seesAnimations = report.containsKey('transient');
      var pending = (report['pending'] as num? ?? 0).toInt();
      var transient = (report['transient'] as num? ?? 0).toInt();
      if (_floor.quiet(pending, transient)) {
        // Twice, because one quiet frame is what the frame *before* an
        // animation starts also looks like.
        if (++zeros >= 2) {
          _floor.settled(pending);
          return (settled: true, seesAnimations: seesAnimations);
        }
      } else {
        zeros = 0;
      }
    }
    _floor.gaveUp();
    return (settled: false, seesAnimations: seesAnimations);
  }

  Future<void> close() async {
    await _vmService.close();
    _connection.add(encodeMessage(const ShutdownMessage()));
    await _connection.flush();
    await _connection.close();
    _guest.kill();
    await _server.close();
    // Frames delete themselves as they are read; this picks up the directory,
    // which would otherwise accumulate one empty `cap-<session>` per capture.
    try {
      Directory(_workDir).deleteSync(recursive: true);
    } on FileSystemException {
      // Housekeeping only — a frame still being written wins, and loses
      // nothing but an empty directory.
    }
  }
}
