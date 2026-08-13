@Timeout(Duration(minutes: 4))
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware_app/src/scenarios/authoring.dart';
import 'package:flutterware_app/src/scenarios/axes.dart';
import 'package:flutterware_app/src/scenarios/harness_entrypoint.dart';
import 'package:flutterware_app/src/scenarios/runner.dart';
import 'package:path/path.dart' as p;

/// End-to-end: the real `examples/example` package, a real `flutter_tester`,
/// a real run. Slow (a cold harness compile), so everything is exercised in
/// one warm sequence rather than one test per assertion.
void main() {
  test('lists, runs, and writes the step triple', () async {
    var flutterRoot = Platform.environment['FLUTTER_ROOT'];
    expect(
      flutterRoot,
      isNotNull,
      reason: 'flutter test always sets FLUTTER_ROOT',
    );
    // app/ → the repo root, the workspace this test runs in.
    var repoRoot = Directory.current.parent.path;
    var packageRoot = p.join(repoRoot, 'examples', 'example');
    var outDir = Directory.systemTemp.createTempSync('scenario_run').path;

    var runner = ScenarioRunner(
      packageRoot: packageRoot,
      directory: 'test/scenarios',
      flutterSdkRoot: flutterRoot!,
    );
    try {
      var listed = await runner.list();
      expect([
        for (var s in listed) '${s.file} ${s.name}',
      ], contains('test/scenarios/counter_test.dart Counter'));

      // Each step is also announced mid-run over the VM service — the
      // streaming half; the blocking response stays the complete report.
      var streamed = <Map<String, Object?>>[];
      runner.onStep = streamed.add;

      var report = await runner.run(
        outDir: outDir,
        file: 'test/scenarios/counter_test.dart',
        scenario: 'Counter',
      );
      var scenarios = (report['scenarios']! as List)
          .cast<Map<String, dynamic>>();
      expect(scenarios, hasLength(1));
      var counter = scenarios.single;
      expect(counter['ok'], isTrue, reason: '${counter['errors']}');

      var steps = (counter['steps']! as List).cast<Map<String, dynamic>>();
      // Two auto taps, one named shot, one auto enterText, one screen().
      expect(steps, hasLength(5));
      expect([
        for (var s in steps) s['name'],
      ], containsAll(['Counted to two', 'Labelled']));
      for (var step in steps) {
        var png = File(step['image']! as String);
        expect(png.existsSync(), isTrue);
        expect(png.lengthSync(), greaterThan(1000));
        expect(step['format'], 'png');
        var tree =
            jsonDecode(File(step['tree']! as String).readAsStringSync())
                as Map<String, dynamic>;
        expect(tree['root'], isNotNull);
        // The fourth leg: what a screen reader gets, beside the widget tree.
        var semantics =
            jsonDecode(File(step['semantics']! as String).readAsStringSync())
                as Map<String, dynamic>;
        expect(semantics['rect'], isNotNull);
        expect(semantics['children'], isNotEmpty);
      }
      var last = steps.last;
      expect((last['texts']! as List).cast<String>(), contains('a label'));

      expect(streamed, hasLength(5));
      expect(streamed.first['scenario'], 'Counter');
      expect((streamed.first['step']! as Map)['index'], 1);
      runner.onStep = null;

      // A run that did not ask records nothing — the CLI lane, and what keeps
      // it costing what it always cost.
      expect(steps.every((s) => s['frames'] == null), isTrue);

      // Recording on: the sixth leg, a directory of numbered frames beside
      // the pixels. The panel's settings, so this is the real cost too.
      var recorded = await runner.run(
        outDir: outDir,
        file: 'test/scenarios/counter_test.dart',
        scenario: 'Counter',
        recordInterval: const Duration(milliseconds: 33),
        recordScale: 0.5,
      );
      var recordedSteps =
          ((recorded['scenarios']! as List).single
                  as Map<String, dynamic>)['steps']!
              as List;
      var withMotion = [
        for (var step in recordedSteps.cast<Map<String, dynamic>>())
          if (step['frames'] != null) step,
      ];
      expect(withMotion, isNotEmpty);
      for (var step in withMotion) {
        expect(step['frameIntervalMs'], 33);
        var count = step['frameCount']! as int;
        expect(count, greaterThan(1));
        // Half of the run's own capture scale, and every frame on disk.
        expect(step['frameWidth'], lessThan(step['width']! as int));
        var directory = Directory(step['frames']! as String);
        expect(
          directory.listSync().whereType<File>(),
          hasLength(count),
          reason: 'every frame written',
        );
      }

      // Warm re-run: the compiled harness and the live tester are reused, so
      // this is the instantaneous FakeAsync loop, not a second cold start.
      var watch = Stopwatch()..start();
      var rerun = await runner.run(
        outDir: outDir,
        file: 'test/scenarios/counter_test.dart',
        scenario: 'Counter',
      );
      expect(((rerun['scenarios']! as List).single as Map)['ok'], isTrue);
      expect(watch.elapsed, lessThan(const Duration(seconds: 10)));

      // A new scenario file. No hot reload re-runs the generated entrypoint's
      // `main`, so this must take the restart lane — and prove the freshly
      // imported file arrives.
      var scratch = File(
        p.join(packageRoot, 'test', 'scenarios', 'scratch_test.dart'),
      );
      scratch.writeAsStringSync(_scratchSource('v1'));
      try {
        await runner.refresh();
        var refreshed = await runner.list();
        expect([
          for (var s in refreshed) '${s.file} ${s.name}',
        ], contains('test/scenarios/scratch_test.dart Scratch'));
        expect(
          _scratchTexts(
            await runner.run(
              outDir: outDir,
              file: 'test/scenarios/scratch_test.dart',
              scenario: 'Scratch',
            ),
          ),
          contains('v1'),
        );

        // A body edit. `run` on a warm runner refreshes by itself — the Run
        // button never replays stale code — and the same file set means this
        // takes the reload lane, not a restart.
        await Future<void>.delayed(const Duration(seconds: 1));
        scratch.writeAsStringSync(_scratchSource('v2'));
        expect(
          _scratchTexts(
            await runner.run(
              outDir: outDir,
              file: 'test/scenarios/scratch_test.dart',
              scenario: 'Scratch',
            ),
          ),
          contains('v2'),
        );
      } finally {
        scratch.deleteSync();
      }

      // The transition events, end to end through a real tester: the three
      // automatic lanes and the reported one, on the step each belongs to.
      var signIn = await runner.run(
        outDir: outDir,
        file: 'test/scenarios/events_test.dart',
        scenario: 'Signing in',
      );
      var signInOutcome = (signIn['scenarios']! as List).single as Map;
      expect(signInOutcome['ok'], isTrue, reason: '${signInOutcome['errors']}');
      var signInSteps = (signInOutcome['steps']! as List).cast<Map>();
      // Every step names the transition into it, which is what the flow's
      // arrows and the Events tab's header both read.
      expect(
        [for (var step in signInSteps) '${step['verb']} ${step['target']}'],
        [
          'pumpWidget _SignInApp',
          'enterText TextField',
          'tap "Sign in"',
          'screen null',
        ],
      );
      // The tap is the interesting transition: the app logged, the fake
      // reported a request, a query and an analytics event, and the framework
      // talked to `flutter/textinput` on the way.
      var tapped = signInSteps[2];
      expect(tapped['eventChannels'], containsPair('log', 1));
      expect(tapped['eventChannels'], containsPair('network', 1));
      expect(tapped['eventChannels'], containsPair('db', 1));
      expect(tapped['eventChannels'], containsPair('analytics', 1));
      // Captured, and left out of the inline digest, which is the whole
      // policy: the volume is real and the reader filters it away.
      expect(tapped['eventChannels'], contains('system'));
      expect(
        (tapped['eventTitles']! as List).cast<String>(),
        containsAll(<String>['POST /sessions → 200', 'sign_in']),
      );
      var events =
          jsonDecode(File(tapped['events']! as String).readAsStringSync())
              as List;
      expect(
        [
          for (var event in events.cast<Map>())
            if (event['channel'] == 'db') event['body'],
        ],
        ['INSERT INTO sessions (email) VALUES (?)'],
      );

      // The `new` action's scaffold, run as written. It is the only
      // documentation of the scenario API that executes, so it is checked
      // where a real tester already is: change `tap` or `Shot` and this is
      // what says the template now teaches something that does not exist.
      var scaffold = File(
        p.join(packageRoot, 'test', 'scenarios', 'scaffold_check_test.dart'),
      );
      scaffold.writeAsStringSync(scenarioScaffold('Scaffold check'));
      try {
        await runner.refresh();
        var scaffolded = await runner.run(
          outDir: outDir,
          file: 'test/scenarios/scaffold_check_test.dart',
          scenario: 'Scaffold check',
        );
        var outcome = (scaffolded['scenarios']! as List).single as Map;
        expect(outcome['ok'], isTrue, reason: '${outcome['errors']}');
        expect(
          [
            for (var step in (outcome['steps']! as List).cast<Map>())
              step['name'],
          ],
          [null, 'Tapped continue'],
        );
      } finally {
        scaffold.deleteSync();
      }

      // Axes: the same warm harness, run as an iPhone in French, dark and
      // scaled — then bare again, proving the reset is per-run, not
      // per-process. The probe scenario prints what `MediaQuery` actually
      // sees, so these assertions are the app's view, not the harness's.
      var probe = File(
        p.join(packageRoot, 'test', 'scenarios', 'axes_probe_test.dart'),
      );
      probe.writeAsStringSync(_probeSource);
      try {
        var framed = await runner.run(
          outDir: outDir,
          file: 'test/scenarios/axes_probe_test.dart',
          scenario: 'Probe',
          axes: const ScenarioAxes(
            device: 'iphone-se',
            language: 'fr-CA',
            textScale: 1.3,
            brightness: 'dark',
            boldText: true,
          ),
        );
        expect(
          _scratchTexts(framed),
          contains('375x667 2.0 20.0 fr-CA Brightness.dark 13.0 true'),
        );
        // Logical pixels by default — the measured cost of physical capture
        // (10× the time and bytes) is not a good default; `captureScale`
        // buys it back explicitly.
        expect(_pngSize(_lastPng(framed)), (375, 667));

        var bare = await runner.run(
          outDir: outDir,
          file: 'test/scenarios/axes_probe_test.dart',
          scenario: 'Probe',
        );
        var text = _scratchTexts(bare).single;
        expect(text, startsWith('800x600 3.0 0.0'));
        expect(text, contains('Brightness.light'));
        expect(text, endsWith('10.0 false'));
        expect(_pngSize(_lastPng(bare)), (800, 600));

        // The knob back up: the device's own ratio is a true screenshot.
        var sharp = await runner.run(
          outDir: outDir,
          file: 'test/scenarios/axes_probe_test.dart',
          scenario: 'Probe',
          axes: const ScenarioAxes(device: 'iphone-se'),
          captureScale: 2,
        );
        expect(_pngSize(_lastPng(sharp)), (750, 1334));

        // Native resolution is resolved **in the guest**, at capture time —
        // the device may have come from a folder profile the host never saw,
        // so a ratio computed here would be a guess.
        var native = await runner.run(
          outDir: outDir,
          file: 'test/scenarios/axes_probe_test.dart',
          scenario: 'Probe',
          axes: const ScenarioAxes(device: 'iphone-16'),
          captureNative: true,
        );
        expect(_pngSize(_lastPng(native)), (393 * 3, 852 * 3));

        // Raw skips PNG encoding — ~80% of a capture's cost — and writes
        // bare rgba8888, width×height×4, exactly as the step reports.
        var raw = await runner.run(
          outDir: outDir,
          file: 'test/scenarios/axes_probe_test.dart',
          scenario: 'Probe',
          axes: const ScenarioAxes(device: 'iphone-se'),
          captureRaw: true,
        );
        var rawStep =
            (((raw['scenarios']! as List).single as Map)['steps']! as List).last
                as Map;
        expect(rawStep['format'], 'raw');
        expect(rawStep['image'] as String, endsWith('.raw'));
        expect((rawStep['width'], rawStep['height']), (375, 667));
        expect(File(rawStep['image']! as String).lengthSync(), 375 * 667 * 4);
      } finally {
        probe.deleteSync();
      }

      // A nested split: the body replays once per path, shared-prefix steps
      // are captured exactly once, and every step carries the parent link
      // (and the branch label on a branch's first step) the flow graph draws
      // its edges from.
      var forked = File(
        p.join(packageRoot, 'test', 'scenarios', 'split_test.dart'),
      );
      forked.writeAsStringSync(_splitSource);
      try {
        var report = await runner.run(
          outDir: outDir,
          file: 'test/scenarios/split_test.dart',
          scenario: 'Split',
        );
        var outcome = (report['scenarios']! as List).single as Map;
        expect(outcome['ok'], isTrue, reason: '${outcome['errors']}');
        var steps = (outcome['steps']! as List).cast<Map<String, dynamic>>();
        // 3 paths → root and L once each, tail three times: 8, not 10.
        expect(steps, hasLength(8));
        Map<String, dynamic> named(String name) =>
            steps.singleWhere((s) => s['name'] == name);
        (int?, String?) shape(String name) =>
            (named(name)['parent'] as int?, named(name)['branch'] as String?);

        expect(shape('root'), (null, null));
        expect(shape('L'), (named('root')['index'], 'left'));
        expect(shape('LX'), (named('L')['index'], 'x'));
        expect(shape('LY'), (named('L')['index'], 'y'));
        expect(shape('R'), (named('root')['index'], 'right'));
        // One tail per leaf, each chained to its own path's last step.
        var leaves = {
          for (var name in ['LX', 'LY', 'R']) named(name)['index'],
        };
        var tails = steps.where((s) => s['name'] == 'tail').toList();
        expect(tails, hasLength(3));
        expect({for (var t in tails) t['parent']}, leaves);
      } finally {
        forked.deleteSync();
      }

      // A scenario the author wrapped in a `group()` — listed by its own
      // name, and runnable by it. `test_api` composes the full name out of
      // the enclosing groups, so filtering by that name is the harness's job
      // rather than the declarer's.
      var grouped = File(
        p.join(packageRoot, 'test', 'scenarios', 'grouped_test.dart'),
      );
      grouped.writeAsStringSync(_groupedSource);
      try {
        await runner.refresh();
        expect([
          for (var s in await runner.list()) s.name,
        ], containsAll(['inside a group', 'outside any group']));
        expect(
          _scratchTexts(
            await runner.run(
              outDir: outDir,
              file: 'test/scenarios/grouped_test.dart',
              scenario: 'inside a group',
            ),
          ),
          contains('grouped'),
        );
      } finally {
        grouped.deleteSync();
      }

      // `setUpAll` and `tearDownAll`: stored on the group rather than among
      // its entries, so a walk over entries alone never ran them — the one
      // way a file could pass under `flutter test` and capture the wrong
      // screens here. The fixture writes what its hooks did into the app, so
      // the assertion is what the scenario actually saw.
      var hooks = File(
        p.join(packageRoot, 'test', 'scenarios', 'hooks_test.dart'),
      );
      hooks.writeAsStringSync(_hooksSource.replaceAll('OUT_DIR', outDir));
      try {
        await runner.refresh();
        var whole = await runner.run(
          outDir: outDir,
          file: 'test/scenarios/hooks_test.dart',
        );
        var ran = (whole['scenarios']! as List).cast<Map<String, dynamic>>();
        expect(ran.map((s) => s['name']), ['Seeded', 'Also seeded']);
        expect(ran.every((s) => s['ok'] == true), isTrue, reason: '$ran');
        // Once for the group, not once per scenario, and the tear-down ran
        // after the last one.
        expect(
          [
            for (var s in ran)
              ((s['steps']! as List).last as Map)['texts']! as List,
          ],
          [
            ['setUpAll:1'],
            ['setUpAll:1'],
          ],
        );
        expect(
          File(p.join(outDir, 'teardown.txt')).readAsStringSync(),
          'torn down',
        );

        // One scenario asked for by name still gets the group's fixtures.
        // `setUpAll:2`, not `1`: the fixture is built once per *run request*,
        // and the counter lives in a guest that outlives the request — which
        // is the scope this harness owes a user who edits a fixture and hits
        // Run again.
        File(p.join(outDir, 'teardown.txt')).deleteSync();
        var one = await runner.run(
          outDir: outDir,
          file: 'test/scenarios/hooks_test.dart',
          scenario: 'Also seeded',
        );
        expect(_scratchTexts(one), ['setUpAll:2']);
        expect(File(p.join(outDir, 'teardown.txt')).existsSync(), isTrue);
      } finally {
        hooks.deleteSync();
      }

      // A `setUpAll` that throws: the scenarios under it do not run against
      // half-built state, and each one that would have run says why.
      var brokenHook = File(
        p.join(packageRoot, 'test', 'scenarios', 'broken_hook_test.dart'),
      );
      brokenHook.writeAsStringSync(_brokenHookSource);
      try {
        await runner.refresh();
        var report = await runner.run(
          outDir: outDir,
          file: 'test/scenarios/broken_hook_test.dart',
        );
        var outcome =
            ((report['scenarios']! as List).single) as Map<String, dynamic>;
        expect(outcome['name'], 'never runs');
        expect(outcome['ok'], isFalse);
        expect(outcome['steps'], isEmpty);
        expect('${outcome['errors']}', contains('the fixture is broken'));
      } finally {
        brokenHook.deleteSync();
      }

      // A folder with its own `flutter_test_config.dart`: the harness runs it
      // — the same file `flutter test` would run — and reports what it says
      // the folder is for. Executed, never parsed, so a profile imported from
      // somewhere else reads exactly as well as one written in place.
      var folder = Directory(
        p.join(packageRoot, 'test', 'scenarios', 'profiled'),
      )..createSync(recursive: true);
      File(
        p.join(folder.path, 'flutter_test_config.dart'),
      ).writeAsStringSync(_folderConfigSource);
      File(
        p.join(folder.path, 'profiled_test.dart'),
      ).writeAsStringSync(_profiledSource);
      // The same scenario outside the folder, to prove the framing is worked
      // out per file rather than per request.
      var unprofiled = File(
        p.join(packageRoot, 'test', 'scenarios', 'unprofiled_test.dart'),
      )..writeAsStringSync(_profiledSource);
      try {
        await runner.refresh();
        var listed = await runner.list();
        var profiled = listed.firstWhere((s) => s.name == 'Profiled');
        expect(profiled.profile, 'phones');
        expect(profiled.devices, ['iphone-se', 'android-tall']);
        expect(profiled.languages, ['fr', 'en']);
        // A scenario outside that folder is not governed by it.
        expect(listed.firstWhere((s) => s.name == 'Counter').profile, isNull);

        // The run itself is the runner's, not the config's: one pass, at the
        // axes the request named rather than the profile's head.
        var report = await runner.run(
          outDir: outDir,
          file: 'test/scenarios/profiled/profiled_test.dart',
          scenario: 'Profiled',
          axes: const ScenarioAxes(device: 'iphone-se'),
        );
        var outcome = (report['scenarios']! as List).single as Map;
        expect(outcome['ok'], isTrue, reason: '${outcome['errors']}');
        expect(outcome['steps']! as List, hasLength(1));
        expect(_scratchTexts(report), ['375.0x667.0']);
        expect(outcome['device'], 'iphone-se');

        // And a request that names *no* device leaves the folder to answer:
        // the profile's head, not the fallback the host would otherwise
        // apply. The two are different sizes, which is the whole assertion.
        var byFolder = await runner.run(
          outDir: outDir,
          file: 'test/scenarios/profiled/profiled_test.dart',
          scenario: 'Profiled',
          unspecifiedDevice: 'iphone-13',
        );
        expect(_scratchTexts(byFolder), ['375.0x667.0']);
        expect(
          ((byFolder['scenarios']! as List).single as Map)['device'],
          'iphone-se',
        );

        // A scenario the folder does not govern takes the fallback instead —
        // one run, two framings, worked out per file.
        var elsewhere = await runner.run(
          outDir: outDir,
          file: 'test/scenarios/unprofiled_test.dart',
          scenario: 'Profiled',
          unspecifiedDevice: 'iphone-13',
        );
        expect(_scratchTexts(elsewhere), ['390.0x844.0']);
        expect(
          ((elsewhere['scenarios']! as List).single as Map)['device'],
          'iphone-13',
        );
      } finally {
        folder.deleteSync(recursive: true);
        unprofiled.deleteSync();
      }

      // An ordinary `testWidgets` living in the scenario folder: it produces
      // no steps and cannot be opened in the panel, so `list` never showed it
      // — and `run` used to execute it anyway. Both now agree it is not a
      // scenario.
      var strayTest = File(
        p.join(packageRoot, 'test', 'scenarios', 'stray_test.dart'),
      )..writeAsStringSync(_straySource);
      try {
        await runner.refresh();
        var listed = await runner.list();
        expect([for (var s in listed) s.name], contains('A real scenario'));
        expect([for (var s in listed) s.name], isNot(contains('Plain widget')));

        var report = await runner.run(
          outDir: outDir,
          file: 'test/scenarios/stray_test.dart',
        );
        expect(
          [
            for (var s
                in (report['scenarios']! as List).cast<Map<String, dynamic>>())
              s['name'],
          ],
          ['A real scenario'],
        );
      } finally {
        strayTest.deleteSync();
      }

      // Tags: declared on the scenario, reported by the listing, and the one
      // thing `run --tag` filters on. The syntactic scan cannot see them —
      // it never evaluates an argument — so the live listing is the only
      // place they exist.
      var tagged = File(
        p.join(packageRoot, 'test', 'scenarios', 'tagged_test.dart'),
      )..writeAsStringSync(_taggedSource);
      try {
        await runner.refresh();
        var listed = await runner.list();
        expect(listed.firstWhere((s) => s.name == 'Smoke tagged').tags, [
          'smoke',
        ]);
        expect(listed.firstWhere((s) => s.name == 'Untagged').tags, isEmpty);

        var filtered = await runner.run(
          outDir: outDir,
          file: 'test/scenarios/tagged_test.dart',
          tag: 'smoke',
        );
        expect(
          [
            for (var s
                in (filtered['scenarios']! as List)
                    .cast<Map<String, dynamic>>())
              s['name'],
          ],
          ['Smoke tagged'],
        );
      } finally {
        tagged.deleteSync();
      }

      // The verbs past tap and enterText, through the real substrate: a list
      // walked until an off-screen row is on screen, a scoped icon tapped
      // inside that row, and a clock moved past a timer no settle would wait
      // for.
      var verbs = File(
        p.join(packageRoot, 'test', 'scenarios', 'verbs_test.dart'),
      );
      verbs.writeAsStringSync(_verbsSource);
      try {
        await runner.refresh();
        var outcome =
            (await runner.run(
                  outDir: outDir,
                  file: 'test/scenarios/verbs_test.dart',
                  scenario: 'Verbs',
                ))['scenarios']!
                as List;
        var run = outcome.single as Map;
        expect(run['ok'], isTrue, reason: '${run['errors']}');
        var last = (run['steps']! as List).last as Map;
        expect((last['texts']! as List).cast<String>(), contains('starred 30'));
      } finally {
        verbs.deleteSync();
      }

      // A screen that never stops animating, and a scenario that breaks in a
      // split branch — the two things a run says about itself when it is not
      // simply fine. Both travel as step fields, so the panel and an agent
      // read them the same way.
      var unhappy = File(
        p.join(packageRoot, 'test', 'scenarios', 'unhappy_test.dart'),
      );
      unhappy.writeAsStringSync(_unhappySource);
      try {
        await runner.refresh();
        var spinning =
            (await runner.run(
                  outDir: outDir,
                  file: 'test/scenarios/unhappy_test.dart',
                  scenario: 'Spinning',
                ))['scenarios']!
                as List;
        var outcome = spinning.single as Map;
        // Never settling is not a failure: the run passes, and the steps say
        // the app was still animating.
        expect(outcome['ok'], isTrue, reason: '${outcome['errors']}');
        var steps = (outcome['steps']! as List).cast<Map<String, dynamic>>();
        expect(steps.map((s) => s['settled']), everyElement(isFalse));

        var broken =
            (await runner.run(
                  outDir: outDir,
                  file: 'test/scenarios/unhappy_test.dart',
                  scenario: 'Broken',
                ))['scenarios']!
                as List;
        var failed = broken.single as Map;
        expect(failed['ok'], isFalse);
        expect('${failed['errors']}', contains('in split branch "by card"'));
        var last = (failed['steps']! as List).last as Map;
        expect(last['failure'], contains('in split branch "by card"'));
        expect(last['failure'], contains('nothing matches "Pay now"'));
        // The failure has a picture, and it is of the screen it broke on.
        expect(File(last['image']! as String).existsSync(), isTrue);
        expect((last['texts']! as List).cast<String>(), contains('Checkout'));
      } finally {
        unhappy.deleteSync();
      }

      // A guest that dies mid-session is noticed: the next run respawns one
      // instead of talking to a service that is gone. (Killing it from here
      // is the same thing the OS does when a scenario blows the isolate up.)
      await runner.debugKillGuest();
      var revived = await runner.run(
        outDir: outDir,
        file: 'test/scenarios/counter_test.dart',
        scenario: 'Counter',
      );
      expect(((revived['scenarios']! as List).single as Map)['ok'], isTrue);
    } finally {
      await runner.dispose();
      Directory(outDir).deleteSync(recursive: true);
    }
  });

  test(
    'a failed cold start is forgotten, not memoized',
    () async {
      var flutterRoot = Platform.environment['FLUTTER_ROOT']!;
      var repoRoot = Directory.current.parent.path;
      var packageRoot = p.join(repoRoot, 'examples', 'example');
      var outDir = Directory.systemTemp.createTempSync('scenario_cold').path;

      // An empty directory is the cheapest cold-start failure there is — no
      // compile, same lane.
      var empty = Directory(p.join(packageRoot, 'test', 'scenarios_cold'))
        ..createSync(recursive: true);
      var runner = ScenarioRunner(
        packageRoot: packageRoot,
        directory: 'test/scenarios_cold',
        flutterSdkRoot: flutterRoot,
      );
      try {
        await expectLater(runner.list(), throwsA(isA<StateError>()));

        // The fix: writing the scenario the runner complained about and asking
        // again starts it, rather than replaying the old complaint forever.
        File(
          p.join(empty.path, 'cold_test.dart'),
        ).writeAsStringSync(_scratchSource('cold'));
        var listed = await runner.list();
        expect([for (var s in listed) s.name], contains('Scratch'));
      } finally {
        await runner.dispose();
        empty.deleteSync(recursive: true);
        Directory(outDir).deleteSync(recursive: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );

  test(
    'a package with no lib/main.dart runs, and taps a Material button',
    () async {
      var flutterRoot = Platform.environment['FLUTTER_ROOT']!;
      // The workspace root — the `flutterware` package itself, which has no
      // `lib/main.dart`, like any library or any app whose entry lives
      // elsewhere. Shelling out to `flutter build bundle` used to stop such a
      // package with `Target file "lib/main.dart" not found` before a single
      // scenario ran.
      var repoRoot = Directory.current.parent.path;
      var outDir = Directory.systemTemp.createTempSync('scenario_no_main').path;
      var dir = Directory(p.join(repoRoot, 'test', 'scenarios_no_main'))
        ..createSync(recursive: true);
      File(
        p.join(dir.path, 'ripple_test.dart'),
      ).writeAsStringSync(_rippleSource);

      var runner = ScenarioRunner(
        packageRoot: repoRoot,
        directory: 'test/scenarios_no_main',
        flutterSdkRoot: flutterRoot,
      );
      try {
        var report = await runner.run(outDir: outDir);
        var outcome = (report['scenarios']! as List).single as Map;
        expect(outcome['ok'], isTrue, reason: '${outcome['errors']}');
      } finally {
        await runner.dispose();
        dir.deleteSync(recursive: true);
        Directory(outDir).deleteSync(recursive: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );

  test(
    'a scenario that never returns is reported, and does not take the run',
    () async {
      var flutterRoot = Platform.environment['FLUTTER_ROOT']!;
      // Written into the workspace root and deleted after, like the
      // no-main test below: a scenario that never returns must not be left
      // lying inside a package whose `test/` a real run scans.
      var repoRoot = Directory.current.parent.path;
      var outDir = Directory.systemTemp.createTempSync('scenario_hang').path;
      var dir = Directory(p.join(repoRoot, 'test', 'scenarios_hang'))
        ..createSync(recursive: true);
      File(
        p.join(dir.path, 'hanging_test.dart'),
      ).writeAsStringSync(_hangingSource);

      var runner = ScenarioRunner(
        packageRoot: repoRoot,
        directory: 'test/scenarios_hang',
        flutterSdkRoot: flutterRoot,
      );
      try {
        var report = await runner.run(outDir: outDir);
        var scenarios = (report['scenarios']! as List)
            .cast<Map<String, dynamic>>();

        // The whole point: an answer came back at all.
        expect(report['abandoned'], isTrue);
        expect(scenarios, hasLength(1));
        var hung = scenarios.single;
        expect(hung['name'], 'Never returns');
        expect(hung['ok'], isFalse);
        expect(
          '${(hung['errors']! as List).first}',
          contains('did not finish within 2s'),
        );
        // Declared after it, and deliberately never reached.
        expect(
          scenarios.map((s) => s['name']),
          isNot(contains('After the hang')),
        );
      } finally {
        await runner.dispose();
        dir.deleteSync(recursive: true);
        Directory(outDir).deleteSync(recursive: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );

  test('the entrypoint file is left alone when its content is right', () {
    var root = Directory.systemTemp.createTempSync('scenario_entrypoint');
    try {
      var path = writeHarnessEntrypoint(root.path, ['test/scenarios/a.dart']);
      var written = File(path).statSync().modified;
      writeHarnessEntrypoint(root.path, ['test/scenarios/a.dart']);
      expect(File(path).statSync().modified, written);
    } finally {
      root.deleteSync(recursive: true);
    }
  });

  test('the generated entrypoint is stable and relative', () {
    var source = generateHarnessEntrypoint([
      'test/scenarios/b_test.dart',
      'test/scenarios/a_test.dart',
    ]);
    expect(
      source,
      '// GENERATED — flutterware scenarios harness. Do not edit.\n'
      "import 'package:flutterware/src/scenarios/harness.dart'\n"
      '    as harness;\n'
      "import '../../test/scenarios/a_test.dart' as s0;\n"
      "import '../../test/scenarios/b_test.dart' as s1;\n"
      '\n'
      'void main() => harness.runHarness(\n'
      '  {\n'
      "    'test/scenarios/a_test.dart': s0.main,\n"
      "    'test/scenarios/b_test.dart': s1.main,\n"
      '  },\n'
      ');\n',
    );
  });

  test('a folder config is imported and keyed by the folder it governs', () {
    var source = generateHarnessEntrypoint(
      ['test/scenarios/mobile/a_test.dart'],
      configs: ['test/scenarios/mobile/flutter_test_config.dart'],
    );

    expect(
      source,
      contains(
        "import '../../test/scenarios/mobile/flutter_test_config.dart' as c0;",
      ),
    );
    expect(source, contains("    'test/scenarios/mobile': c0.testExecutable,"));
  });
}

/// The last (only) step's texts of a single-scenario run report.
List<String> _scratchTexts(Map<String, Object?> report) {
  var scenarios = (report['scenarios']! as List).cast<Map<String, dynamic>>();
  var scratch = scenarios.single;
  expect(scratch['ok'], isTrue, reason: '${scratch['errors']}');
  var steps = (scratch['steps']! as List).cast<Map<String, dynamic>>();
  return (steps.last['texts']! as List).cast<String>();
}

/// A scenario that needs the bundle to be right in the one way a hand-written
/// one is most likely to get wrong: `FragmentProgram.fromAsset` throws unless
/// `shaders/ink_sparkle.frag` is the *compiled* form, and it is what an M3
/// button's first tap loads.
const _rippleSource = r'''
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutterware/flutter_test.dart';

void main() {
  scenario('Ripple', (s) async {
    await FragmentProgram.fromAsset('shaders/ink_sparkle.frag');
    await s.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: ElevatedButton(onPressed: () {}, child: const Text('Tap')),
          ),
        ),
      ),
    );
    await s.tap('Tap');
  });
}
''';

String _scratchSource(String label) =>
    '''
import 'package:flutter/material.dart';
import 'package:flutterware/flutter_test.dart';

void main() {
  scenario('Scratch', (s) async {
    await s.tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('$label'))),
    );
    await s.screen('shot');
  });
}
''';

/// The last step's image path of a single-scenario run report.
String _lastPng(Map<String, Object?> report) {
  var steps = ((report['scenarios']! as List).single as Map)['steps']! as List;
  return (steps.last as Map)['image']! as String;
}

/// Width and height from the PNG's IHDR chunk — no decoder needed.
(int, int) _pngSize(String path) {
  var bytes = File(path).readAsBytesSync();
  int word(int offset) =>
      (bytes[offset] << 24) |
      (bytes[offset + 1] << 16) |
      (bytes[offset + 2] << 8) |
      bytes[offset + 3];
  return (word(16), word(20));
}

/// A scenario nested in a user `group()`, beside one that is not.
const _groupedSource = r'''
import 'package:flutter/material.dart';
import 'package:flutterware/flutter_test.dart';

void main() {
  group('checkout', () {
    scenario('inside a group', (s) async {
      await s.pumpWidget(
        const MaterialApp(home: Scaffold(body: Text('grouped'))),
        shot: Shot('shot'),
      );
    });
  });

  scenario('outside any group', (s) async {
    await s.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('plain'))),
      shot: Shot('shot'),
    );
  });
}
''';

/// A nested split: three paths (left→x, left→y, right), a shared prefix
/// (`root`), and a step after the split (`tail`) that runs once per path.
const _splitSource = r'''
import 'package:flutter/material.dart';
import 'package:flutterware/flutter_test.dart';

void main() {
  scenario('Split', (s) async {
    await s.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('root'))),
      shot: Shot.skip,
    );
    await s.screen('root');
    await s.split({
      'left': () async {
        await s.screen('L');
        await s.split({
          'x': () async {
            await s.screen('LX');
          },
          'y': () async {
            await s.screen('LY');
          },
        });
      },
      'right': () async {
        await s.screen('R');
      },
    });
    await s.screen('tail');
  });
}
''';

/// A group with both `all` hooks, counting its own runs so the scenarios can
/// report whether the fixture was built once or once each.
const _hooksSource = r'''
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutterware/flutter_test.dart';

var setUps = 0;

void main() {
  setUpAll(() => setUps++);
  tearDownAll(() {
    // Written where the test can find it: the harness outlives the run, so a
    // tear-down that never ran would otherwise leave no trace either way.
    File('OUT_DIR/teardown.txt').writeAsStringSync('torn down');
  });

  scenario('Seeded', (s) async {
    await s.pumpWidget(
      MaterialApp(home: Scaffold(body: Text('setUpAll:$setUps'))),
    );
  });

  scenario('Also seeded', (s) async {
    await s.pumpWidget(
      MaterialApp(home: Scaffold(body: Text('setUpAll:$setUps'))),
    );
  });
}
''';

/// A `setUpAll` that throws — the fixture every scenario under it needed.
const _brokenHookSource = r'''
import 'package:flutter/material.dart';
import 'package:flutterware/flutter_test.dart';

void main() {
  setUpAll(() => throw StateError('the fixture is broken'));

  scenario('never runs', (s) async {
    await s.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('unreachable'))),
    );
  });
}
''';

/// A folder that declares what it is for. The profile is imported rather than
/// written inline, which is the case a syntactic scan could not have read.
const _folderConfigSource = '''
import 'dart:async';

import 'package:flutterware/flutter_test.dart';

const phones = ScenarioProfile(
  'phones',
  devices: [Devices.iphoneSe, Devices.androidTall],
  languages: ['fr', 'en'],
);

Future<void> testExecutable(FutureOr<void> Function() testMain) =>
    runScenarios(testMain, profile: phones);
''';

const _profiledSource = r'''
import 'package:flutter/material.dart';
import 'package:flutterware/flutter_test.dart';

void main() {
  scenario('Profiled', (s) async {
    await s.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            var size = MediaQuery.sizeOf(context);
            return Scaffold(body: Text('${size.width}x${size.height}'));
          },
        ),
      ),
    );
  });
}
''';

/// A scenario and a plain `testWidgets` in the same file — what `list` and
/// `run` used to disagree about.
const _straySource = r'''
import 'package:flutter/material.dart';
import 'package:flutterware/flutter_test.dart';

void main() {
  scenario('A real scenario', (s) async {
    await s.pumpWidget(const MaterialApp(home: Scaffold(body: Text('real'))));
  });

  testWidgets('Plain widget', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('plain'))),
    );
    expect(find.text('plain'), findsOneWidget);
  });
}
''';

/// Two scenarios, one tagged — the fixture for `--tag` and for what a
/// listing reports about it.
const _taggedSource = r'''
import 'package:flutter/material.dart';
import 'package:flutterware/flutter_test.dart';

void main() {
  scenario('Smoke tagged', tags: ['smoke'], (s) async {
    await s.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('tagged'))),
    );
  });

  scenario('Untagged', (s) async {
    await s.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('untagged'))),
    );
  });
}
''';

/// The verbs past tap and enterText: a list scrolled to an off-screen row, a
/// target scoped to that row, and a timer waited out.
const _verbsSource = r'''
import 'package:flutter/material.dart';
import 'package:flutterware/flutter_test.dart';

void main() {
  scenario('Verbs', (s) async {
    await s.pumpWidget(const _App(), shot: Shot.skip);
    await s.scrollTo('Item 30');
    await s.tap(const Target.within(ValueKey('row-30'), Icons.star));
    await s.wait(const Duration(seconds: 2));
    await s.screen('done');
  });
}

class _App extends StatefulWidget {
  const _App();
  @override
  State<_App> createState() => _AppState();
}

class _AppState extends State<_App> {
  var note = 'none';

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      // The note above the list, not in it: the last step's texts are what
      // the assertion reads, and a widget scrolled off the bottom is not
      // among them.
      body: Column(
        children: [
          Text(note),
          Expanded(
            child: ListView(
              children: [
                for (var i = 0; i < 40; i++)
                  SizedBox(
                    key: ValueKey('row-$i'),
                    height: 80,
                    child: Row(
                      children: [
                        Text('Item $i'),
                        IconButton(
                          icon: const Icon(Icons.star),
                          onPressed: () => setState(() => note = 'starred $i'),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
''';

/// The two unhappy shapes: a screen holding a spinner, where the settle
const _unhappySource = r'''
import 'package:flutter/material.dart';
import 'package:flutterware/flutter_test.dart';

void main() {
  scenario('Spinning', (s) async {
    await s.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: Column(children: [Text('Loading'), CircularProgressIndicator()]),
      ),
    ));
    await s.screen('still going');
  });

  scenario('Broken', (s) async {
    await s.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('Checkout'))),
    );
    await s.split({
      'by card': () async {
        await s.tap('Pay now');
      },
    });
  });
}
''';

/// A scenario that never returns, and one declared after it that must not run.
const _hangingSource = r'''
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutterware/flutter_test.dart';

void main() {
  scenario(
    'Never returns',
    // Two seconds rather than the 30-second default: the test asserts that
    // the deadline fires, not how patient it is.
    timeout: const Timeout(Duration(seconds: 2)),
    (s) async {
      await s.pumpWidget(const SizedBox.shrink());
      // Real async that no pump — and no clock — will ever complete.
      await s.tester.runAsync(() => Completer<void>().future);
    },
  );

  scenario('After the hang', (s) async {
    await s.pumpWidget(const SizedBox.shrink());
  });
}
''';

/// Prints the app's own view of the axes: logical size, pixel ratio, the top
/// safe area, the platform locale, brightness, and 10 through the text
/// scaler.
const _probeSource = r'''
import 'package:flutter/material.dart';
import 'package:flutterware/flutter_test.dart';

void main() {
  scenario('Probe', (s) async {
    await s.tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              var media = MediaQuery.of(context);
              var locale = View.of(context).platformDispatcher.locale;
              return Text(
                '${media.size.width.round()}x${media.size.height.round()} '
                '${media.devicePixelRatio} '
                '${media.padding.top} '
                '${locale.toLanguageTag()} '
                '${media.platformBrightness} '
                '${media.textScaler.scale(10)} '
                '${media.boldText}',
              );
            },
          ),
        ),
      ),
    );
    await s.screen('probe');
  });
}
''';
