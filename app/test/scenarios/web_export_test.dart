import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware/plugins.dart';
// ignore: implementation_imports
import 'package:flutterware/src/log_client.dart';
import 'package:flutterware_app/src/context.dart';
import 'package:flutterware_app/src/plugins/native/scenarios_core.dart';
import 'package:flutterware_app/src/plugins/native/scenarios_results.dart';
import 'package:flutterware_app/src/plugins/plugin_host.dart';
import 'package:flutterware_app/src/scenarios/web_export.dart';
import 'package:flutterware_app/src/scenarios/web_export_dialog.dart';
import 'package:flutterware_app/src/scenarios/web_report.dart';
import 'package:flutterware_app/src/shell/workspace.dart';
import 'package:flutterware_app/src/shell/worktree.dart';
import 'package:flutterware_app/src/utils/flutter_sdk.dart';
import 'package:flutterware_app/src/utils/viewer_bundle.dart';
import 'package:path/path.dart' as p;

/// What an exported page is made of.
///
/// The viewer compile is stubbed — it is `flutter build web` on our own
/// sources, and whether it succeeds is a question for the analyzer and for the
/// build itself. Everything after it is what an export actually *is*: the
/// artifacts copied in, the paths rewritten to reach them from the page, and
/// the report readable back into the same classes the panel draws.
void main() {
  late Directory root;
  late Directory viewer;

  setUp(() {
    root = Directory.systemTemp.createTempSync('fw_scenario_export_test');
    // A stand-in for the compiled bundle. `index.html` carries the base href
    // the tool would have written.
    viewer = Directory(
      ViewerBundle(
        flutterExecutable: '/none/flutter',
        appToolRoot: p.join(root.path, 'app'),
      ).viewerDir,
    )..createSync(recursive: true);
    File(p.join(viewer.path, 'index.html')).writeAsStringSync(
      '<!DOCTYPE html><html><head><base href="/"></head><body></body></html>',
    );
    File(p.join(viewer.path, 'main.dart.js')).writeAsStringSync('// viewer');
    Directory(p.join(viewer.path, 'assets')).createSync();
    File(p.join(viewer.path, 'assets', 'FontManifest.json'))
        .writeAsStringSync('[]');
  });

  tearDown(() => root.deleteSync(recursive: true));

  ScenarioWebExporter exporter() => ScenarioWebExporter(
    flutterExecutable: '/none/flutter',
    appToolRoot: p.join(root.path, 'app'),
    worktreeRoot: root.path,
  )..debugCompile = (_) async => 0;

  /// Writes a step's artifacts where the harness would have, and returns the
  /// step naming them the way a run does — worktree-relative.
  ScenarioRunStep step(
    int index, {
    String name = 'shot',
    bool events = true,
    int frames = 0,
  }) {
    var dir = Directory(p.join(root.path, 'build', 'runs', 'A'))
      ..createSync(recursive: true);
    var base = '$index-$name';
    File(p.join(dir.path, '$base.png')).writeAsBytesSync([1, 2, 3, index]);
    File(p.join(dir.path, '$base.tree.json'))
        .writeAsStringSync('{"name":"Root$index"}');
    File(p.join(dir.path, '$base.semantics.json'))
        .writeAsStringSync('{"label":"hello"}');
    if (events) {
      File(p.join(dir.path, '$base.events.json'))
          .writeAsStringSync('[{"title":"tapped"}]');
    }
    if (frames > 0) {
      var recording = Directory(p.join(dir.path, '$base.frames'))
        ..createSync(recursive: true);
      for (var frame = 0; frame < frames; frame++) {
        File(p.join(recording.path, '${frame.toString().padLeft(4, '0')}.png'))
            .writeAsBytesSync([frame]);
      }
    }
    var relative = p.join('build', 'runs', 'A', base);
    return ScenarioRunStep(
      position: '#$index',
      verb: 'tap',
      target: '"Add"',
      frames: frames > 0 ? '$relative.frames' : null,
      frameCount: frames > 0 ? frames : null,
      frameWidth: frames > 0 ? 195 : null,
      frameHeight: frames > 0 ? 422 : null,
      frameIntervalMs: frames > 0 ? 33 : null,
      index: index,
      auto: false,
      name: name,
      image: '$relative.png',
      format: 'png',
      width: 390,
      height: 844,
      tree: '$relative.tree.json',
      semantics: '$relative.semantics.json',
      events: events ? '$relative.events.json' : null,
      eventCount: events ? 1 : null,
      texts: const ['hello'],
      address: 'fw://w/scenarios/./A/$index',
      root: root.path,
    );
  }

  ScenarioWebReport report(List<ScenarioRunStep> steps, {bool ok = true}) =>
      ScenarioWebReport(
        title: 'example',
        generated: DateTime.utc(2026, 8, 11, 15),
        run: ScenarioRunResult(
          packages: [
            ScenarioRunPackage(
              path: '.',
              output: p.join(root.path, 'build', 'runs'),
              scenarios: [
                ScenarioRunOutcome(
                  file: 'test/scenarios/a_test.dart',
                  name: 'A',
                  ok: ok,
                  device: 'iphone-13',
                  steps: steps,
                ),
              ],
            ),
          ],
        ),
      );

  String output() => p.join(root.path, 'build', 'scenarios', 'web');

  Map<String, Object?> readReport() => (jsonDecode(
    File(p.join(output(), scenarioWebReportFile)).readAsStringSync(),
  ) as Map).cast<String, Object?>();

  test(
    'every artifact is copied in and every path points at the copy',
    () async {
      var written = await exporter().export(
        report: report([step(1), step(2, name: 'Cart')]),
        output: output(),
      );

      // Four per step: the frame, the tree, the semantics and the events. The
      // count is the assertion that used to be zero — the collector walked the
      // envelope instead of the run inside it and copied nothing at all, while
      // reporting a perfectly successful export.
      expect(written.artifacts, 8);
      expect(written.steps, 2);
      expect(written.scenarios, 1);

      var parsed = ScenarioWebReport.fromJson(readReport());
      var steps = parsed.run.packages.single.scenarios.single.steps;
      expect(steps, hasLength(2));
      for (var step in steps) {
        for (var path in [
          step.image!,
          step.tree!,
          step.semantics!,
          step.events!,
        ]) {
          // Relative, and reachable from the page rather than from a worktree
          // the reader does not have.
          expect(p.isAbsolute(path), isFalse, reason: path);
          expect(path, startsWith('${ScenarioWebExporter.artifactsDir}/'));
          expect(
            File(p.join(output(), path)).existsSync(),
            isTrue,
            reason: path,
          );
        }
      }
      // And the page itself came along.
      expect(File(p.join(output(), 'main.dart.js')).existsSync(), isTrue);
      expect(
        File(p.join(output(), 'assets', 'FontManifest.json')).existsSync(),
        isTrue,
      );
    },
  );

  test('the report reads back into the classes the panel draws', () async {
    await exporter().export(report: report([step(1)]), output: output());

    var parsed = ScenarioWebReport.fromJson(readReport());
    expect(parsed.title, 'example');
    expect(parsed.generated, DateTime.utc(2026, 8, 11, 15));
    var outcome = parsed.run.packages.single.scenarios.single;
    expect(outcome.name, 'A');
    expect(outcome.device, 'iphone-13');
    expect(outcome.ok, isTrue);
    var step0 = outcome.steps.single;
    expect(step0.index, 1);
    expect(step0.position, '#1');
    expect(step0.name, 'shot');
    // The transition that produced the step, which is what labels the arrow
    // into it — a page that could not parse the verb back would be a page of
    // unlabelled arrows.
    expect(step0.action, 'tap "Add"');
    expect(step0.width, 390);
    expect(step0.texts, ['hello']);
    expect(step0.hasEvents, isTrue);
    // Nobody's checkout: a step parsed out of a report has no worktree behind
    // it, and the artifacts source it is drawn through supplies the base.
    expect(step0.root, isEmpty);
  });

  test(
    'a step whose artifact has gone keeps its name and is not copied',
    () async {
      var missing = step(1, events: false);
      var written = await exporter().export(
        report: report([missing]),
        output: output(),
      );

      // Three, not four: there was no events file to copy.
      expect(written.artifacts, 3);
      var step0 = ScenarioWebReport.fromJson(readReport())
          .run
          .packages
          .single
          .scenarios
          .single
          .steps
          .single;
      expect(step0.events, isNull);
    },
  );

  test('a second export does not leave the first one behind', () async {
    await exporter().export(
      report: report([step(1), step(2, name: 'Cart')]),
      output: output(),
    );
    expect(
      Directory(p.join(output(), ScenarioWebExporter.artifactsDir, 's0'))
          .listSync(),
      hasLength(8),
    );

    // The same page, from a run with one step. Merged into, the deleted
    // scenario's screenshots would stay in the tree with nothing linking to
    // them and nothing ever removing them.
    await exporter().export(report: report([step(1)]), output: output());
    expect(
      Directory(p.join(output(), ScenarioWebExporter.artifactsDir, 's0'))
          .listSync(),
      hasLength(4),
    );
  });

  test('a recorded transition is left behind, fields and all', () async {
    var written = await exporter().export(
      report: report([step(1, frames: 3)]),
      output: output(),
    );

    // The four files of the step, and not one frame: a recording is the
    // bulkiest thing a run produces and a page is a thing people download.
    expect(written.artifacts, 4);

    var step0 = ScenarioWebReport.fromJson(readReport())
        .run
        .packages
        .single
        .scenarios
        .single
        .steps
        .single;
    // Not merely uncopied — unmentioned. A step that kept its frame fields
    // would put a play button on the page that fetches nothing.
    expect(step0.hasMotion, isFalse);
    expect(step0.frames, isNull);
    expect(step0.framePaths, isEmpty);
    expect(step0.frameIntervalMs, isNull);
    expect(readReport().toString(), isNot(contains('frameCount')));
  });

  test('the page resolves against its own URL unless told otherwise', () async {
    await exporter().export(report: report([step(1)]), output: output());

    expect(
      File(p.join(output(), 'index.html')).readAsStringSync(),
      contains('<base href="./">'),
    );
  });

  test('the base href is rewritten rather than recompiled', () async {
    await exporter().export(
      report: report([step(1)]),
      output: output(),
      baseHref: '/scenarios/',
    );

    expect(
      File(p.join(output(), 'index.html')).readAsStringSync(),
      contains('<base href="/scenarios/">'),
    );
  });

  test('a viewer that will not compile says whose fault it is', () async {
    var subject = ScenarioWebExporter(
      flutterExecutable: '/none/flutter',
      appToolRoot: p.join(root.path, 'app'),
      worktreeRoot: root.path,
    )..debugCompile = (_) async => 1;

    await expectLater(
      subject.export(report: report([step(1)]), output: output()),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          allOf(contains('not in your project'), contains('viewer')),
        ),
      ),
    );
  });

  group('the command the dialog shows', () {
    String command({
      String package = '.',
      bool nameThePackage = false,
      String output = '',
      String baseHref = '',
      bool offline = false,
    }) => scenarioWebExportCommand(
      pluginId: scenariosPluginId,
      package: package,
      nameThePackage: nameThePackage,
      output: output,
      baseHref: baseHref,
      offline: offline,
    );

    ScenariosCore core() {
      var worktree = Worktree(path: root.path);
      return ScenariosCore(
        PluginHost(
          id: scenariosPluginId,
          label: 'Scenarios',
          worktree: worktree,
          workspace: Workspace(
            root: worktree.path,
            declared: [Pkg('.')],
            discovered: const ['.'],
            appContext: AppContext(logger: LogClient.print()),
            flutterSdk: FlutterSdkPath('/tmp/flutter'),
          ),
          config: const {
            'packages': [
              {'path': '.'},
            ],
          },
        ),
      );
    }

    test('the bare form names the plugin the way the CLI resolves it', () {
      // `fw` matches on the last dotted segment, not the full id.
      expect(command(), 'dart run flutterware run scenarios export');
    });

    test('the default output is left off', () {
      expect(
        command(output: ScenarioWebExporter.defaultOutput),
        isNot(contains('--output')),
      );
      expect(command(output: 'docs/flows'), contains('--output=docs/flows'));
    });

    test('a path with a space is quoted', () {
      expect(
        command(output: 'my pages/web'),
        contains("--output='my pages/web'"),
      );
    });

    test('every flag it prints is one the action declares', () {
      var action = core().report.actions.firstWhere(
        (a) => a.id == webExportActionId,
      );
      var declared = {for (var parameter in action.parameters) parameter.id};

      var printed = command(
        package: 'packages/ui',
        nameThePackage: true,
        output: 'docs/flows',
        baseHref: '/scenarios/',
        offline: true,
      );
      var flags = RegExp(r'--([a-z-]+)=')
          .allMatches(printed)
          .map((m) => m.group(1)!)
          .toSet();

      expect(flags, isNotEmpty);
      // A flag renamed on the action and not here is a command that fails the
      // moment somebody copies it.
      expect(declared, containsAll(flags));
    });

    test('the action it names exists', () {
      expect(
        core().report.actions.map((a) => a.id),
        contains(webExportActionId),
      );
    });
  });
}
