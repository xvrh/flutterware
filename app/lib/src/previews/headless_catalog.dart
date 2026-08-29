import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:collection/collection.dart';
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
import '../embedder/raw_frame.dart';
import '../embedder/protocol.dart';
import 'catalog_picture.dart';
import 'catalog_render.dart';
import 'catalog_values.dart';
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
/// **The embedder backend of [CatalogRenderer]** — a real engine drawing a real
/// frame, which is what the panel shows and therefore what a picture meant to
/// agree with the panel comes from. The same pipeline the GUI drives, invoked
/// by whoever asks — a button, `fw`, or an agent. Nothing here touches Flutter,
/// so it runs anywhere the daemon does.
///
/// The guest is spawned with `--capture-raw`, which writes the composited frame
/// the user would have seen rather than re-rasterising it.
class HeadlessCatalog extends CatalogRenderer {
  HeadlessCatalog({required this.dartExecutable, required this.config});

  /// A real Dart VM — the Flutter SDK's `dart`, never the running executable
  /// when that is a Flutter app.
  final String dartExecutable;

  final DaemonConfig config;

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
    String? scope,

    /// Frames to draw per stop, overriding what a probe measures. The probe is
    /// right for most screens and cannot be right for all of them: how long a
    /// screen takes to arrive at a playhead depends on where it is coming
    /// from, and a probe samples a few places rather than every one.
    int? framesPerStop,
  }) => _withGuest(entryId: entryId, viewport: viewport, (guest) async {
    if (axes.isNotEmpty) await guest.applyAxes(entryId, axes);
    if (knobs.isNotEmpty) await guest.applyKnobs(entryId, knobs);

    // One opening seek to learn the duration and settle on a scope, then the
    // whole strip in a single call — the same batched render a video walks.
    var opening = await guest.seekMotion(stops.first, scope: scope);
    var frames = <FilmstripFrame>[];
    var index = 0;
    var perStop =
        framesPerStop ?? await _measureSettleDepth(guest, opening.scope, stops);
    await for (var raw in guest.renderSequence(
      scope: opening.scope,
      stops: stops,
      framesPerStop: perStop,
    )) {
      var t = stops[index++];
      frames.add(
        FilmstripFrame(
          image: raw.toImage(),
          t: t,
          // The playhead's own units, computed rather than reported: a
          // batched render is not asked where it landed frame by frame, and
          // `t` of a known duration is the same number the guest would give.
          ms: (t * opening.durationMs).round(),
        ),
      );
    }
    return CatalogFilmstrip(
      file: composeFilmstrip(frames, output: output, cellWidth: cellWidth),
      stops: stops,
      durationMs: opening.durationMs,
      framesPerStop: perStop,
    );
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
    String? scope,

    /// Frames to draw per stop, overriding what a probe measures. See
    /// [filmstrip].
    int? framesPerStop,
  }) => _withGuest(entryId: entryId, viewport: viewport, (guest) async {
    if (axes.isNotEmpty) await guest.applyAxes(entryId, axes);
    if (knobs.isNotEmpty) await guest.applyKnobs(entryId, knobs);

    // The duration is the motion's, and only the guest knows it — so the
    // first seek is what tells us how many frames there are to render.
    var opening = await guest.seekMotion(0, scope: scope);
    var durationMs = opening.durationMs;
    if (durationMs <= 0) {
      throw StateError(
        "this entry's motion reports no duration, so there is nothing to "
        'render at $fps frames a second',
      );
    }
    var stops = videoStops(durationMs: durationMs, fps: fps);

    var render = Stopwatch()..start();
    // The frames arrive as a sequence the guest writes on its own, so the
    // first one has to be waited for before the encoder can be opened — it is
    // what says how big the picture is and what order its bytes are in.
    var frames = guest.renderSequence(
      scope: opening.scope,
      stops: stops,
      // A screen that applies its playhead in stages shows the *previous*
      // stop on the frame that moved it, so its picture is the last of the
      // group. Measured on this screen rather than assumed.
      framesPerStop:
          framesPerStop ??
          await _measureSettleDepth(guest, opening.scope, stops),
    );
    VideoEncoder? encoder;
    try {
      var handoff = Stopwatch();
      var index = 0;
      await for (var frame in frames) {
        encoder ??= await VideoEncoder.start(
          output: output,
          width: frame.width,
          height: frame.height,
          fps: fps,
          // The guest's own order. Converting it here would cost more than the
          // encode does — see [FrameCapture.captureRaw].
          pixelFormat: frame.pixelFormat,
        );
        handoff.start();
        encoder.addRaw(frame);
        handoff.stop();
        index++;
      }
      guest.timings.encoderHandoff = handoff.elapsed;
      // Position is the only thing pairing a file with a stop, so a short
      // sequence is a video missing a moment rather than a shorter video.
      if (index != stops.length) {
        throw StateError(
          'the guest rendered $index frames for ${stops.length} stops — '
          'something other than the motion was scheduling frames, and the '
          'clip would be of the wrong moments',
        );
      }
    } catch (_) {
      await encoder?.abort();
      rethrow;
    }
    if (encoder == null) {
      throw StateError('the guest rendered nothing to encode');
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
      scope: opening.scope,
      mountedScopes: opening.mounted,
      timings: guest.readCaptureCosts(),
    );
  });

  /// How many frames a stop is worth on this screen, measured **on the
  /// pixels**.
  ///
  /// The question is "when has the screen finished arriving", and the only
  /// honest answer to it is that two frames in a row came out the same. Asking
  /// the scheduler instead — is a frame pending, is a ticker running — was
  /// tried and under-reports: a `PageView` moved by `jumpTo` onto a page
  /// boundary toggles `pageSnapping`, which makes `Scrollable` build a new
  /// `ScrollPosition` and absorb the old one, and in the frames that takes
  /// there are moments when nothing is scheduled and nothing is ticking and
  /// the picture is still a page behind. Measured on the onboarding flow, the
  /// scheduler said two where the pixels say five, and a filmstrip rendered at
  /// two was a faithful picture of the wrong moments.
  ///
  /// Seeks somewhere the screen is *not*, because parking the playhead where
  /// it already sits changes nothing and every screen answers one. Three stops
  /// are probed and the deepest wins: stops do not settle alike, and the
  /// expensive ones are exactly the ones a cheap probe misses.
  Future<int> _measureSettleDepth(
    _GuestSession guest,
    String scope,
    List<double> stops,
  ) async {
    var deepest = 1;
    for (var fraction in const [0.25, 0.5, 0.75]) {
      var index = (stops.length * fraction).floor().clamp(0, stops.length - 1);
      var probe = await guest.seekMotion(stops[index], scope: scope);
      // The seek drew this many getting here; every capture below draws one
      // more, because arming a capture forces a frame.
      var drawn = probe.settleFrames;
      var previous = await guest.captureRawFrame(alreadySettled: true);
      drawn++;
      while (drawn < _settleDepthCap) {
        var next = await guest.captureRawFrame(alreadySettled: true);
        drawn++;
        if (_sameFrame(previous, next)) {
          // `next` matched, so the screen was already finished when `previous`
          // was taken — one frame earlier than the one that proved it.
          drawn--;
          break;
        }
        previous = next;
      }
      if (drawn > deepest) deepest = drawn;
    }
    return deepest;
  }

  /// Where the probe gives up. A screen that never repeats a frame is
  /// animating on its own, and no number of frames would settle it.
  static const _settleDepthCap = 12;

  /// Whether two frames are the same picture.
  ///
  /// Compared eight bytes at a time, and every byte of them: a sampled
  /// comparison would call a screen settled that had one page-shift left to
  /// go, which is precisely the case this exists to catch.
  static bool _sameFrame(RawFrame a, RawFrame b) {
    if (a.width != b.width || a.height != b.height) return false;
    if (a.pixels.length != b.pixels.length) return false;
    var words = a.pixels.length ~/ 8;
    // Byte offsets into the source, not element counts of the view.
    var left = Uint64List.sublistView(a.pixels, 0, words * 8);
    var right = Uint64List.sublistView(b.pixels, 0, words * 8);
    for (var i = 0; i < words; i++) {
      if (left[i] != right[i]) return false;
    }
    for (var i = words * 8; i < a.pixels.length; i++) {
      if (a.pixels[i] != b.pixels[i]) return false;
    }
    return true;
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

  /// One entry, in a guest of its own: start a daemon, compile the entry,
  /// render one frame, tear it all down.
  ///
  /// Fine for one entry, which is the shape of every caller left here.
  /// Catalog-wide batches — the audit, the comparison, the thumbnails — render
  /// under `flutter_tester` instead, where a demo that animates for ever costs
  /// fake clock rather than real seconds.
  ///
  /// Order matters and is not arbitrary: axes before knobs because a shell
  /// rebuild changes what the demo is handed; debug before any read because
  /// `platform` and `brightness` change what the demo *builds*; the tree before
  /// the hit test because a hit is only meaningful against a particular tree;
  /// and the capture last, because a picture should be of the state everything
  /// else described.
  ///
  /// A knob name the entry does not declare is an error naming the ones it
  /// does: a silently ignored knob produces a picture that looks right and is
  /// not.
  @override
  Future<CatalogObservation> render(CatalogRender request) => _withGuest(
    entryId: request.entryId,
    viewport: request.viewport,
    (guest) async {
      var entryId = request.entryId;
      // **The device's identity, which the resize cannot carry.** The
      // embedder's window-metrics event has a size, a ratio and four insets
      // and nothing else, so everything beyond geometry travels over the VM
      // service — and until now only the *panel* sent this one
      // (`catalog_view.dart`'s `stageAs`). Headless, a preview asked for on an
      // iPhone was given a phone's screen and left running as whatever
      // platform the bare embedder reports: Cupertino widgets picked the wrong
      // branch, and a `ThemeData` computing `materialTapTargetSize` from
      // `defaultTargetPlatform` sized its buttons for the wrong machine.
      // `CaptureViewport.platform` has always existed to say this; nothing
      // outside the panel said it.
      await guest.stageAs(request.viewport.platform);
      if (request.axes.isNotEmpty) await guest.applyAxes(entryId, request.axes);
      if (request.knobs.isNotEmpty) {
        await guest.applyKnobs(entryId, request.knobs);
      }
      await guest.applyDebug(request.debug);
      // After the knobs and the axes, because both rebuild the demo and a
      // rebuilt scope would start wherever its controller says rather than
      // where this was asked to put it.
      if (request.motionT case var t?) await guest.seekMotion(t);

      // **One frame, then every read off it.** This is the actual content of
      // "one render", and it was not true before: each `settled*` drew its own
      // scratch frame, so an observation asking five questions drew five or six
      // — and `settledHitTest` read a *second* tree to resolve against, which
      // is the assumption collapsing the actions was supposed to remove rather
      // than preserve.
      //
      // When a picture is wanted and nothing has to be read *before* it is
      // taken, the picture **is** the settling frame. That is not a
      // micro-optimisation: a plain `screenshot` is the commonest call there
      // is, and every frame here writes a PNG to disk and deletes it again. A
      // crop or an annotation needs the tree first, so those still settle
      // separately.
      File? picture;
      if (request.screenshot case var output? when !request.framed) {
        picture = await guest.capture(
          output,
          pixelRatio: request.viewport.pixelRatio,
        );
      } else {
        await guest.settle();
      }

      var tree = request.needsTree ? await guest.readTree(entryId) : null;

      // Against the tree above, by argument rather than by luck.
      var hits = request.at == null || tree == null
          ? null
          : await guest.readHitTest(tree, request.at!.$1, request.at!.$2);

      var errors = await guest.readErrors(entryId);
      var logs = request.wantLogs ? await guest.readLogs(entryId) : null;
      var applied = request.wantKnobs ? await guest.readKnobs(entryId) : null;
      var axes = request.wantAxes ? await guest.readAxes(entryId) : null;

      if (request.screenshot case var output? when picture == null) {
        var framing = PictureFraming.of(
          // `framed` is what put us here, and `needsTree` covers it, so the
          // tree has been read.
          tree!,
          node: request.cropNode,
          annotate: request.annotate,
          entryId: entryId,
        );
        picture = await guest.capture(
          output,
          framing: framing,
          pixelRatio: request.viewport.pixelRatio,
        );
      }

      return CatalogObservation(
        tree: tree,
        errors: errors,
        logs: logs,
        knobs: applied,
        axes: axes,
        hits: hits,
        screenshot: picture,
      );
    },
  );
}

/// Where a render's time went, inside the guest exchange.
///
/// A frame of a motion costs four VM service round trips and one socket
/// exchange, and the four are not equal: `motion.list` walks every target and
/// every segment, `motion.seek` waits a frame, and the settle asks whether the
/// picture has stopped moving at least twice. Splitting them is the difference
/// between "render on another engine" and "stop asking the same question".
class GuestTimings {
  Duration motionList = Duration.zero;
  Duration motionSeek = Duration.zero;
  Duration settle = Duration.zero;
  Duration frame = Duration.zero;

  int listCalls = 0;
  int seekCalls = 0;
  int frames = 0;

  /// Copying decoded pixels into the encoder's stdin.
  Duration encoderHandoff = Duration.zero;

  /// The guest's own render loop, end to end — every frame drawn and written,
  /// with nothing asked of it in between.
  Duration guestRender = Duration.zero;

  /// How long this side sat waiting for a frame that had not landed yet.
  ///
  /// Read against [guestRender] it says which half is the bottleneck: near it,
  /// the guest is drawing and this side is idle; near zero, the guest is ahead
  /// and reading and encoding is the wall.
  Duration awaitingFrames = Duration.zero;

  /// The capture, split into what the guest did and what this side did.
  Duration captureDraw = Duration.zero;
  Duration captureRead = Duration.zero;
  Duration captureDecode = Duration.zero;
  int captureBytes = 0;

  Map<String, Object?> toJson() => {
    'motionListMs': motionList.inMilliseconds,
    'motionSeekMs': motionSeek.inMilliseconds,
    'settleMs': settle.inMilliseconds,
    'frameMs': frame.inMilliseconds,
    'captureDrawMs': captureDraw.inMilliseconds,
    'captureReadMs': captureRead.inMilliseconds,
    'captureDecodeMs': captureDecode.inMilliseconds,
    'encoderHandoffMs': encoderHandoff.inMilliseconds,
    'guestRenderMs': guestRender.inMilliseconds,
    'awaitingFramesMs': awaitingFrames.inMilliseconds,
    'capturedMB': (captureBytes / 1048576).round(),
    'listCalls': listCalls,
    'seekCalls': seekCalls,
    'frames': frames,
  };
}

/// Where a seek landed, and which scope took it.
///
/// [scope] and [mounted] ride along because a composed screen mounts several
/// playheads — a flow and the components inside it — and which one a render
/// walked is not something the caller can infer from the picture. A video of
/// the wrong timeline looks like a video.
class MotionSeek {
  MotionSeek({
    required this.ms,
    required this.durationMs,
    required this.scope,
    required this.mounted,
    required this.settled,
    required this.settleFrames,
  });

  /// Where the playhead landed, in the motion's own milliseconds.
  final int ms;

  /// That motion's whole duration.
  final int durationMs;

  /// The scope that was seeked.
  final String scope;

  /// Every scope mounted at the time, in mount order — which is tree order,
  /// so the first encloses the rest.
  final List<String> mounted;

  /// Whether the frame this seek waited for was already quiet — no image
  /// loads outstanding, nothing animating — or null from a guest too old to
  /// say.
  ///
  /// Null and false are the same instruction (settle before capturing) and
  /// are kept apart anyway, because a guest that cannot answer is a version
  /// skew and a guest that answers "no" is a picture still moving.
  final bool? settled;

  /// How many frames this seek had to draw before the screen stopped drawing
  /// — one for a screen that shows its playhead where it reads it, more for
  /// one that applies it in stages.
  ///
  /// It is what a render uses to decide how many frames a stop is worth.
  /// Guessing wrong photographs a screen still on its way, which looks like a
  /// perfectly good picture of the wrong moment.
  final int settleFrames;
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
    required this.scope,
    required this.mountedScopes,
    required this.timings,
  });

  final File file;
  final int frames;
  final int fps;

  /// The scope whose playhead was walked.
  final String scope;

  /// Every playhead that was mounted, so a render of the wrong one is visible
  /// rather than merely wrong.
  final List<String> mountedScopes;

  /// Where the per-frame time went.
  final GuestTimings timings;

  /// The motion's own duration, which is what set the frame count.
  final int durationMs;

  /// Seeking and capturing, which is the cost that scales with the clip.
  final Duration renderTime;

  /// Waiting for the encoder after the last frame went in. Small, because
  /// `ffmpeg` was encoding all along.
  final Duration encodeTime;
}

/// A contact sheet, and where on the playhead its frames were taken.
class CatalogFilmstrip {
  CatalogFilmstrip({
    required this.file,
    required this.stops,
    required this.durationMs,
    this.framesPerStop = 1,
  });

  /// How many frames each stop was drawn before its picture was taken.
  ///
  /// Recorded because a clip rendered a frame early looks entirely plausible,
  /// and this is the number that decides whether it was.
  final int framesPerStop;

  final File file;
  final List<double> stops;
  final int durationMs;
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
        // Nothing watches this guest, so nothing is served by pacing it to a
        // display — see `--free-vsync` in `native/host.c`. Measured at 4.4x
        // on a render.
        '--free-vsync',
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

  /// **The insets are scaled and the size is not, and that asymmetry is the
  /// message's.** `ResizeMessage` is physical throughout —
  /// `physical_view_inset_*` is what the engine reads — and
  /// `CaptureViewport` carries a physical size beside *logical* insets,
  /// because those are the space `EdgeInsets` and `MediaQuery.padding` are
  /// written in everywhere else.
  ///
  /// Unscaled, a phone's safe areas came out divided by its pixel ratio: an
  /// iPhone 16 was staged with a 19.67pt cutout instead of 59, and an iPhone
  /// SE with 10 instead of 20. Nothing failed and every picture looked
  /// plausible — an `AppBar` merely sat too high, under the notch a phone
  /// frame exists to catch. The panel had it right all along
  /// (`catalog_view.dart`'s `insets: safeAreas * dpr`); this path did not, and
  /// `lane_parity_test.dart` is what noticed.
  void _resize(CaptureViewport viewport) => _connection.add(
    encodeMessage(
      ResizeMessage(
        width: viewport.width,
        height: viewport.height,
        pixelRatio: viewport.pixelRatio,
        insetTop: viewport.insetTop * viewport.pixelRatio,
        insetRight: viewport.insetRight * viewport.pixelRatio,
        insetBottom: viewport.insetBottom * viewport.pixelRatio,
        insetLeft: viewport.insetLeft * viewport.pixelRatio,
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
    var payload = axisPayloadFor(declared, values);
    if (payload == null) return declared;
    return await _inspect.setAxes(jsonEncode(payload)) ?? declared;
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
  /// Tells the guest which device it *is*, where the resize told it how big.
  Future<void> stageAs(DevicePlatform? platform) async {
    await _renderScratchFrame();
    await _inspect.setStaging(platform);
  }

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

  Future<MotionSeek> seekMotion(double t, {String? scope}) async {
    // Only the first one pays for it. Once the scope has mounted the extension
    // stays registered, and a filmstrip that rendered a throwaway frame before
    // every seek would double the cost of the thing it exists to make cheap.
    if (!_motionReady) {
      await _renderScratchFrame();
      _motionReady = true;
    }
    // A caller that already knows which scope it is walking does not need the
    // listing, and a render asks 1800 times for a minute of video. The listing
    // is what *chooses* a scope and what makes a refusal name the others, so
    // it is skipped only when the id was given — and a seek that then fails
    // falls back to it, so the refusal is as good as it ever was.
    if (scope != null) {
      var direct = await _seek(scope, t);
      if (direct != null) {
        return MotionSeek(
          ms: (direct['ms'] as num?)?.toInt() ?? 0,
          durationMs: _durationByScope[scope] ?? 0,
          scope: scope,
          mounted: _mountedByScope,
          settled: _readSettled(direct),
          settleFrames: (direct['settleFrames'] as num?)?.toInt() ?? 1,
        );
      }
    }

    // List first, and seek by id: the guest resolves a nameless seek only
    // while exactly one scope is mounted, so a composed screen would refuse —
    // and the refusal surfaced here as the misleading "no mounted
    // MotionScope".
    var watch = Stopwatch()..start();
    var listed = await _vmService.callExtension('ext.flutterware.motion.list');
    timings.motionList += watch.elapsed;
    timings.listCalls++;
    var scopes = <Map<String, Object?>>[
      for (var entry in (listed?['scopes'] as List?) ?? const [])
        if (entry is Map) entry.cast<String, Object?>(),
    ];
    if (scopes.isEmpty) {
      throw ArgumentError.value(
        t,
        't',
        'this entry has no mounted MotionScope to seek',
      );
    }

    var chosen = scope == null
        ? scopes.first
        : scopes.firstWhereOrNull((one) => one['id'] == scope);
    if (chosen == null) {
      throw ArgumentError.value(
        scope,
        'scope',
        'no scope by that name is mounted. Mounted: '
            '${scopes.map(_describeMountedScope).join('; ')}',
      );
    }

    var id = chosen['id'] as String?;
    _mountedByScope = [for (var one in scopes) one['id'] as String? ?? ''];
    for (var one in scopes) {
      if (one['id'] case String key) {
        _durationByScope[key] = (one['durationMs'] as num?)?.toInt() ?? 0;
      }
    }
    var reply = await _seek(id, t);
    if (reply == null) {
      throw ArgumentError.value(
        t,
        't',
        'this entry has no mounted MotionScope to seek',
      );
    }
    return MotionSeek(
      ms: (reply['ms'] as num?)?.toInt() ?? 0,
      durationMs: (chosen['durationMs'] as num?)?.toInt() ?? 0,
      scope: id ?? '',
      // Mount order is tree order, so the first is the outermost — the
      // composition's own timeline rather than one of the components inside
      // it. Reported rather than assumed: a caller that got the wrong one
      // should be able to see that it did, and name the other.
      mounted: _mountedByScope,
      settled: _readSettled(reply),
      settleFrames: (reply['settleFrames'] as num?)?.toInt() ?? 1,
    );
  }

  /// What the last listing said, so the fast path can answer without one.
  var _mountedByScope = <String>[];
  final _durationByScope = <String, int>{};

  Future<Map<String, Object?>?> _seek(String? scope, double t) async {
    var watch = Stopwatch()..start();
    var reply = await _vmService.callExtension(
      'ext.flutterware.motion.seek',
      args: {'scope': ?scope, 't': '$t'},
    );
    timings.motionSeek += watch.elapsed;
    timings.seekCalls++;
    return reply;
  }

  static bool? _readSettled(Map<String, Object?> reply) =>
      switch ((reply['pending'], reply['transient'])) {
        (num pending, num transient) => pending == 0 && transient == 0,
        _ => null,
      };

  /// One mounted scope, for a refusal that teaches which to name.
  static String _describeMountedScope(Map<String, Object?> scope) {
    var targets = [
      for (var target in (scope['targets'] as List?) ?? const [])
        if (target is Map && target['name'] is String) target['name'] as String,
    ];
    return '${scope['id']} (${scope['durationMs']}ms'
        '${targets.isEmpty ? '' : ', ${targets.join('/')}'})';
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
    await _inspect.setKnobs(
      jsonEncode(knobPayloadFor(declared, values, entryId: entryId)),
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
  Future<(img.Image, ({bool settled, bool seesAnimations}))>
  captureImage() async {
    var watch = Stopwatch()..start();
    var settled = await _settle();
    timings.settle += watch.elapsed;
    watch.reset();
    var image = await _capture.capture();
    timings.frame += watch.elapsed;
    timings.frames++;
    return (image, settled);
  }

  /// Asks the guest to write its next frame, waits for the ack, and files it.
  ///
  /// The framing and the encoding are `catalog_picture.dart`'s: what is this
  /// session's is getting a frame out of a guest, and what a `--node` means
  /// against a tree is the same question whichever engine drew it.
  Future<File> capture(
    String output, {
    PictureFraming framing = const PictureFraming(),

    /// Logical-to-physical, for turning a layout rect into pixels.
    double pixelRatio = 1,
  }) async {
    await _settle();
    return writePicture(
      await _capture.capture(),
      output,
      framing: framing,
      pixelRatio: pixelRatio,
    );
  }

  final _floor = SettleFloor();

  /// Where a render's per-frame time went, accumulated across the session.
  final timings = GuestTimings();

  /// [timings], with the capture's own three-way split folded in.
  ///
  /// Read at the end rather than accumulated as it goes: `FrameCapture` counts
  /// for the whole session and this is the one place that knows a render is
  /// over.
  /// Walks the whole playhead in one call, yielding frames as they land.
  ///
  /// **This is the batched render**, and what it removes is the conversation.
  /// Driving a video with `seekMotion` + `captureRawFrame` costs two
  /// cross-process round trips a frame — one over the VM service to move the
  /// playhead, one over the socket to ask for the picture — and measured at
  /// phone resolution those were 18 of the 22ms a frame cost, against 4ms of
  /// drawing. Here the capture is armed once, the loop runs inside the guest
  /// beside the playhead, and nothing is asked per frame.
  ///
  /// It yields rather than returns because the two halves then overlap: this
  /// side reads and encodes frame 3 while the guest is still drawing frame 40,
  /// where before each waited for the other.
  ///
  /// Frames pair with [stops] by **position**, which holds exactly as long as
  /// nothing but the render loop schedules a frame. That is why this settles
  /// first — a pending image load or a running transient would present frames
  /// nobody asked for and shift every file after them.
  Stream<RawFrame> renderSequence({
    required String scope,
    required List<double> stops,

    /// How many frames the guest draws for each one kept — the last of each
    /// group. One unless the screen applies its playhead late, which
    /// [MotionSeek.settleFrames] is how to find out.
    int framesPerStop = 1,
  }) async* {
    // **Nothing may be in flight when the sequence is armed.** The host writes
    // frames as they present, and pairing them with stops is positional — so a
    // single frame left over from whatever ran before shifts every picture in
    // the clip by one, and each of them still looks perfectly good. That is
    // how the first batched filmstrip came out: a probe seek left a spring
    // running, its last frame was written as stop zero, and the strip was a
    // faithful render of the wrong six moments.
    //
    // Seeking to the first stop is what quiets it, because a seek now draws
    // until the screen stops drawing. The settle after it is for image loads,
    // which are the other thing that presents a frame nobody asked for.
    await _seek(scope, stops.first);
    await _settle();
    var prefix = p.join(_capture.workDir, 'seq-');
    var frames = await _capture.captureSequence(
      prefix: prefix,
      count: stops.length,
      stride: framesPerStop,
    );
    // Unawaited on purpose: it answers when the *last* frame has been drawn,
    // and the whole point is to be reading the first one long before then.
    //
    // A render that dies owes frames that are never coming, so its failure is
    // pushed into the outstanding captures rather than only remembered —
    // otherwise the loop below waits out a timeout for a file no one is
    // writing, and reports that instead of the real error.
    Object? failure;
    var guestClock = Stopwatch()..start();
    var done = _vmService
        .callExtension(
          'ext.flutterware.motion.render',
          args: {
            'scope': scope,
            'stops': stops.join(','),
            'framesPerStop': '$framesPerStop',
          },
        )
        .then<void>(
          (reply) {
            // Loud rather than subtle: a stop still drawing when its picture
            // was taken is a frame of the wrong moment, and the picture looks
            // entirely plausible.
            if ((reply?['unsettled'] as num? ?? 0) > 0) {
              failure = StateError(
                '${reply?['unsettled']} of ${stops.length} stops were still '
                'drawing when their frame was taken, at $framesPerStop frames '
                'a stop — the clip would be of the wrong moments',
              );
            }
          },
          onError: (Object error) {
            failure = error;
            _capture.endSequence(prefix, because: error);
          },
        )
        .whenComplete(() => timings.guestRender = guestClock.elapsed);

    try {
      var waiting = Stopwatch();
      for (var frame in frames) {
        waiting.start();
        var landed = await frame;
        waiting.stop();
        yield landed;
        timings.frames++;
      }
      timings.awaitingFrames = waiting.elapsed;
    } finally {
      _capture.endSequence(prefix);
      await done;
    }
    if (failure != null) throw StateError('the render failed: $failure');
  }

  /// [captureImage] with the pixels left as the guest wrote them.

  ///
  /// [alreadySettled] skips the settle loop, and is only ever true because a
  /// *seek* just reported the frame it drew was quiet. The loop it skips is
  /// two forced frames — the capture forces its own anyway — so on a parked
  /// motion this is the difference between four rendered frames per captured
  /// one and two.
  Future<RawFrame> captureRawFrame({bool alreadySettled = false}) async {
    var watch = Stopwatch()..start();
    if (!alreadySettled) await _settle();
    timings.settle += watch.elapsed;
    watch.reset();
    var frame = await _capture.captureRaw();
    timings.frame += watch.elapsed;
    timings.frames++;
    return frame;
  }

  GuestTimings readCaptureCosts() => timings
    ..captureDraw = _capture.drawTime
    ..captureRead = _capture.readTime
    ..captureDecode = _capture.decodeTime
    ..captureBytes = _capture.readBytes;

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
