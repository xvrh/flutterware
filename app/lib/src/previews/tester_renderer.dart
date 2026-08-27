// The report types, not the umbrella `ui_catalog.dart`: that one exports the
// demo annotations, which reach `package:flutter/widgets.dart`.
// ignore: implementation_imports
import 'package:flutterware/src/inspect/error.dart';
// ignore: implementation_imports
import 'package:flutterware/src/inspect/node.dart';
// ignore: implementation_imports
import 'package:flutterware/src/devices.dart';
// ignore: implementation_imports
import 'package:flutterware/src/ui_catalog/axis.dart';
// ignore: implementation_imports
import 'package:flutterware/src/ui_catalog/knob.dart';

import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import 'catalog_picture.dart';
import 'catalog_render.dart';
import 'catalog_values.dart';
import 'test_runner.dart';

/// The `flutter_tester` backend of [CatalogRenderer].
///
/// One warm harness for a whole package against one embedder guest per call:
/// measured 2026-08-27 on this repo's catalog, a guest render is ~12.7s of
/// daemon-connect, whole-kernel compile, spawn and teardown, and a warm
/// harness answers in tens of milliseconds. It is also reproducible — the same
/// entry renders byte-identically under FakeAsync — which is what the audit,
/// the comparison and the thumbnails all moved here for.
///
/// **What it cannot answer is refused, never approximated.** The logs are the
/// one thing left: a demo's `print` inside a widget test rides the runner's
/// own message stream rather than the zone `GuestLogs` wraps, so there is
/// nothing here to collect — and it is refused by name rather than answered
/// empty, because a caller told "no logs" when it means "not on this engine"
/// goes looking in the demo.
class TesterRenderer extends CatalogRenderer {
  TesterRenderer({required this.runner, this.sync = true});

  final PreviewTestRunner runner;

  /// Bring the harness up to date with what is on disk first — a sweep of
  /// every source and the asset bundle, ~1.5–1.9s even when nothing moved.
  ///
  /// Right for a caller answering a question about the code as it is now,
  /// which is every caller here; the hover thumbnails are the ones that turn
  /// it off, because they have their own idea of when a picture went stale.
  final bool sync;

  @override
  Future<CatalogObservation> render(CatalogRender request) async {
    // **Two calls, and the first one is what makes the refusals right.** Which
    // kind a knob is, and which label an axis option answers to, are facts
    // about the build that declared them — so the values are resolved against
    // a real declaration rather than guessed at from the characters, and a
    // name nobody declared is refused in the same words the guest refuses it
    // in. The extra call is a pump of one entry against a warm harness: tens
    // of milliseconds, against a wrong picture that looks right.
    var wantsValues = request.knobs.isNotEmpty || request.axes.isNotEmpty;
    var declared = wantsValues
        ? await _ask(request, wantKnobs: true, wantAxes: true)
        : null;

    var reply = await _ask(
      request,
      knobs: declared == null
          ? null
          : knobPayloadFor(
              declared.knobs,
              request.knobs,
              entryId: request.entryId,
            ),
      axes: declared == null
          ? null
          : axisPayloadFor(declared.axes, request.axes),
      wantKnobs: request.wantKnobs,
      wantAxes: request.wantAxes,
      // Only the second call syncs; the first has just done it.
      sync: declared == null && sync,
    );

    return CatalogObservation(
      errors: reply.errors,
      knobs: request.wantKnobs ? reply.knobs : null,
      axes: request.wantAxes ? reply.axes : null,
      stagedOn: reply.stagedOn,
      tree: request.wantTree ? reply.tree : null,
      hits: reply.hits,
      screenshot: switch ((request.screenshot, reply.frame)) {
        (var output?, var frame?) => _file(request, output, frame, reply.tree),
        _ => null,
      },
    );
  }

  /// The frame the harness drew, framed and written where the caller asked.
  ///
  /// **The framing is host-side and shared**, which is the whole of §5.4: the
  /// same `PictureFraming` resolves `--node` against the same kind of tree,
  /// and the same `writePicture` encodes it, whichever engine drew the pixels.
  /// What differs is one decode — packed rgba here against the embedder's BGRA
  /// behind a header.
  File _file(
    CatalogRender request,
    String output,
    _Frame frame,
    InspectTree? tree,
  ) {
    var bytes = File(frame.path).readAsBytesSync();
    var image = frame.format == 'png'
        ? img.decodePng(bytes)!
        : decodeTesterFrame(bytes, width: frame.width, height: frame.height);
    try {
      return writePicture(
        image,
        output,
        framing: request.framed
            ? PictureFraming.of(
                // `framed` is what put us here and the request's `needsTree`
                // covers it, so the tree was asked for and is in hand.
                tree!,
                node: request.cropNode,
                annotate: request.annotate,
                entryId: request.entryId,
              )
            : const PictureFraming(),
        pixelRatio: request.viewport.pixelRatio,
      );
    } finally {
      // The frame was scaffolding: raw at a phone's ratio is megabytes, and
      // the artifact is the PNG.
      var directory = Directory(p.dirname(frame.path));
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    }
  }

  Future<_Reply> _ask(
    CatalogRender request, {
    Map<String, Object?>? knobs,
    Map<String, Map<String, Object?>>? axes,
    bool wantKnobs = false,
    bool wantAxes = false,
    bool? sync,
  }) async {
    var reply = await runner.render(
      entryId: request.entryId,
      sync: sync ?? this.sync,
      request: {
        'entry': request.entryId,
        // The whole screen as numbers, which is what the guest is sent over
        // its resize message too — so the two backends are staged from one
        // answer rather than each deriving its own from a device id.
        'viewport': request.viewport.staged.toJson(),
        // The staged screen's own ratio, so a picture from this lane comes out
        // the size the guest's would.
        if (request.viewport.pixelRatio != 1)
          'pixelRatio': request.viewport.pixelRatio,
        'knobs': ?knobs,
        'axes': ?axes,
        if (wantKnobs) 'wantKnobs': true,
        if (wantAxes) 'wantAxes': true,
        // A directory for the frame, not the final path: what the harness
        // draws is scaffolding, and the artifact is what `writePicture` makes
        // of it. PNG rather than raw, because a phone-sized frame is
        // megabytes of rgba to move across a disk for one picture — the
        // comparison keeps raw precisely because it diffs pixels and would
        // decode straight back out.
        if (request.screenshot != null) ...{
          'output': p.join(_scratch, 'frame'),
          'format': 'png',
        },
        if (request.needsTree) 'tree': true,
        if (request.at != null) 'at': '${request.at!.$1},${request.at!.$2}',
        // Named rather than omitted, so the harness refuses it by name — a
        // request that came back looking answered and was not is the failure
        // this lane has to be safe from.
        if (request.wantLogs) 'logs': true,
      },
    );
    return _Reply(
      errors: InspectErrors.fromJson(reply),
      stagedOn: switch (reply['viewport']) {
        Map json => StagedViewport.fromJson(json.cast<String, Object?>()),
        _ => null,
      },
      knobs: switch (reply['knobs']) {
        Map json => KnobReport.fromJson(json.cast<String, Object?>()),
        _ => KnobReport.empty,
      },
      axes: switch (reply['axes']) {
        Map json => AxisReport.fromJson(json.cast<String, Object?>()),
        _ => AxisReport.empty,
      },
      tree: switch (reply['tree']) {
        Map json => InspectTree.fromJson(json.cast<String, Object?>()),
        _ => null,
      },
      hits: switch (reply['hits']) {
        List ids => [for (var id in ids) '$id'],
        _ => null,
      },
      frame: switch (reply['image']) {
        String path => _Frame(
          path: path,
          format: reply['format'] as String? ?? 'raw',
          width: reply['width'] as int? ?? 0,
          height: reply['height'] as int? ?? 0,
        ),
        _ => null,
      },
    );
  }

  /// Where a frame lands on its way to being a picture. Under the runner's own
  /// build directory rather than the system temp, so a crash leaves it where
  /// the rest of the lane's scaffolding is swept from.
  String get _scratch => p.join(runner.packageRoot, runner.buildDirectory);
}

class _Frame {
  const _Frame({
    required this.path,
    required this.format,
    required this.width,
    required this.height,
  });

  final String path;
  final String format;
  final int width;
  final int height;
}

class _Reply {
  const _Reply({
    required this.errors,
    required this.knobs,
    required this.axes,
    this.stagedOn,
    this.tree,
    this.hits,
    this.frame,
  });

  final StagedViewport? stagedOn;
  final InspectErrors errors;
  final KnobReport knobs;
  final AxisReport axes;
  final InspectTree? tree;
  final List<String>? hits;
  final _Frame? frame;
}
