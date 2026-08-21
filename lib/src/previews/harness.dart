import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
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
import '../ui_catalog/fake_keyboard.dart';
import '../inspect/error.dart';
import '../inspect/guest_errors.dart';
import '../inspect/guest_inspect.dart';
import '../scenarios/asset_bundle.dart';
import '../scenarios/fonts.dart';
import '../scenarios/real_work.dart';
import '../scenarios/run_args.dart';
import '../scenarios/settle.dart';
import '../scenarios/staging.dart';
import '../ui_catalog/guest.dart';

/// How much fake clock an entry is given before it is judged.
const auditBudget = Duration(seconds: 5);

/// [Settle.elapse] rather than [Settle.standard], because the audit is the one
/// caller with nothing to photograph.
///
/// A frame-driven settle returns at the first frame the entry does not ask for,
/// and an entry waiting on a timer asks for none while it waits — an image
/// provider that sleeps before it decodes, a demo holding its placeholder long
/// enough to be seen. The tree is then disposed with that timer still on the
/// clock, and `flutter_test` reports that as the entry leaking a timer, which
/// reads as the entry's bug and is the harness's. Spending the clock instead
/// costs close to nothing here — a pump with nothing due builds no frame — and
/// widens what the error buffer sees, since every frame in between is still
/// built and still reported.
///
/// What this policy gives up is the screen *as it settled*: what a capture
/// photographs is the screen at `budget`. The comparison rides that on
/// purpose — under a fake clock the screen at `budget` is the same picture
/// every run, animations and all, and a diff wants reproducible pixels more
/// than it wants the prettiest frame.
const auditSettle = Settle.elapse(auditBudget);

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
/// The same widgets, the same errors, a different engine. Each entry is
/// mounted under [CatalogGuest] and its annotation's `wrapper`, exactly as the
/// embedder guest's entrypoint mounts it, and errors are collected into
/// [GuestErrors] — the same buffer, the same dedup key, the same counts. What
/// changes is only that the frame is drawn by a test binding under FakeAsync
/// rather than by a real engine in real time, which is what takes a
/// catalog-wide render from minutes to seconds: a demo that animates for ever
/// costs a few microseconds of fake clock instead of a three-second wait.
///
/// Two lanes off one generated file, told apart by whether a test runner is
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
///   measuring unstyled text in *approximate* Roboto — real bytes under the
///   platform-default family names, which is near enough for an overflow
///   verdict to mean something and not near enough for a pixel-exact one.
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
    //
    // The defaults too, and only in this branch: `--use-test-fonts` boxes the
    // families nobody loads bytes for, and the families most of a catalog
    // names none of are exactly those. `runScenarios` does the same two lines
    // for the scenario half of this lane; see [loadDefaultScenarioFonts] for
    // why the driven lane below must not.
    setUpAll(() async {
      await loadScenarioFonts();
      await loadDefaultScenarioFonts();
    });
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
        // A directory to photograph into. Pixels stay out of the response —
        // a frame is megabytes and the service protocol is JSON — so what
        // travels back is the paths, the way a scenario run reports its
        // captures.
        output: args['output'],
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
  String? output,
}) async {
  var wanted = [
    for (var entry in entries)
      if (only == null || only.contains(entry.id)) entry,
  ];
  var collected = <String, InspectErrors>{};
  var captured = <String, Map<String, Object?>>{};
  var declarer = Declarer();
  declarer.declare(
    () => _declare(
      wanted,
      canvases,
      collect: collected,
      device: device,
      orientation: orientation,
      output: output,
      captured: captured,
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
        failures[entry.id] ??= auditFailureMessage(details.exceptionAsString());
    try {
      await live.run();
    } finally {
      reportTestException = priorReporter;
    }
    for (var error in live.errors) {
      failures[entry.id] ??= auditFailureMessage('${error.error}');
    }
  }

  return {
    'ms': watch.elapsedMilliseconds,
    'entries': {
      for (var entry in wanted)
        entry.id: {
          ...?collected[entry.id]?.toJson(),
          ...?captured[entry.id],
          // Something went wrong that is not a framework error the build
          // reported — the builder threw outright, a test timed out. Reported
          // separately because it is a different kind of broken: the entry did
          // not render at all rather than rendering badly.
          'failure': ?failures[entry.id],
        },
    },
  };
}

/// A row says what happened, not what `flutter_test` calls it.
///
/// The pending-timer assertion is the one failure whose wording sends the
/// reader to the wrong place. `flutter_test` says a timer is still pending
/// *after the widget tree was disposed* and quotes a line of `binding.dart` to
/// say it, which reads as the entry leaking a timer — but the disposal is
/// [auditSettle] reaching the end of [auditBudget], and how long the audit
/// waits is the fact that makes the row actionable. It separates a demo that
/// sleeps longer than the audit does from one whose timer never stops; the
/// framework's spelling separates neither.
String auditFailureMessage(String failure) {
  if (!failure.contains('A Timer is still pending')) return failure;
  return 'A Timer this entry started had not fired after ${auditBudget.inSeconds}s '
      'of the audit clock, so the harness disposed the tree with it '
      'outstanding. Either the entry waits longer than the audit does, or its '
      'timer never stops.';
}

/// Declares one `testWidgets` per entry into whichever declarer is current.
///
/// [collect] is where each entry's report lands in the driven lane. Null in the
/// `flutter test` lane, where nobody is going to read it and the test's own
/// pass or fail is the whole answer.
///
/// [output] asks for pictures: each entry's settled screen and its tree are
/// written under it and their paths land in [captured]. Only the driven lane
/// passes it — the comparison is the caller — so an ordinary audit pays
/// nothing for the capability.
void _declare(
  List<PreviewEntry> entries,
  List<PreviewCanvas> canvases, {
  required Map<String, InspectErrors>? collect,
  Device? device,
  ScreenOrientation? orientation,
  String? output,
  Map<String, Map<String, Object?>>? captured,
}) {
  for (var (index, entry) in entries.indexed) {
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
      // The other buffer nothing empties between bodies, and the expensive
      // one: an entry left holding a pending decode makes every entry after
      // it wait out the whole real-work allowance on it.
      resetAnnouncedWork();
      // A device named for the whole run wins over every canvas; absent, each
      // entry is framed as its own subtree declared. `canvasFor` rather than a
      // prefix match written out again here, because a rule applied twice is a
      // rule that eventually differs.
      var canvas = canvasFor(canvases, entry.path);
      var reset = switch ((device, canvas?.defaultDevice)) {
        (var named?, _) => tester.applyDevice(
          named,
          orientation: orientation,
          // The device is the run's; the keyboard is still the entry's own
          // canvas talking, because *which entries are worth seeing with a
          // keyboard over them* is a fact about the entries and not about
          // which phone somebody asked for.
          keyboard: canvas?.defaultKeyboard,
        ),
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
      // Held rather than built inline: `landRealWork` reads its in-flight count
      // to know an asset the entry asked for is genuinely still on the way.
      var assets = ScenarioAssetBundle();
      try {
        // The harness read the app's fonts through `rootBundle` at startup, and
        // that cached a future belonging to a zone this test is not in.
        rootBundle.clear();
        await tester.pumpWidget(
          // Caches values where `rootBundle` caches futures, which is what makes
          // an asset the app has already read safe to read again from inside
          // `runAsync`. An app installing its own still wins — it is nearer.
          DefaultAssetBundle(
            bundle: assets,
            // The same two wrappers the embedder guest's entrypoint mounts, in
            // the same order, so what differs between the backends is the
            // engine and not the tree. `CatalogGuest` is what makes knobs
            // answer and what resets the axes, errors and logs per entry.
            // And the keyboard, if the canvas staged one — as tall as the
            // view says, so the picture and the layout are the same number.
            //
            // **Always the letters one, and that is a limit of this lane.**
            // The canvas stages its keyboard *before* the pump, so there is
            // nothing focused yet to read a variant off; an entry that
            // autofocuses a `phone` field is drawn here with the keyboard the
            // canvas asked for rather than the one the field did. Following
            // it would need a driver sampling between frames, which is the
            // scenario lane's `ScenarioKeyboard` — and this lane renders one
            // cold frame.
            child: ViewKeyboardSlab(
              child: CatalogGuest(entryId: entry.id, child: entry.build()),
            ),
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
        // The boot turn above lands what the *first* frame asked for, and
        // nothing after that: a demo that holds a placeholder for half a second
        // starts its load inside the settle, on fake time the real loop never
        // sees, and is judged with the load still in flight. Measured on
        // `demo/vector_smoke.dart` — the entry pointing at an asset that does
        // not exist was reported clean, because the read that would have thrown
        // never completed. So the settle lands announced work as it goes, out
        // of the same purse as the landing after it.
        var budget = RealWorkBudget();
        var settled = await auditSettle.apply(
          tester,
          land: () => budget.land(tester, assets),
        );
        await landRealWork(
          tester,
          auditSettle,
          settled: settled,
          budget: budget,
          assets: assets,
        );
        // After the settle, so the picture is of the same screen the errors
        // are about. An entry whose build threw is photographed anyway — the
        // ErrorWidget is what is there — and the host decides whether that
        // picture is worth comparing.
        if (output != null) {
          captured?[entry.id] = await _capture(tester, entry, output, index);
        }
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

/// Photographs the settled screen into [output] and reads the tree it drew,
/// answering with the paths and the picture's dimensions.
///
/// Raw rgba, never PNG — the comparison reads pixels and encoding is ~80% of
/// what a capture costs, the same measurement the scenario capture cites. The
/// rect is physical and the output logical, which is also the scenario rule:
/// the root layer's coordinates have the device-pixel-ratio transform inside
/// them, so a 3× canvas captured at face value saves its top-left ninth.
Future<Map<String, Object?>> _capture(
  WidgetTester tester,
  PreviewEntry entry,
  String output,
  int index,
) async {
  var directory = Directory(output)..createSync(recursive: true);
  var imagePath = p.join(directory.path, '$index.raw');
  var treePath = p.join(directory.path, '$index.tree.json');
  var width = 0;
  var height = 0;
  // A real-async turn, like the scenario capture: `toImage` completes on the
  // real event loop, which fake time never runs.
  await tester.runAsync(() async {
    var view = tester.binding.renderViews.single;
    var layer = view.debugLayer! as OffsetLayer;
    var dpr = view.flutterView.devicePixelRatio;
    var image = await layer.toImage(
      Offset.zero & (view.size * dpr),
      pixelRatio: 1 / dpr,
    );
    var data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    width = image.width;
    height = image.height;
    image.dispose();
    File(imagePath).writeAsBytesSync(data.buffer.asUint8List());
  });
  // The same walk every other surface answers with, so the comparison's tree
  // diff reads the identical shape a live guest or a scenario step reports.
  var tree = GuestInspector(
    rootOf: () => CatalogGuest.demoRoot,
    entryIdOf: () => entry.id,
  ).read();
  File(treePath).writeAsStringSync(jsonEncode(tree.toJson()));
  return {
    'image': imagePath,
    'width': width,
    'height': height,
    'tree': treePath,
  };
}
