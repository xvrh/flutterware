import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
// The declarer, so one generated file can serve both lanes — see
// [runPreviewHarness] for how its presence is the thing that tells them apart.
// ignore: implementation_imports
import 'package:test_api/src/backend/declarer.dart';
// ignore: implementation_imports
import 'package:test_api/src/backend/runtime.dart';
// ignore: implementation_imports
import 'package:test_api/src/backend/suite.dart';
// ignore: implementation_imports
import 'package:test_api/src/backend/suite_platform.dart';
// ignore: implementation_imports
import 'package:test_api/src/backend/test.dart' as backend;

import '../canvases.dart';
import '../devices.dart';
import '../inspect/error.dart';
import '../inspect/guest_errors.dart';
import '../scenarios/asset_bundle.dart';
import '../scenarios/fonts.dart';
import '../scenarios/settle.dart';
import '../scenarios/run_args.dart';
import '../scenarios/staging.dart';
import '../ui_catalog/guest.dart';

/// One preview, as the generated harness hands it over.
///
/// [build] is a thunk rather than a widget because a preview is built *inside*
/// the test body: the annotation's `wrapper` runs there, under the canvas the
/// entry is judged on, and a widget built at table-construction time would have
/// been built under whatever the previous entry left behind.
class PreviewEntry {
  const PreviewEntry({
    required this.id,
    required this.path,
    required this.name,
    required this.build,
  });

  /// What the tool calls this entry — `demo/tile.dart#tileEmpty`.
  final String id;

  /// Package-relative and `/`-separated, which is the coordinate space
  /// [canvasFor] matches against.
  final String path;

  final String name;

  /// The entry with its `wrapper` already applied — the generator owns that,
  /// because only the generated file can name the annotation.
  final Widget Function() build;
}

/// Runs every preview in a package as a widget test, and answers what each one
/// reported.
///
/// **The same widgets, the same errors, a different engine.** Each entry is
/// mounted under [CatalogGuest] and its annotation's `wrapper`, exactly as the
/// embedder guest's entrypoint mounts it, and errors are collected into
/// [GuestErrors] — the same buffer, the same dedup key, the same counts. What
/// changes is only that the frame is drawn by a test binding under FakeAsync
/// rather than by a real engine in real time, which is what takes a
/// catalog-wide render from minutes to seconds: a demo that animates for ever
/// costs a few microseconds of fake clock instead of a three-second wait.
///
/// **Two lanes off one generated file**, told apart by whether a test runner is
/// already declaring:
///
/// - `Declarer.current == null` — nobody is. This was launched as a bare
///   program in a `flutter_tester` the tool spawned, so it declares into its
///   own [Declarer], registers `ext.flutterware.previews.audit` and waits to be
///   asked. **This is the lane whose fonts are real**: the tool omits
///   `--use-test-fonts` and `--disable-asset-fonts`, which `flutter test`
///   passes unconditionally.
/// - `Declarer.current != null` — `flutter test` is running this file as an
///   ordinary test. Each entry is declared as an ordinary `testWidgets` that
///   fails when the entry reports anything. Convenient, shardable, and
///   measuring unstyled text in the test font, so an overflow verdict from this
///   lane is worth less than one from the other.
void runPreviewHarness(
  List<PreviewEntry> entries, {
  List<PreviewCanvas> canvases = const [],
}) {
  if (Declarer.current != null) {
    // The driven lane loads fonts before it declares anything; this one has
    // nowhere earlier to do it. A scenario folder has a
    // `flutter_test_config.dart` to hang that on and a generated preview
    // harness has no folder of its own, so the declaration carries it.
    //
    // Without this the catalog is measured in the fallback font, which is wrong
    // in the one way nothing catches: it still renders, and reports the
    // difference as `RenderFlex overflowed by 3.5 pixels`.
    setUpAll(loadScenarioFonts);
    _declare(entries, canvases, collect: null);
    return;
  }
  // Guarded for the reason the scenario harness is: a failing entry can leak an
  // async error after its test completes, and unguarded that reaches
  // `tester_main.cc`'s unhandled handler, which kills the process. A shared
  // harness dying because one preview failed is the one outcome this may never
  // have.
  unawaited(
    runZonedGuarded(() => _serve(entries, canvases), (error, stack) {
      stderr.writeln('[previews] uncaught: $error\n$stack');
    }),
  );
}

/// The driven lane: declare once, then run on request.
Future<void> _serve(
  List<PreviewEntry> entries,
  List<PreviewCanvas> canvases,
) async {
  // The binding first, because everything below reaches for it — loading a font
  // needs the messenger `rootBundle` goes through, and that is the binding's.
  TestWidgetsFlutterBinding.ensureInitialized();
  var fonts = await loadScenarioFonts();

  developer.registerExtension('ext.flutterware.previews.audit', (
    _,
    args,
  ) async {
    try {
      var only = args['entries']
          ?.split(',')
          .where((id) => id.isNotEmpty)
          .toSet();
      var report = await _audit(
        entries,
        canvases,
        only: only,
        // One device for the whole catalog, which is how you ask whether all
        // of it survives a small phone. Absent — the right answer for CI —
        // leaves each entry framed as its own subtree declared.
        device: switch (args['device']) {
          null => null,
          var id => deviceById(id),
        },
        orientation: switch (args['orientation']) {
          null => null,
          var name => orientationById(name),
        },
      );
      return developer.ServiceExtensionResponse.result(jsonEncode(report));
    } catch (error, stack) {
      return developer.ServiceExtensionResponse.result(
        jsonEncode({'error': '$error', 'stack': '$stack'}),
      );
    }
  });

  // The line the host waits for. Fonts named because a catalog rendered in the
  // fallback font is wrong in the one way nothing catches, and "which fonts"
  // is the first question when an overflow row looks implausible.
  print(
    'flutterware previews harness ready — '
    '${entries.length} entries, fonts: ${fonts.join(', ')}',
  );
}

/// Runs [entries] and reports what each one said.
Future<Map<String, Object?>> _audit(
  List<PreviewEntry> entries,
  List<PreviewCanvas> canvases, {
  Set<String>? only,
  Device? device,
  ScreenOrientation? orientation,
}) async {
  var wanted = [
    for (var entry in entries)
      if (only == null || only.contains(entry.id)) entry,
  ];
  var collected = <String, InspectErrors>{};
  var declarer = Declarer();
  declarer.declare(
    () => _declare(
      wanted,
      canvases,
      collect: collected,
      device: device,
      orientation: orientation,
    ),
  );
  // Flat by construction — one `testWidgets` per entry, no groups — so the
  // group walk the scenario harness needs has nothing to walk here.
  var suite = Suite(declarer.build(), SuitePlatform(Runtime.vm));

  var failures = <String, String>{};
  var watch = Stopwatch()..start();
  for (var (index, test) in suite.group.entries.cast<backend.Test>().indexed) {
    var entry = wanted[index];
    var live = test.load(suite);
    // The binding's failure path bypasses the LiveTest: it dumps to console and
    // throws from the binding's own zone, so the failure would surface as an
    // uncaught zone error rather than an outcome. The same hook `flutter test`'s
    // own bootstrap uses.
    var priorReporter = reportTestException;
    reportTestException = (details, _) =>
        failures[entry.id] ??= details.exceptionAsString();
    try {
      await live.run();
    } finally {
      reportTestException = priorReporter;
    }
    for (var error in live.errors) {
      failures[entry.id] ??= '${error.error}';
    }
  }

  return {
    'ms': watch.elapsedMilliseconds,
    'entries': {
      for (var entry in wanted)
        entry.id: {
          ...?collected[entry.id]?.toJson(),
          // Something went wrong that is not a framework error the build
          // reported — the builder threw outright, a test timed out. Reported
          // separately because it is a different kind of broken: the entry did
          // not render at all rather than rendering badly.
          'failure': ?failures[entry.id],
        },
    },
  };
}

/// Declares one `testWidgets` per entry into whichever declarer is current.
///
/// [collect] is where each entry's report lands in the driven lane. Null in the
/// `flutter test` lane, where nobody is going to read it and the test's own
/// pass or fail is the whole answer.
void _declare(
  List<PreviewEntry> entries,
  List<PreviewCanvas> canvases, {
  required Map<String, InspectErrors>? collect,
  Device? device,
  ScreenOrientation? orientation,
}) {
  for (var entry in entries) {
    testWidgets(entry.id, (tester) async {
      // Not `install()`: the binding owns `FlutterError.onError` for the length
      // of a test, and that ownership is what makes a reported error fail it.
      // Chaining collects everything — including the first, which the binding
      // stashes rather than reports — and hands it on unchanged.
      var previous = FlutterError.onError;
      FlutterError.onError = (details) {
        GuestErrors.instance.report(details);
        previous?.call(details);
      };
      // `CatalogGuest` resets on a *change* of entry, so re-running the same one
      // would otherwise still be holding the last run's errors.
      GuestErrors.instance.clear();
      // A device named for the whole run wins over every canvas; absent, each
      // entry is framed as its own subtree declared. `canvasFor` rather than a
      // prefix match written out again here, because a rule applied twice is a
      // rule that eventually differs.
      var canvas = canvasFor(canvases, entry.path);
      var reset = switch ((device, canvas?.defaultDevice)) {
        (var named?, _) => tester.applyDevice(named, orientation: orientation),
        (_, _?) => tester.applyCanvas(canvas),
        // Neither: the plain rectangle, staged rather than left alone. The
        // default test surface is 800×600 and the guest's is 900×700, and an
        // entry judged on the narrower one overflows where the guest says it
        // does not.
        _ => applyScenarioRunArgs(
          tester,
          ScenarioRunArgs(
            size: Size(
              previewPanelWidth.toDouble(),
              previewPanelHeight.toDouble(),
            ),
            pixelRatio: 1,
          ),
        ),
      };
      try {
        // The harness read the app's fonts through `rootBundle` at startup, and
        // that cached a future belonging to a zone this test is not in.
        rootBundle.clear();
        await tester.pumpWidget(
          // Caches values where `rootBundle` caches futures, which is what makes
          // an asset the app has already read safe to read again from inside
          // `runAsync`. An app installing its own still wins — it is nearer.
          DefaultAssetBundle(
            bundle: ScenarioAssetBundle(),
            // The same two wrappers the embedder guest's entrypoint mounts, in
            // the same order, so what differs between the backends is the
            // engine and not the tree. `CatalogGuest` is what makes knobs
            // answer and what resets the axes, errors and logs per entry.
            child: CatalogGuest(entryId: entry.id, child: entry.build()),
          ),
        );
        // A turn of the *real* event loop, which is what lets an asset read
        // complete — the boot turn that replaces `UNIT_TEST_ASSETS`, whose
        // handler deadlocks any `runAsync` that reads an asset itself.
        await tester.runAsync(() async {
          for (var i = 0; i < 5; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 1));
          }
        });
        await Settle.standard.apply(tester);
      } finally {
        FlutterError.onError = previous;
        // Inside the body, never a tearDown: the binding verifies its debug
        // variables at the end of the body, and a reset filed as a tearDown
        // fails the test it was meant to clean up after.
        reset();
        collect?[entry.id] = GuestErrors.instance.describe();
      }
      // Nothing is taken from the binding on purpose. An entry that reported
      // anything leaves it pending, and a pending exception is what fails this
      // test — which is the whole answer in the `flutter test` lane, and one
      // more way of saying it in the driven one.
    });
  }
}
