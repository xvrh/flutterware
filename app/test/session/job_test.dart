import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware/plugins.dart';
// ignore: implementation_imports
import 'package:flutterware/src/log_client.dart';
import 'package:flutterware_app/src/context.dart';
import 'package:flutterware_app/src/plugins/plugin_core.dart';
import 'package:flutterware_app/src/session/job.dart';
import 'package:flutterware_app/src/session/session.dart';
import 'package:flutterware_app/src/shell/workspace.dart';
import 'package:flutterware_app/src/shell/worktree.dart';
import 'package:flutterware_app/src/utils/flutter_sdk.dart';

/// `Session.invoke` is the single door every renderer runs an action through,
/// so what it guarantees is what the CLI, MCP and the GUI can each rely on
/// without implementing it themselves.
///
/// Built over fake cores rather than the real repo: none of this needs a
/// Flutter SDK, a config file or a plugin that does anything.
const _worktree = Worktree(path: '/tmp/wt', branch: 'feature/x');

/// A result whose answer is data, carrying one file worth looking at.
class _DataCarryingArtifact implements ProducesArtifacts {
  _DataCarryingArtifact(this.screenshot);

  final Artifact screenshot;

  @override
  List<Artifact> get artifacts => [screenshot];
}

class _FakeCore extends PluginCore {
  _FakeCore(super.host, {this.result, this.throws});

  final Object? result;
  final Error? throws;

  var calls = 0;

  @override
  PluginReport get report => PluginReport(
    id: host.id,
    label: host.label,
    actions: const [PluginAction('go', 'Go')],
  );

  @override
  Future<Object?> invoke(
    String actionId, {
    Map<String, Object?> arguments = const {},
  }) async {
    calls++;
    if (actionId != 'go') {
      return super.invoke(actionId, arguments: arguments);
    }
    if (throws case var error?) throw error;
    return result;
  }
}

Session _session(Map<String, PluginCoreFactory> cores) => Session.resolved(
  worktree: _worktree,
  workspace: Workspace(
    root: _worktree.path,
    declared: const [Pkg('.')],
    discovered: const ['.'],
    appContext: AppContext(logger: LogClient.print()),
    flutterSdk: FlutterSdkPath('/tmp/flutter'),
  ),
  manifest: PluginManifest([
    for (var id in cores.keys)
      PluginDeclaration(id: id, label: id.split('.').last),
  ]),
  registry: PluginCoreRegistry(cores),
);

Session _one({Object? result, Error? throws}) => _session({
  'a.one': (host) => _FakeCore(host, result: result, throws: throws),
});

void main() {
  test('a job carries the resolved plugin id, not what the caller typed', () {
    var job = _one().invoke('one', 'go');
    expect(job.plugin, 'a.one');
    expect(job.action, 'go');
  });

  test('job ids are unique', () {
    var session = _one();
    expect(
      session.invoke('one', 'go').id,
      isNot(session.invoke('one', 'go').id),
    );
  });

  test('an unknown plugin throws — nothing ran, so there is no job', () {
    var session = _one();
    expect(
      () => session.invoke('ghost', 'go'),
      throwsA(
        isA<SessionException>().having(
          (e) => e.message,
          'message',
          allOf(contains('ghost'), contains('a.one')),
        ),
      ),
    );
  });

  test('an unknown action is a failed job, not a throw', () async {
    // The line Address draws: the framework owns the namespace up to the
    // plugin, the plugin owns everything past it. A bad action is a real
    // invocation of a real plugin that came back with an error.
    var result = await _one().invoke('one', 'nope').done;
    expect(result.ok, isFalse);
    expect(result.error, isA<ArgumentError>());
  });

  test('a throwing action completes rather than escaping', () async {
    var result = await _one(throws: StateError('boom'))
        .invoke('one', 'go')
        .done;
    expect(result.ok, isFalse);
    expect(result.error, isA<StateError>());
    expect(result.stackTrace, isNotNull);
    // A failed run is still a run: it has a duration, and it will have a line
    // in the log.
    expect(result.duration, greaterThanOrEqualTo(Duration.zero));
  });

  test('an artifact result is collected, not just returned', () async {
    var artifact = Artifact(
      kind: 'image/png',
      path: '.flutterware/artifacts/x.png',
      address: Address(worktree: 'wt', plugin: 'a.one', segments: const ['x']),
    );
    var result = await _one(result: artifact).invoke('one', 'go').done;

    expect(result.ok, isTrue);
    expect(result.artifacts, [artifact]);
    expect(result.value, artifact);
  });

  test('a plain result is left alone', () async {
    var result = await _one(result: 'went').invoke('one', 'go').done;
    expect(result.value, 'went');
    expect(result.artifacts, isEmpty);
  });

  test('a data result declares the picture it carries', () async {
    // The route a result takes when its *answer* is data and a file is one
    // field of it — `inspect --screenshot`, a scenario run's failing frame.
    // Without it a surface that can render a picture never finds one, and an
    // agent that asked to see something is handed a path instead. Which is what
    // `inspect` did: it held an Artifact in a field and implemented nothing.
    var artifact = Artifact(
      kind: 'image/png',
      path: 'build/shot.png',
      address: Address(worktree: 'wt', plugin: 'a.one', segments: const ['x']),
    );
    var result = await _one(result: _DataCarryingArtifact(artifact))
        .invoke('one', 'go')
        .done;

    expect(result.artifacts, [artifact]);
    expect(
      result.value,
      isA<_DataCarryingArtifact>(),
      reason: 'the data is still the answer; the artifact is the footnote',
    );
  });

  group('events', () {
    test('replay what a subscriber missed', () async {
      // Nobody can subscribe before invoke returns, so a stream that only
      // carried what happened next would never deliver JobStarted at all.
      var job = _one(result: 'went').invoke('one', 'go');
      await job.done;

      var events = await job.events.toList();
      expect(events.map((e) => e.runtimeType), [JobStarted, JobFinished]);
      expect((events.first as JobStarted).at, job.startedAt);
      expect((events.last as JobFinished).result.value, 'went');
    });

    test('an artifact is announced before the job finishes', () async {
      var artifact = Artifact(
        kind: 'image/png',
        path: 'x.png',
        address: Address(
          worktree: 'wt',
          plugin: 'a.one',
          segments: const ['x'],
        ),
      );
      var job = _one(result: artifact).invoke('one', 'go');
      await job.done;

      expect(await job.events.toList(), [
        isA<JobStarted>(),
        isA<JobArtifactProduced>(),
        isA<JobFinished>(),
      ]);
    });

    test('a live subscriber sees the end without a duplicate start', () async {
      var job = _one(result: 'went').invoke('one', 'go');
      var seen = <JobEvent>[];
      var subscription = job.events.listen(seen.add);

      await job.done;
      await pumpEventQueue();
      await subscription.cancel();

      expect(seen.map((e) => e.runtimeType), [JobStarted, JobFinished]);
    });

    test('the stream closes when the job does', () async {
      var job = _one().invoke('one', 'go');
      await job.events.drain<void>();
      expect(job.isFinished, isTrue);
    });
  });

  test('the core is invoked exactly once', () async {
    var session = _session({'a.one': (host) => _FakeCore(host)});
    await session.invoke('one', 'go').done;
    expect((session.cores.single as _FakeCore).calls, 1);
  });

  test('arguments reach the core unchanged', () async {
    Map<String, Object?>? seen;
    var session = _session({
      'a.one': (host) => _RecordingCore(host, (args) => seen = args),
    });
    await session.invoke('one', 'go', arguments: {'k': 'v'}).done;
    expect(seen, {'k': 'v'});
  });
}

class _RecordingCore extends PluginCore {
  _RecordingCore(super.host, this.onInvoke);

  final void Function(Map<String, Object?>) onInvoke;

  // Declared, because declared is what makes an action invocable and a
  // parameter acceptable. This used to answer `go` while declaring nothing,
  // which is the shape that let `run`'s undeclared `screenshot` take an
  // unchecked `--output` — see `session/undeclared_action_test.dart`. What
  // this test is *about* is that the arguments arrive unchanged, so it keeps
  // the argument and gains the declaration.
  @override
  PluginReport get report => PluginReport(
    id: host.id,
    label: host.label,
    actions: const [
      PluginAction('go', 'Go', parameters: [ActionParameter('k', 'K')]),
    ],
  );

  @override
  Future<Object?> invoke(
    String actionId, {
    Map<String, Object?> arguments = const {},
  }) async {
    onInvoke(arguments);
    return null;
  }
}
