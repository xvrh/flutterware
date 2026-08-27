/// The second pass: an app's captures, composed onto the canvas a store takes.
///
/// A program in its own right, run in a `flutter_tester` the tool spawned, with
/// the project's own frame compiled into it. It renders nothing of the app —
/// pass one already did that — so what happens here is a `pumpWidget` over a
/// decoded PNG and a capture of the result.
///
/// Kept apart from the capture pass on purpose, and the reason is a loop rather
/// than a layer: **changing a headline or a background must not re-run the
/// app.** The captures are on disk, this reads them, and a recompose is
/// seconds where a re-run is a minute. See the design's §3.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_api/backend.dart' show Runtime, SuitePlatform;
// ignore: implementation_imports
import 'package:test_api/src/backend/declarer.dart';
// ignore: implementation_imports
import 'package:test_api/src/backend/suite.dart';
// ignore: implementation_imports
import 'package:test_api/src/backend/test.dart' as backend;

import '../devices.dart';
import '../plugins/store.dart';
import '../scenarios/fonts.dart';
import '../scenarios/run_args.dart';
import '../scenarios/staging.dart';
import 'frame.dart';

/// Serves compose requests until the host stops asking.
///
/// The generated entrypoint calls this with the project's frame — one function,
/// because a frame is handed [StoreShot.canvas] and [StoreShot.device] and a
/// widget branching on its input is what a widget is.
void runStoreFrameHarness(StoreFrame Function(StoreShot shot) build) {
  // Guarded for the reason the other two harnesses are: an async error leaking
  // after a compose completes reaches `tester_main.cc`'s unhandled handler,
  // which kills the process — and a shared harness dying because one frame
  // threw is the one outcome this may never have.
  unawaited(
    runZonedGuarded(() => _serve(build), (error, stack) {
      stderr.writeln('[store] uncaught: $error\n$stack');
    }),
  );
}

Future<void> _serve(StoreFrame Function(StoreShot shot) build) async {
  // The binding first: loading a font goes through the messenger `rootBundle`
  // reaches for, and that is the binding's.
  TestWidgetsFlutterBinding.ensureInitialized();
  var fonts = await loadScenarioFonts();

  developer.registerExtension('ext.flutterware.store.compose', (_, args) async {
    try {
      return developer.ServiceExtensionResponse.result(
        jsonEncode(await _compose(build, manifest: args['manifest']!)),
      );
    } catch (error, stack) {
      return developer.ServiceExtensionResponse.result(
        jsonEncode({'error': '$error', 'stack': '$stack'}),
      );
    }
  });

  // The engine keeps the process alive; the timer keeps the isolate from ever
  // reading as idle between host calls.
  Timer.periodic(const Duration(days: 1), (_) {});
  print('flutterware store frames harness ready — fonts: ${fonts.join(', ')}');
}

/// One compose job, as the host writes it into the manifest.
///
/// A file rather than flat arguments because a set is tens of jobs each
/// carrying nine fields, and a service-extension call takes a map of strings.
class _Job {
  _Job(Map<String, Object?> json)
    : image = json['image']! as String,
      set = [for (var it in json['set'] as List? ?? const []) '$it'],
      out = json['out']! as String,
      slug = json['slug']! as String,
      index = json['index']! as int,
      total = json['total']! as int,
      locale = json['locale'] as String? ?? 'en',
      device = json['device']! as String,
      canvasWidth = json['canvasWidth']! as int,
      canvasHeight = json['canvasHeight']! as int,
      canvasRatio = (json['canvasRatio']! as num).toDouble();

  final String image;

  /// Every image of the set, in order — see [StoreShot.set].
  final List<String> set;

  final String out;
  final String slug;
  final int index;
  final int total;
  final String locale;
  final String device;
  final int canvasWidth;
  final int canvasHeight;
  final double canvasRatio;
}

Future<Map<String, Object?>> _compose(
  StoreFrame Function(StoreShot shot) build, {
  required String manifest,
}) async {
  var jobs = [
    for (var entry in (jsonDecode(
      File(manifest).readAsStringSync(),
    ) as List).cast<Map<String, Object?>>())
      _Job(entry),
  ];

  var written = <String>[];
  var failures = <String, String>{};

  // Declared and run the way the previews harness runs its audit: a `tester` is
  // the only thing that can pump and capture, and a `Declarer` of our own is
  // how a program with no test runner gets one.
  var declarer = Declarer();
  declarer.declare(() {
    for (var job in jobs) {
      testWidgets(job.slug, (tester) async {
        var device = deviceById(job.device);
        if (device == null) {
          throw StateError(
            'no device "${job.device}" — the host resolved it, so this is a '
            'version disagreement between the harness and the tool.',
          );
        }
        var canvas = StoreCanvas(
          width: job.canvasWidth,
          height: job.canvasHeight,
          pixelRatio: job.canvasRatio,
        );
        // The canvas is the whole viewport, at its own ratio, so what
        // `toImage` produces below is already the store's exact pixel size
        // and nothing is resampled afterwards.
        var reset = applyScenarioRunArgs(
          tester,
          ScenarioRunArgs(
            size: Size(canvas.logicalWidth, canvas.logicalHeight),
            pixelRatio: canvas.pixelRatio,
          ),
        );
        try {
          // Read once and shared, so a frame that paints its own shot and a
          // neighbour does not read the same file twice.
          var loaded = <String, MemoryImage>{};
          MemoryImage load(String path) => loaded.putIfAbsent(
            path,
            () => MemoryImage(File(path).readAsBytesSync()),
          );
          var shot = StoreShot(
            image: load(job.image),
            set: [for (var path in job.set) load(path)],
            imageSize: Size(device.width, device.height),
            slug: job.slug,
            index: job.index,
            total: job.total,
            locale: _localeOf(job.locale),
            device: device,
            canvas: canvas,
          );
          await tester.pumpWidget(
            StoreFrameStage(shot: shot, child: build(shot)),
          );
          // A `MemoryImage` decodes off the real event loop, which fake time
          // never runs — so without this turn the frame is captured with the
          // app's own pixels still missing from it, and the picture is a
          // composition around a hole.
          //
          // **Every `Image` the frame placed**, not just the shot's own. It
          // was `precacheImage(shot.image, …find.byType(Image))` — singular,
          // and correct only while a frame could paint exactly one picture. A
          // panorama paints its neighbours, and each of those would have been
          // that hole. Asked of the tree rather than of the job, so what gets
          // decoded is what was actually placed: a frame that ignores
          // [StoreShot.set] pays nothing.
          await tester.runAsync(() async {
            for (var element in find.byType(Image).evaluate()) {
              await precacheImage((element.widget as Image).image, element);
            }
          });
          await tester.pump();
          await _capture(tester, job.out);
          written.add(job.out);
        } finally {
          reset();
        }
      });
    }
  });

  var suite = Suite(declarer.build(), SuitePlatform(Runtime.vm));
  for (var (index, test) in suite.group.entries.cast<backend.Test>().indexed) {
    var live = test.load(suite);
    var priorReporter = reportTestException;
    reportTestException = (details, _) =>
        failures[jobs[index].slug] ??= details.exceptionAsString();
    try {
      await live.run();
    } finally {
      reportTestException = priorReporter;
    }
  }

  return {'written': written, if (failures.isNotEmpty) 'failures': failures};
}

/// `fr-CA` into a `Locale`, because that is the spelling a declaration uses and
/// `Locale` wants the halves apart.
Locale _localeOf(String tag) {
  var parts = tag.split(RegExp('[-_]'));
  return parts.length > 1 ? Locale(parts.first, parts[1]) : Locale(parts.first);
}

/// The composed frame, as a PNG at the canvas's exact pixel size.
Future<void> _capture(WidgetTester tester, String out) async {
  // A real-async turn, like every other capture in this codebase: `toImage`
  // completes on the real event loop, which fake time never runs.
  await tester.runAsync(() async {
    var view = tester.binding.renderViews.single;
    var layer = view.debugLayer! as OffsetLayer;
    var dpr = view.flutterView.devicePixelRatio;
    var image = await layer.toImage(Offset.zero & (view.size * dpr));
    var data = (await image.toByteData(format: ui.ImageByteFormat.png))!;
    image.dispose();
    File(out).parent.createSync(recursive: true);
    File(out).writeAsBytesSync(data.buffer.asUint8List());
  });
}

/// Where the generated entrypoint goes, relative to the package.
const storeFrameEntrypointPath =
    'build/flutterware/store_frames/store_frames.dart';
