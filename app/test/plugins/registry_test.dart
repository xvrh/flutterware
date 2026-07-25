import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware/plugins.dart';
// ignore: implementation_imports
import 'package:flutterware/src/logs/remote_log_client.dart';
import 'package:flutterware_app/src/context.dart';
import 'package:flutterware_app/src/plugins/manifest_loader.dart';
import 'package:flutterware_app/src/plugins/native_plugin.dart';
import 'package:flutterware_app/src/plugins/plugin_host.dart';
import 'package:flutterware_app/src/plugins/registry.dart';
import 'package:flutterware_app/src/plugins/worktree_session.dart';
import 'package:flutterware_app/src/project.dart';
import 'package:flutterware_app/src/shell/worktree.dart';
import 'package:flutterware_app/src/utils/flutter_sdk.dart';

const _worktree = Worktree(path: '/tmp/wt', branch: 'feature/x');

// Project's services are `late final`, so building one costs nothing until a
// plugin touches them — cheap enough for a unit test.
Project _project() => Project(
  AppContext(logger: LogClient.print()),
  _worktree.path,
  FlutterSdkPath('/tmp/flutter'),
);

class _Fake extends NativePlugin {
  _Fake(super.host, {this.status = Status.none, this.teardown = const []});

  final Status status;
  final List<TeardownStep> teardown;
  var disposed = false;

  @override
  PluginReport get report => PluginReport(
    id: host.id,
    label: host.label,
    status: status,
    teardown: teardown,
    actions: const [PluginAction('go', 'Go')],
  );

  @override
  Widget buildPanel(BuildContext context) => const SizedBox();

  void bump() => notifyListeners();

  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }
}

PluginManifest _manifest(List<String> ids) => PluginManifest([
  for (var id in ids) PluginDeclaration(id: id, label: id.split('.').last),
]);

void main() {
  group('registry', () {
    test('resolves declarations in the config file order', () {
      var registry = PluginRegistry({'a.one': _Fake.new, 'a.two': _Fake.new});
      var plugins = registry.resolve(
        _manifest(['a.two', 'a.one']),
        _worktree,
        _project(),
      );
      expect(plugins.map((p) => p.id), ['a.two', 'a.one']);
    });

    test('surfaces an unknown id instead of dropping it', () {
      var registry = PluginRegistry({'a.one': _Fake.new});
      var plugins = registry.resolve(
        _manifest(['a.one', 'ghost']),
        _worktree,
        _project(),
      );

      expect(plugins, hasLength(2));
      var ghost = plugins.last;
      expect(ghost, isA<MissingPlugin>());
      expect(ghost.report.status.tone, Tone.error);
      expect(ghost.report.view.toText(), contains('ghost'));
    });

    test('passes declared config through to the host', () {
      PluginHost? seen;
      var registry = PluginRegistry({
        'a.one': (host) {
          seen = host;
          return _Fake(host);
        },
      });
      registry.resolve(
        PluginManifest([
          PluginDeclaration(
            id: 'a.one',
            label: 'One',
            config: {'compose': 'dev.yml', 'watch': true},
          ),
        ]),
        _worktree,
        _project(),
      );

      expect(seen!.string('compose'), 'dev.yml');
      expect(seen!.boolean('watch'), isTrue);
      expect(seen!.string('missing', 'fallback'), 'fallback');
      expect(seen!.worktree.branch, 'feature/x');
    });

    test('refuses a duplicate registration', () {
      var registry = PluginRegistry({'a.one': _Fake.new});
      expect(
        () => registry.register('a.one', _Fake.new),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('worktree session', () {
    test('closing disposes every plugin', () {
      var registry = PluginRegistry({'a.one': _Fake.new, 'a.two': _Fake.new});
      var session = WorktreeSession.resolve(
        worktree: _worktree,
        manifest: _manifest(['a.one', 'a.two']),
        registry: registry,
        project: _project(),
      );
      var plugins = session.plugins.cast<_Fake>();

      expect(plugins.every((p) => p.disposed), isFalse);
      session.dispose();
      expect(plugins.every((p) => p.disposed), isTrue);
      expect(session.isDisposed, isTrue);
    });

    test('reduces to the most severe plugin status', () {
      var session = WorktreeSession(
        worktree: _worktree,
        plugins: [
          _Fake(_host('a'), status: Status.good('ok')),
          _Fake(_host('b'), status: Status.error('3 failing')),
          _Fake(_host('c'), status: Status.warn('stack down')),
        ],
      );
      expect(session.status.tone, Tone.error);
      expect(session.status.message, '3 failing');
    });

    test('a plugin update notifies the session', () {
      var plugin = _Fake(_host('a'));
      var session = WorktreeSession(worktree: _worktree, plugins: [plugin]);
      var notified = 0;
      session.addListener(() => notified++);

      plugin.bump();
      expect(notified, 1);
    });

    test('collects teardown steps in phase order', () {
      var session = WorktreeSession(
        worktree: _worktree,
        plugins: [
          _Fake(
            _host('a'),
            teardown: const [
              TeardownStep('c', 'cleanup', phase: TeardownPhase.cleanup),
            ],
          ),
          _Fake(
            _host('b'),
            teardown: const [
              TeardownStep('i', 'infra', phase: TeardownPhase.infra),
              TeardownStep('a', 'apps', phase: TeardownPhase.apps),
            ],
          ),
        ],
      );
      expect(session.teardownSteps.map((s) => s.id), ['a', 'i', 'c']);
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
}

PluginHost _host(String id) =>
    PluginHost(id: id, label: id, worktree: _worktree, project: _project());
