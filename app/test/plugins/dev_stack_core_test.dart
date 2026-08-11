import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
// ignore: implementation_imports
import 'package:flutterware/src/log_client.dart';
import 'package:flutterware/plugins.dart';
import 'package:flutterware_app/src/context.dart';
import 'package:flutterware_app/src/plugins/native/dev_stack_core.dart';
import 'package:flutterware_app/src/plugins/native/dev_stack_results.dart';
import 'package:flutterware_app/src/plugins/plugin_host.dart';
import 'package:flutterware_app/src/shell/workspace.dart';
import 'package:flutterware_app/src/shell/worktree.dart';
import 'package:flutterware_app/src/utils/flutter_sdk.dart';
import 'package:flutterware_app/src/utils/run_dir.dart';

/// The core against a scripted `runProcess`, which is the seam that keeps this
/// from needing docker. What is asserted is what `fw`, an agent and the sidebar
/// all read — [PluginReport] and `invoke` — because the panel draws the same
/// core and a test against the widget would only be testing the widget.
void main() {
  late Directory runDir;
  late Directory project;
  late List<List<String>> ran;
  late Map<String, ProcessResult> responses;

  /// The next result for a command, keyed by its first two words so a test can
  /// script `up` and `doctor` differently.
  ProcessResult resultFor(List<String> command) =>
      responses[command.take(2).join(' ')] ?? ProcessResult(0, 0, '', '');

  /// Every core gets the same scripted process, set per instance.
  DevStackCore coreWith(Map<String, Object?> config) =>
      DevStackCore(
          PluginHost(
            id: devStackPluginId,
            label: 'Dev stack',
            worktree: Worktree(path: project.path),
            workspace: Workspace(
              root: project.path,
              declared: [],
              discovered: [],
              appContext: AppContext(logger: LogClient.print()),
              flutterSdk: FlutterSdkPath('/tmp/flutter'),
            ),
            config: config,
          ),
        )
        ..runProcess = (command, {workingDirectory}) async {
          ran.add([
            ...command,
            if (workingDirectory != null) '@$workingDirectory',
          ]);
          return resultFor(command);
        };

  /// A stack delegated to a project's own CLI, as `DevStack.background(...)`
  /// emits it.
  Map<String, Object?> localEnvConfig() => DevStack.background(
    workingDirectory: 'packages/server',
    probe: Probe.exitCode(['stack', 'doctor']),
    start: ['stack', 'up'],
    stop: ['stack', 'down'],
    stopIsDestructive: true,
    commands: [
      StackCommand('logs', 'Logs', ['stack', 'logs']),
      StackCommand('restart', 'Restart', [
        'stack',
        'restart',
      ], argument: 'service'),
    ],
  ).config;

  setUp(() {
    runDir = Directory.systemTemp.createTempSync('fw-stack-run-');
    project = Directory.systemTemp.createTempSync('fw-stack-project-');
    ran = [];
    responses = {};
    DevStackCore.runDirProvider = () => runDir.path;
  });

  tearDown(() {
    DevStackCore.runDirProvider = flutterwareRunDir;
    for (var dir in [runDir, project]) {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    }
  });

  group('the config a project writes', () {
    test('survives the trip through the manifest', () {
      var core = coreWith(localEnvConfig());
      expect(core.declaredProbeCommand, 'stack doctor');
      expect(core.declaredDirectory, 'packages/server');
      expect(core.stopIsDestructive, isTrue);
      expect(core.canControl, isTrue);
      expect([for (var c in core.commands) c.id], ['logs', 'restart']);
      expect(core.pollInterval, const Duration(seconds: 10));
      core.dispose();
    });

    test('resolves the working directory against the worktree', () {
      var core = coreWith(localEnvConfig());
      expect(core.workingDirectory, '${project.path}/packages/server');
      core.dispose();
    });
  });

  group('computeAll', () {
    test('spawns nothing — the budget is a file read', () async {
      var core = coreWith(localEnvConfig());
      await core.computeAll();
      expect(ran, isEmpty);
      expect(core.report.status.message, 'not checked');
      core.dispose();
    });

    test('reads back what a previous probe cached', () async {
      var first = coreWith(localEnvConfig());
      responses['stack doctor'] = ProcessResult(0, 0, 'All checks passed.', '');
      await first.refresh();
      first.dispose();

      var second = coreWith(localEnvConfig());
      await second.computeAll();
      expect(second.reading.state, StackState.up);
      expect(second.reading.detail, 'All checks passed.');
      // The point of the cache: a cold read says something true and spawns
      // nothing to do it.
      expect(ran.length, 1);
      second.dispose();
    });
  });

  group('the exit-code probe', () {
    test('zero is up, and the last line becomes the detail', () async {
      var core = coreWith(localEnvConfig());
      responses['stack doctor'] = ProcessResult(
        0,
        0,
        'Doctor for the dev stack\n  docker … OK\nAll checks passed.',
        '',
      );
      var reading = await core.refresh();
      expect(reading.state, StackState.up);
      expect(reading.detail, 'All checks passed.');
      expect(core.report.status.tone, Tone.good);
      core.dispose();
    });

    test('non-zero is down', () async {
      var core = coreWith(localEnvConfig());
      responses['stack doctor'] = ProcessResult(0, 1, '2 check(s) failed.', '');
      expect((await core.refresh()).state, StackState.down);
      expect(core.report.status.message, 'down');
      core.dispose();
    });

    test(
      'strips the colour codes a health check writes for a terminal',
      () async {
        var core = coreWith(localEnvConfig());
        responses['stack doctor'] = ProcessResult(
          0,
          0,
          '\x1B[32mAll checks passed.\x1B[0m',
          '',
        );
        expect((await core.refresh()).detail, 'All checks passed.');
        core.dispose();
      },
    );

    test('a command that cannot be spawned is unavailable, not down', () async {
      var core = coreWith(localEnvConfig())
        ..runProcess = (command, {workingDirectory}) async =>
            throw const ProcessException('stack', [], 'No such file');
      var reading = await core.refresh();
      // The distinction the five-state design exists for: a probe that could
      // not run says nothing about whether the stack is up.
      expect(reading.state, StackState.unavailable);
      expect(reading.failure, contains('No such file'));
      expect(core.report.status.tone, Tone.error);
      core.dispose();
    });
  });

  group('the JSON probe', () {
    Map<String, Object?> jsonConfig() => DevStack.background(
      probe: Probe.json(['stack', 'doctor']),
      start: ['stack', 'up'],
      stop: ['stack', 'down'],
    ).config;

    test('carries services and their ports through', () async {
      var core = coreWith(jsonConfig());
      responses['stack doctor'] = ProcessResult(0, 0, '''
        {"state":"up","detail":"slot 8200-8208",
         "services":[{"name":"postgres","port":8200,"state":"up"},
                     {"name":"identity","port":8201,"state":"starting"}]}
      ''', '');
      var reading = await core.refresh();
      expect(reading.state, StackState.up);
      expect(reading.detail, 'slot 8200-8208');
      expect(reading.services.map((s) => s.name), ['postgres', 'identity']);
      expect(reading.services.first.port, 8200);
      expect(reading.services.last.state, StackState.starting);
      core.dispose();
    });

    test('ignores whatever the command wrote to stderr', () async {
      // Found by pointing the example project's declaration at a Dart script:
      // `dart` announces `Running build hooks...` on stderr, and folding that
      // in made every probe unparseable. Almost nothing that prints structured
      // output has stderr to itself — docker writes deprecation warnings there,
      // a wrapper's `set -x` writes every line it runs — so a probe that reads
      // both is one that works until a tool starts mentioning something.
      var core = coreWith(jsonConfig());
      responses['stack doctor'] = ProcessResult(
        0,
        0,
        '{"state":"up","detail":"4 containers"}',
        'Running build hooks...\nnote: using cached layer',
      );
      var reading = await core.refresh();
      expect(reading.state, StackState.up);
      expect(reading.detail, '4 containers');
      core.dispose();
    });

    test("keeps the command's own words when it did not print JSON", () async {
      var core = coreWith(jsonConfig());
      responses['stack doctor'] = ProcessResult(
        0,
        1,
        '',
        'Cannot connect to the Docker daemon.',
      );
      var reading = await core.refresh();
      expect(reading.state, StackState.unavailable);
      // Not "printed something that is not JSON": that buries the sentence
      // explaining the problem under a complaint about the format.
      expect(reading.failure, 'Cannot connect to the Docker daemon.');
      core.dispose();
    });

    test('reports unavailable when it cannot say what it is up to', () async {
      var core = coreWith(jsonConfig());
      responses['stack doctor'] = ProcessResult(0, 0, 'not json at all', '');
      var reading = await core.refresh();
      expect(reading.state, StackState.unavailable);
      // Quoted rather than paraphrased — whatever it said is more use than a
      // complaint about the format.
      expect(reading.failure, 'not json at all');
      core.dispose();
    });

    test('falls back to naming the format when it said nothing', () async {
      var core = coreWith(jsonConfig());
      responses['stack doctor'] = ProcessResult(0, 1, '', '');
      var reading = await core.refresh();
      expect(reading.state, StackState.unavailable);
      expect(reading.failure, contains('not JSON'));
      core.dispose();
    });
  });

  group('start and stop', () {
    test('run the declared command and re-probe', () async {
      var core = coreWith(localEnvConfig());
      responses['stack doctor'] = ProcessResult(0, 0, 'All checks passed.', '');
      var result = await core.start();
      expect(result.ok, isTrue);
      expect(result.command, 'stack up');
      // Up, then the probe — the caller asked whether it came up, not whether
      // the command exited.
      expect(ran.map((c) => c.take(2).join(' ')), ['stack up', 'stack doctor']);
      expect(result.reading!.state, StackState.up);
      core.dispose();
    });

    test('run in the declared working directory', () async {
      var core = coreWith(localEnvConfig());
      await core.start();
      expect(ran.first.last, '@${project.path}/packages/server');
      core.dispose();
    });

    test('refuse to overlap', () async {
      var core = coreWith(localEnvConfig());
      var completer = Completer<ProcessResult>();
      core.runProcess = (command, {workingDirectory}) => completer.future;
      var first = core.start();
      expect(core.busy, 'start');
      await expectLater(core.stop(), throwsStateError);
      completer.complete(ProcessResult(0, 0, '', ''));
      await first;
      expect(core.busy, isNull);
      core.dispose();
    });

    test(
      'a transition wins over the last reading while it is in flight',
      () async {
        var core = coreWith(localEnvConfig());
        var completer = Completer<ProcessResult>();
        core.runProcess = (command, {workingDirectory}) => completer.future;
        var pending = core.start();
        // The probe cannot see a compose project that has not finished coming up,
        // so the status must not fall back to what it last said.
        expect(core.report.status.message, 'bringing up…');
        completer.complete(ProcessResult(0, 0, '', ''));
        await pending;
        core.dispose();
      },
    );

    test(
      'a stack with no start declared says so rather than doing nothing',
      () async {
        var core = coreWith(
          DevStack.background(probe: Probe.exitCode(['check'])).config,
        );
        expect(core.canControl, isFalse);
        await expectLater(core.start(), throwsStateError);
        expect([for (var a in core.report.actions) a.id], ['status']);
        core.dispose();
      },
    );
  });

  group('actions', () {
    test('are what fw and an agent see, with stop marked destructive', () {
      var core = coreWith(localEnvConfig());
      var actions = {for (var a in core.report.actions) a.id: a};
      expect(actions.keys, ['status', 'start', 'stop', 'logs', 'restart']);
      expect(actions['stop']!.danger, isTrue);
      expect(actions['stop']!.confirm, isTrue);
      expect(actions['start']!.danger, isFalse);
      // A command with an argument declares it, so `fw run … --service=x` and a
      // GUI form are the same declaration.
      expect(actions['restart']!.parameters.single.id, 'service');
      expect(actions['logs']!.parameters, isEmpty);
      core.dispose();
    });

    test('invoke routes a declared command and appends its argument', () async {
      var core = coreWith(localEnvConfig());
      var result =
          (await core.invoke('restart', arguments: {'service': 'sync'}))!
              as DevStackRunResult;
      expect(result.command, 'stack restart sync');
      core.dispose();
    });

    test('an unknown action names what is declared', () async {
      var core = coreWith(localEnvConfig());
      await expectLater(
        core.invoke('nope'),
        throwsA(
          isA<ArgumentError>().having(
            (e) => '$e',
            'message',
            contains('status, start, stop, logs, restart'),
          ),
        ),
      );
      core.dispose();
    });
  });

  group('teardown', () {
    test('offers a step only when there is something to tear down', () async {
      var core = coreWith(localEnvConfig());
      responses['stack doctor'] = ProcessResult(0, 1, 'down', '');
      await core.refresh();
      expect(core.report.teardown, isEmpty);

      responses['stack doctor'] = ProcessResult(0, 0, '4 containers', '');
      await core.refresh();
      var step = core.report.teardown.single;
      expect(step.id, 'stop');
      expect(step.phase, TeardownPhase.infra);
      expect(step.checked, isTrue);
      expect(step.danger, isTrue);
      // The detail is what makes the checkbox decidable.
      expect(step.detail, '4 containers · destroys the database');
      core.dispose();
    });

    test('a stack with no stop never offers one', () async {
      var core = coreWith(
        DevStack.background(probe: Probe.exitCode(['check'])).config,
      );
      await core.refresh();
      expect(core.report.teardown, isEmpty);
      core.dispose();
    });
  });

  group('watching', () {
    test('polls only while something is watching', () async {
      var core = coreWith(
        DevStack.background(
          probe: Probe.exitCode(['check']),
          poll: const Duration(milliseconds: 30),
        ).config,
      );
      expect(core.isWatching, isFalse);

      core.watch();
      expect(core.isWatching, isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 110));
      var whileWatching = ran.length;
      expect(whileWatching, greaterThan(1));

      core.unwatch();
      expect(core.isWatching, isFalse);
      await Future<void>.delayed(const Duration(milliseconds: 110));
      expect(ran.length, whileWatching);
      core.dispose();
    });

    test(
      'two surfaces share one poll, and the second release stops it',
      () async {
        var core = coreWith(
          DevStack.background(
            probe: Probe.exitCode(['check']),
            poll: const Duration(milliseconds: 30),
          ).config,
        );
        // The home screen and the panel can be mounted across one navigation;
        // the first unwatch must not stop the surface still showing.
        core.watch();
        core.watch();
        core.unwatch();
        expect(core.isWatching, isTrue);
        core.unwatch();
        expect(core.isWatching, isFalse);
        core.dispose();
      },
    );
  });
}
