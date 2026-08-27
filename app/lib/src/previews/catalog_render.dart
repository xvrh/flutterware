import 'dart:io';

// The knob types, not the umbrella `ui_catalog.dart`: that one exports the
// demo annotations, which reach `package:flutter/widgets.dart` and would make
// `fw` unlinkable.
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

import 'devices.dart';

/// Everything asked about **one** rendered build.
///
/// **What to render and what to read are one request on purpose.** `tree`,
/// `find`, `at`, `errors` and `logs` are not five capabilities — they are five
/// projections of one observation, with the same inputs and the same
/// precondition, and each used to pay a full compile-launch-render to answer
/// one question about a frame the others also had to produce. Three questions
/// was three renders, which for an agent in an edit loop is the dominant
/// per-iteration cost.
///
/// It also removes an assumption rather than only a cost. `screenshot
/// --annotate` read its own tree, so a caller that ran `tree` and then
/// `screenshot --annotate` got two trees from two processes; the ids on the
/// picture matched the ids in the tree because the build is deterministic, not
/// because they were the same object. Closing that loop was the entire point
/// of `--annotate`. One render, one tree, both projections off it.
///
/// A request is validated by whoever builds it, before anything is scanned or
/// compiled: a typo in a flag should cost nothing, and a compile-and-render is
/// the most expensive thing in the plugin.
class CatalogRender {
  const CatalogRender({
    required this.entryId,
    this.viewport = CaptureViewport.panel,
    this.knobs = const {},
    this.axes = const {},
    this.debug = const {},
    this.wantTree = false,
    this.wantLogs = false,
    this.wantKnobs = false,
    this.wantAxes = false,
    this.at,
    this.screenshot,
    this.annotate = false,
    this.cropNode,
    this.motionT,
  });

  final String entryId;

  /// The screen to stage: its size, its pixel ratio, its safe areas, its
  /// keyboard.
  final CaptureViewport viewport;

  /// Values the *preview* asked for while it built, as raw strings — a flag
  /// and a JSON object both arrive as text, and only the entry knows what kind
  /// each one is.
  final Map<String, String> knobs;

  /// Values for the shell *around* the preview — theme, locale, flavour.
  final Map<String, String> axes;

  /// The framework's own switches: `paint`, `brightness`, `timeDilation`.
  /// Neither the preview's nor the shell's, and a fixed set either way.
  final Map<String, String> debug;

  final bool wantTree;
  final bool wantLogs;
  final bool wantKnobs;
  final bool wantAxes;

  /// A point to hit-test, in logical pixels.
  final (double, double)? at;

  /// Where to write the picture. Null takes none.
  final String? screenshot;

  /// Draw a box and its node id over every widget.
  final bool annotate;

  /// Cut the picture down to one widget, by name or by tree id.
  final String? cropNode;

  /// Where to park the entry's motion, 0..1.
  final double? motionT;

  /// Whether the tree has to be read, which is more often than the caller
  /// asked for it: a hit resolves ids against a tree, a crop needs a node's
  /// rect, and an annotation needs every node's.
  ///
  /// Worked out here rather than by each backend, because a backend that
  /// disagreed about this would answer a question nobody could see it had been
  /// asked.
  bool get needsTree => wantTree || at != null || framed;

  /// Whether the picture has to be cut or drawn on after it is taken — which
  /// is what decides whether the shutter can *be* the settling frame.
  bool get framed => annotate || (cropNode?.isNotEmpty ?? false);

  /// Every field, so a field added and forgotten here is a compile error
  /// rather than a value that silently stops travelling.
  CatalogRender copyWith({
    String? entryId,
    CaptureViewport? viewport,
    Map<String, String>? knobs,
    Map<String, String>? axes,
    Map<String, String>? debug,
    bool? wantTree,
    bool? wantLogs,
    bool? wantKnobs,
    bool? wantAxes,
    (double, double)? at,
    String? screenshot,
    bool? annotate,
    String? cropNode,
    double? motionT,
  }) => CatalogRender(
    entryId: entryId ?? this.entryId,
    viewport: viewport ?? this.viewport,
    knobs: knobs ?? this.knobs,
    axes: axes ?? this.axes,
    debug: debug ?? this.debug,
    wantTree: wantTree ?? this.wantTree,
    wantLogs: wantLogs ?? this.wantLogs,
    wantKnobs: wantKnobs ?? this.wantKnobs,
    wantAxes: wantAxes ?? this.wantAxes,
    at: at ?? this.at,
    screenshot: screenshot ?? this.screenshot,
    annotate: annotate ?? this.annotate,
    cropNode: cropNode ?? this.cropNode,
    motionT: motionT ?? this.motionT,
  );
}

/// Something that can render one entry and answer questions about that frame.
///
/// The interface exists so the answer's shape is fixed while the engine behind
/// it is not: the embedder guest renders what a person is watching, and a
/// `flutter_tester` harness renders everything nobody is. Both answer a
/// [CatalogObservation], so the plugin's projections — `screen`, `find`, `at`,
/// `styles` — read the same thing either way.
abstract class CatalogRenderer {
  const CatalogRenderer();

  Future<CatalogObservation> render(CatalogRender request);

  /// A picture, and the knobs the build that produced it declared.
  ///
  /// Concrete rather than abstract, and here rather than in a backend: a
  /// capture is a projection of a render, so a second implementation of it is
  /// a second chance to disagree about what a picture of an entry *is*.
  Future<CatalogCapture> capture(CatalogRender request) async {
    if (request.screenshot == null) {
      throw ArgumentError.value(
        request.screenshot,
        'screenshot',
        'a capture needs somewhere to write the picture',
      );
    }
    // The declared knobs always, whatever the request said: a caller comparing
    // them with what it asked for is the only way to notice a demo clamping
    // one, and `screenshot` reports them for exactly that reason.
    var observed = await render(request.copyWith(wantKnobs: true));
    return CatalogCapture(
      // The render was asked for a screenshot, so it took one or threw.
      file: observed.screenshot!,
      knobs: observed.knobs?.knobs ?? const [],
    );
  }
}

/// One rendered build, and everything the call asked about it.
///
/// Nullable per section rather than empty-per-section, and the distinction is
/// load-bearing: null means *not asked for*, empty means *asked and there is
/// nothing*. A demo that printed nothing and a demo whose logs were not
/// requested are different answers, and a caller that could not tell them apart
/// would read the second as the first.
///
/// The same shape whether the reading came from a fresh guest, from the session
/// a person has open, or from a harness under `flutter_tester`, so the paths
/// cannot drift in what they can report.
class CatalogObservation {
  const CatalogObservation({
    required this.errors,
    this.tree,
    this.logs,
    this.knobs,
    this.axes,
    this.hits,
    this.screenshot,
    this.stagedOn,
  });

  /// Always read, whatever was asked for. It is the answer to "is this one
  /// broken", which is the question behind asking anything at all — and it
  /// costs a round trip against a guest that is already running.
  final InspectErrors errors;

  final InspectTree? tree;
  final InspectLogs? logs;

  /// The knobs the captured build declared, when they were asked for.
  ///
  /// Here rather than only on [CatalogRenderer.capture] because a picture and a
  /// list of the controls that produced it are two projections of one frame,
  /// like everything else here.
  final KnobReport? knobs;

  /// What the shell around the entry declared, when it was asked for — and
  /// which shell that was, which is the thing an entry with no shell answers
  /// `null` to.
  final AxisReport? axes;

  /// The node ids under the probed point, outermost first. Empty is an answer:
  /// there is nothing of the demo's there.
  final List<String>? hits;

  final File? screenshot;

  /// The screen it actually rendered on, as the backend read it back off its
  /// own binding — not what the request asked for.
  ///
  /// The one check on staging there is. Every other answer here looks exactly
  /// the same on the wrong surface as on the right one: the knobs a demo
  /// declares, the errors it reported, even a picture, which is only wrong in
  /// a way somebody has to already suspect. Null from a backend that does not
  /// report it.
  final StagedViewport? stagedOn;
}

/// One picture, and what the build that produced it declared.
class CatalogCapture {
  CatalogCapture({required this.file, required this.knobs});

  final File file;

  /// What the entry reported *after* the values were applied — so a clamped or
  /// ignored value is visible rather than assumed.
  final List<KnobDescriptor> knobs;
}
