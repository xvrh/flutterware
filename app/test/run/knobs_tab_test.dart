import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware_app/src/plugins/native/run_results.dart';
import 'package:flutterware_app/src/run/handle.dart';
import 'package:flutterware_app/src/run/knobs_tab.dart';

/// The editor that makes the 262ms reachable: the launch form lives on the New
/// run page, and the only other way back to it is Stop — which is a rebuild.
void main() {
  RunHandle handleWith(Map<String, String> knobs) => RunHandle(
    worktree: '/w',
    worktreeName: 'wt',
    device: 'macos',
    entrypoint: 'lib/main.dart',
    entrypointName: 'App',
    package: 'app',
    launcherPid: 1,
    knobs: knobs,
    startedAt: DateTime(2026),
  );

  var knobs = [
    RunKnobEntry(name: 'apiHost', kind: 'string', defaultValue: 'localhost'),
    RunKnobEntry(
      name: 'backend',
      kind: 'picker',
      defaultValue: 'dev',
      options: const ['dev', 'staging', 'prod'],
    ),
  ];

  Future<List<Map<String, String>>> pump(
    WidgetTester tester, {
    RunHandle? handle,
    List<RunKnobEntry>? offered,
    String? unknown,
  }) async {
    var applied = <Map<String, String>>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: KnobsTab(
            handle: handle ?? handleWith(const {}),
            knobs: offered ?? knobs,
            unknown: unknown,
            onApply: (values) async => applied.add(values),
          ),
        ),
      ),
    );
    return applied;
  }

  testWidgets('draws each knob for the kind its parameter declares', (
    tester,
  ) async {
    await pump(tester);

    expect(find.text('apiHost'), findsOneWidget);
    expect(find.byType(TextFormField), findsOneWidget);
    // An enum is a dropdown of its own constants rather than a field somebody
    // can misspell into.
    expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
  });

  testWidgets('will not restart until something has actually changed', (
    tester,
  ) async {
    await pump(tester);

    var button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);
    // The cost is stated only once there is something to pay it for.
    expect(find.textContaining('starts from its first screen'), findsNothing);
  });

  testWidgets('an edit enables the button and says what a restart costs', (
    tester,
  ) async {
    var applied = await pump(tester);

    await tester.enterText(find.byType(TextFormField), 'staging.example.com');
    await tester.pump();

    expect(find.textContaining('starts from its first screen'), findsOneWidget);
    expect(applied, isEmpty, reason: 'not applied until the button is pressed');

    await tester.tap(find.byType(FilledButton));
    await tester.pump();

    expect(applied.single, {'apiHost': 'staging.example.com'});
  });

  testWidgets('starts from what the run is actually holding', (tester) async {
    // A knob whose current value the tool had forgotten would be a field you
    // can only overwrite blind.
    await pump(tester, handle: handleWith({'apiHost': 'already.set'}));

    expect(find.text('already.set'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
  });

  testWidgets('an entry point taking none says so rather than sitting blank', (
    tester,
  ) async {
    await pump(tester, offered: const []);

    expect(find.textContaining('takes no knobs'), findsOneWidget);
    // And teaches the one thing that would make it non-empty.
    expect(find.textContaining('optional named parameters'), findsOneWidget);
  });

  testWidgets('a run it cannot read says why, not "takes no knobs"', (
    tester,
  ) async {
    // Another checkout of the same repo has the same package paths and the
    // same entry point names, so every lookup succeeds — against source that
    // may be on a different branch. Claiming the app takes none would be a
    // statement about somebody else's code.
    await pump(
      tester,
      offered: const [],
      unknown: 'This run belongs to feature-x.',
    );

    expect(find.text('This run belongs to feature-x.'), findsOneWidget);
    expect(find.textContaining('takes no knobs'), findsNothing);
    // Nothing to edit, so nothing that looks editable.
    expect(find.byType(FilledButton), findsNothing);
  });

  test('a copy keeps the knobs, or a launch forgets them seconds later', () {
    // `refreshFromLog` rewrites the handle the moment the launcher reports a VM
    // service — a few seconds after every launch. A copy that dropped `knobs`
    // left the field empty in the cockpit while the app was plainly running
    // with values, which is exactly what the end-to-end showed.
    var handle = RunHandle(
      worktree: '/w',
      worktreeName: 'wt',
      device: 'macos',
      entrypoint: 'lib/main.dart',
      launcherPid: 1,
      defines: const {'FW_MARKER': 'x'},
      knobs: const {'apiHost': 'set.example.com'},
      startedAt: DateTime(2026),
    );

    var refreshed = handle.withService(vmService: 'ws://127.0.0.1:1/ws');

    expect(refreshed.knobs, {'apiHost': 'set.example.com'});
    expect(refreshed.defines, {'FW_MARKER': 'x'});
    expect(handle.withKnobs(const {'apiHost': 'other'}).defines, {
      'FW_MARKER': 'x',
    });
  });
}
