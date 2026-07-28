import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware/plugins.dart';
// ignore: implementation_imports
import 'package:flutterware/src/logs/remote_log_client.dart';
import 'package:path/path.dart' as p;
import 'package:flutterware_app/src/context.dart';
import 'package:flutterware_app/src/plugins/manifest_loader.dart';
import 'package:flutterware_app/src/plugins/native_plugin.dart';
import 'package:flutterware_app/src/plugins/plugin_core.dart';
import 'package:flutterware_app/src/plugins/plugin_host.dart';
import 'package:flutterware_app/src/plugins/registry.dart';
import 'package:flutterware_app/src/plugins/worktree_session.dart';
import 'package:flutterware_app/src/shell/workspace.dart';
import 'package:flutterware_app/src/shell/worktree.dart';
import 'package:flutterware_app/src/utils/flutter_sdk.dart';

const _worktree = Worktree(path: '/tmp/wt', branch: 'feature/x');

// Workspace carries package identity only; Projects are built on first use, so
// constructing one costs nothing in a unit test.
Workspace _workspace() => Workspace(
  root: _worktree.path,
  declared: const [Pkg('.')],
  discovered: const ['.'],
  appContext: AppContext(logger: LogClient.print()),
  flutterSdk: FlutterSdkPath('/tmp/flutter'),
);

class _FakeCore extends PluginCore {
  _FakeCore(super.host, {this.status = Status.none, this.teardown = const []});

  final Status status;
  final List<TeardownStep> teardown;
  var disposed = false;
  var invoked = <String, Object?>{};

  @override
  PluginReport get report => PluginReport(
    id: host.id,
    label: host.label,
    status: status,
    teardown: teardown,
    actions: const [PluginAction('go', 'Go')],
  );

  @override
  Future<Object?> invoke(
    String actionId, {
    Map<String, Object?> arguments = const {},
  }) async {
    if (actionId != 'go') {
      return super.invoke(actionId, arguments: arguments);
    }
    invoked = arguments;
    return 'went';
  }

  void bump() => notifyChanged();

  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }
}

class _Fake extends NativePlugin<_FakeCore> {
  _Fake(super.core);

  var disposed = false;

  @override
  Widget buildPanel(BuildContext context, String? childId) => const SizedBox();

  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }
}

PluginCoreFactory _core({
  Status status = Status.none,
  List<TeardownStep> teardown = const [],
}) =>
    (host) => _FakeCore(host, status: status, teardown: teardown);

PluginManifest _manifest(
  List<String> ids, {
  Map<String, Object?> config = const {},
}) => PluginManifest([
  for (var id in ids)
    PluginDeclaration(id: id, label: id.split('.').last, config: config),
]);

/// A worktree session over fake cores, each with a panel — the arrangement the
/// shell builds, with the two registries agreeing.
WorktreeSession _session(
  Map<String, PluginCoreFactory> cores, {
  Map<String, Object?> config = const {},
  List<String>? panelsFor,
}) => WorktreeSession.resolve(
  worktree: _worktree,
  manifest: _manifest(cores.keys.toList(), config: config),
  registry: PluginRegistry({
    for (var id in panelsFor ?? cores.keys) id: panelFor<_FakeCore>(_Fake.new),
  }),
  workspace: _workspace(),
  coreRegistry: PluginCoreRegistry(cores),
);

void main() {
  group('registry', () {
    test('resolves declarations in the config file order', () {
      var session = _session({'a.two': _core(), 'a.one': _core()});
      expect(session.plugins.map((p) => p.id), ['a.two', 'a.one']);
      expect(session.session.cores.map((c) => c.id), ['a.two', 'a.one']);
    });

    test('surfaces an unknown id instead of dropping it', () {
      // "ghost" is declared but neither registry knows it.
      var ghost = WorktreeSession.resolve(
        worktree: _worktree,
        manifest: _manifest(['a.one', 'ghost']),
        registry: PluginRegistry({'a.one': panelFor<_FakeCore>(_Fake.new)}),
        workspace: _workspace(),
        coreRegistry: PluginCoreRegistry({'a.one': _core()}),
      ).plugins.last;

      expect(ghost, isA<MissingPlugin>());
      expect(ghost.core.report.status.tone, Tone.error);
      expect(ghost.core.report.view.toText(), contains('ghost'));
    });

    test('a core with no panel keeps its real report', () {
      // The GUI has no screen for it; `fw` and MCP are unaffected. Reporting
      // an error in the sidebar would hide a plugin that works.
      var session = _session({
        'a.one': _core(status: Status.warn('2 outdated')),
      }, panelsFor: const []);

      var plugin = session.plugins.single;
      expect(plugin, isA<MissingPlugin>());
      expect(plugin.core.report.status, Status.warn('2 outdated'));
    });

    test('passes declared config through to the host', () {
      PluginHost? seen;
      var session = _session(
        {
          'a.one': (host) {
            seen = host;
            return _FakeCore(host);
          },
        },
        config: {'compose': 'dev.yml', 'watch': true},
      );

      expect(session.plugins, hasLength(1));
      expect(seen!.string('compose'), 'dev.yml');
      expect(seen!.boolean('watch'), isTrue);
      expect(seen!.string('missing', 'fallback'), 'fallback');
      expect(seen!.worktree.branch, 'feature/x');
    });

    test('refuses a duplicate registration', () {
      var registry = PluginRegistry({'a.one': panelFor<_FakeCore>(_Fake.new)});
      expect(
        () => registry.register('a.one', panelFor<_FakeCore>(_Fake.new)),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('worktree session', () {
    test('closing disposes every panel and every core', () {
      var session = _session({'a.one': _core(), 'a.two': _core()});
      var plugins = session.plugins.cast<_Fake>();
      var cores = session.session.cores.cast<_FakeCore>();

      expect(plugins.every((p) => p.disposed), isFalse);
      session.dispose();
      expect(plugins.every((p) => p.disposed), isTrue);
      expect(cores.every((c) => c.disposed), isTrue);
      expect(session.isDisposed, isTrue);
    });

    test('reduces to the most severe plugin status', () {
      var session = _session({
        'a.one': _core(status: Status.good('ok')),
        'a.two': _core(status: Status.error('3 failing')),
        'a.three': _core(status: Status.warn('stack down')),
      });
      expect(session.status.tone, Tone.error);
      expect(session.status.message, '3 failing');
    });

    test('a core update notifies the session', () async {
      var session = _session({'a.one': _core()});
      var notified = 0;
      session.addListener(() => notified++);

      (session.session.cores.single as _FakeCore).bump();
      // The core coalesces bursts into one microtask, and the stream delivers
      // asynchronously; both are why the panel never marks the shell dirty
      // during a build.
      await pumpEventQueue();
      expect(notified, 1);
    });

    test('collects teardown steps in phase order', () {
      var session = _session({
        'a.one': _core(
          teardown: const [
            TeardownStep('c', 'cleanup', phase: TeardownPhase.cleanup),
          ],
        ),
        'a.two': _core(
          teardown: const [
            TeardownStep('i', 'infra', phase: TeardownPhase.infra),
            TeardownStep('a', 'apps', phase: TeardownPhase.apps),
          ],
        ),
      });
      expect(session.teardownSteps.map((s) => s.id), ['a', 'i', 'c']);
    });

    test('invoking goes through the session, not the panel', () async {
      var session = _session({'a.one': _core()});
      var result = await session
          .invoke('one', 'go', arguments: {'k': 'v'})
          .done;

      expect(result.ok, isTrue);
      expect(result.value, 'went');
      expect((session.session.cores.single as _FakeCore).invoked, {'k': 'v'});
    });
  });

  group('manifest loader', () {
    var dir = Directory.systemTemp.createTempSync('fw-manifest-test');

    tearDownAll(() => dir.deleteSync(recursive: true));

    ManifestLoader loaderReturning(ProcessResult result) => ManifestLoader(
      dartExecutable: 'dart',
      runProcess: (_, _, {workingDirectory}) async => result,
    );

    void writeConfig() {
      File('${dir.path}/$configFilePath')
        ..createSync(recursive: true)
        ..writeAsStringSync('// config');
    }

    test('returns null when the project declares no config file', () async {
      var empty = Directory.systemTemp.createTempSync('fw-no-config');
      var loader = loaderReturning(ProcessResult(0, 0, '', ''));
      expect(await loader.load(empty.path), isNull);
      empty.deleteSync();
    });

    test('parses the manifest from stdout', () async {
      writeConfig();
      var loader = loaderReturning(
        ProcessResult(
          0,
          0,
          '{"version":1,"plugins":[{"id":"a.one","label":"One"}]}',
          'Running build hooks...',
        ),
      );

      var manifest = await loader.load(dir.path);
      expect(manifest!.plugins.single.id, 'a.one');
    });

    test('reports a failing config rather than treating it as empty', () async {
      writeConfig();
      var loader = loaderReturning(ProcessResult(0, 1, '', 'boom'));
      await expectLater(
        loader.load(dir.path),
        throwsA(isA<ManifestLoadException>()),
      );

      var result = await loader.tryLoad(dir.path);
      expect(result.manifest, isNull);
      expect(result.error, contains('boom'));
    });

    test('reports a config that prints nothing', () async {
      writeConfig();
      var loader = loaderReturning(ProcessResult(0, 0, '   ', ''));
      await expectLater(
        loader.load(dir.path),
        throwsA(
          isA<ManifestLoadException>().having(
            (e) => e.message,
            'message',
            contains('Flutterware.configure'),
          ),
        ),
      );
    });
  });

  group('manifest loader caches the compiled config', () {
    late Directory dir;
    late List<List<String>> invocations;

    const manifest = '{"version":1,"plugins":[{"id":"a.one","label":"One"}]}';

    /// A loader over a resolved project, recording what it spawned. The kernel
    /// is only attempted when `package_config.json` exists, which is what
    /// keeps every other test on the `dart run` path.
    ManifestLoader loaderWith({
      int compileExit = 0,
      int kernelExit = 0,
      String dart = 'dart',
    }) => ManifestLoader(
      dartExecutable: dart,
      runProcess: (executable, arguments, {workingDirectory}) async {
        invocations.add(arguments);
        if (arguments.first == 'compile') {
          if (compileExit == 0) {
            File(arguments[arguments.indexOf('-o') + 1])
              ..createSync(recursive: true)
              ..writeAsStringSync('kernel');
          }
          return ProcessResult(0, compileExit, '', '');
        }
        if (arguments.first == 'run') return ProcessResult(0, 0, manifest, '');
        return ProcessResult(
          0,
          kernelExit,
          kernelExit == 0 ? manifest : '',
          '',
        );
      },
    );

    setUp(() {
      invocations = [];
      dir = Directory.systemTemp.createTempSync('fw-manifest-cache');
      File(p.join(dir.path, configFilePath))
        ..createSync(recursive: true)
        ..writeAsStringSync('// config');
      File(p.join(dir.path, '.dart_tool', 'package_config.json'))
        ..createSync(recursive: true)
        ..writeAsStringSync('{}');
    });

    tearDown(() => dir.deleteSync(recursive: true));

    test('compiles once, then runs the kernel', () async {
      var loader = loaderWith();

      expect((await loader.load(dir.path))!.plugins.single.id, 'a.one');
      expect(invocations.map((a) => a.first), ['compile', endsWith('.dill')]);

      invocations.clear();
      expect((await loader.load(dir.path))!.plugins.single.id, 'a.one');
      expect(
        invocations.map((a) => a.first),
        [endsWith('.dill')],
        reason: 'the second load must not compile again',
      );
    });

    test('recompiles when the config file changes', () async {
      var loader = loaderWith();
      await loader.load(dir.path);
      invocations.clear();

      // Size is part of the key, so this is a change even at the same mtime.
      File(
        p.join(dir.path, configFilePath),
      ).writeAsStringSync('// config, edited');

      await loader.load(dir.path);
      expect(invocations.first.first, 'compile');
    });

    test('recompiles when a different SDK is doing the compiling', () async {
      await loaderWith(dart: '/a/bin/dart').load(dir.path);
      invocations.clear();

      await loaderWith(dart: '/b/bin/dart').load(dir.path);
      expect(
        invocations.first.first,
        'compile',
        reason: 'an fvm switch changes neither the config nor the resolution',
      );
    });

    test('a kernel that will not load falls back rather than blaming the '
        'config', () async {
      var loader = loaderWith(kernelExit: 253);

      // It still answers, via `dart run` — the failure is ours, not the user's.
      expect((await loader.load(dir.path))!.plugins.single.id, 'a.one');
      expect(invocations.map((a) => a.first), [
        'compile',
        endsWith('.dill'),
        'run',
      ]);

      invocations.clear();
      await loader.load(dir.path);
      expect(
        invocations.first.first,
        'compile',
        reason: 'the bad kernel must have been invalidated',
      );
    });

    test('falls back to dart run when the compile fails', () async {
      var loader = loaderWith(compileExit: 1);
      expect((await loader.load(dir.path))!.plugins.single.id, 'a.one');
      expect(invocations.map((a) => a.first), ['compile', 'run']);
    });
  });
}
