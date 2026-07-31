import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware/plugins.dart';
// ignore: implementation_imports
import 'package:flutterware/src/log_client.dart';
import 'package:flutterware_app/src/context.dart';
import 'package:flutterware_app/src/plugins/manifest_loader.dart';
import 'package:flutterware_app/src/plugins/native_plugin.dart';
import 'package:flutterware_app/src/plugins/plugin_core.dart';
import 'package:flutterware_app/src/plugins/registry.dart';
import 'package:flutterware_app/src/shell/config_load.dart';
import 'package:flutterware_app/src/shell/shell_controller.dart';
import 'package:flutterware_app/src/shell/worktree_discovery.dart';
import 'package:flutterware_app/src/utils/flutter_sdk.dart';
import 'package:path/path.dart' as p;
import 'package:watcher/watcher.dart';

/// The watcher joined to the reload it triggers, over a real config file on
/// disk so the content gate is exercised rather than stubbed. Only the *events*
/// are injected — a filesystem watcher's delivery is the platform's business and
/// not what this is checking.
const _debounce = Duration(milliseconds: 10);

const _one = '{"version":1,"plugins":[{"id":"a.one","label":"One"}]}';
const _two =
    '{"version":1,"plugins":[{"id":"a.one","label":"One"},'
    '{"id":"a.two","label":"Two"}]}';

/// Names a package that is not on disk. The package list is read off the
/// plugins that declare it, so this is where a package lives now.
const _declaringMissing =
    '{"version":1,"plugins":[{"id":"a.one","label":"One",'
    '"config":{"packages":[{"path":"pkg"}]}}]}';

var _disposedIds = <String>[];

class _FakeCore extends PluginCore {
  _FakeCore(super.host, {this.guards = const []});

  final List<Guard> guards;

  @override
  PluginReport get report =>
      PluginReport(id: host.id, label: host.label, guards: guards);

  @override
  void dispose() {
    _disposedIds.add(host.id);
    super.dispose();
  }
}

/// A core that refuses teardown forever, so a reload has something to be
/// stopped by if it were going to be.
class _BlockingCore extends PluginCore {
  _BlockingCore(super.host);

  @override
  PluginReport get report => PluginReport(
    id: host.id,
    label: host.label,
    guards: const [Guard.block('busy')],
  );

  @override
  void dispose() {
    _disposedIds.add(host.id);
    super.dispose();
  }
}

class _Fake extends NativePlugin<PluginCore> {
  _Fake(super.core);

  @override
  Widget buildPanel(BuildContext context) => const SizedBox();
}

class _StubLoader implements ManifestLoader {
  _StubLoader(this.file);

  /// Reads the file the watcher is watching, so a test "edits the config" by
  /// writing it and the loader sees what the watcher saw.
  final File file;

  @override
  Future<PluginManifest?> load(String worktreePath) async =>
      PluginManifest.parse(file.readAsStringSync());

  @override
  Future<({PluginManifest? manifest, String? error})> tryLoad(
    String worktreePath,
  ) async {
    try {
      return (manifest: await load(worktreePath), error: null);
    } catch (e) {
      return (manifest: null, error: '$e');
    }
  }

  @override
  String get dartExecutable => 'dart';

  @override
  Duration get timeout => Duration.zero; // Unused: no stub spawns a process.
}

void main() {
  late Directory root;
  late File config;
  late StreamController<WatchEvent> events;
  late ShellController shell;

  /// Saves and waits for the reload it causes to land. Waiting on the recorded
  /// load rather than the clock: a fixed delay was a bet on the CI runner's
  /// timer latency, and it lost.
  Future<void> save(String contents) async {
    var worktree = shell.selected!;
    var before = shell.lastLoad(worktree);
    config.writeAsStringSync(contents);
    events.add(WatchEvent(ChangeType.MODIFY, config.path));
    var deadline = DateTime.now().add(const Duration(seconds: 10));
    while (identical(shell.lastLoad(worktree), before)) {
      if (DateTime.now().isAfter(deadline)) {
        fail('no reload landed within 10s of the save');
      }
      await Future<void>.delayed(_debounce);
    }
  }

  /// For saves that must cause no load at all. There is nothing to wait on, so
  /// give the debounce ample room to have fired if it was going to. Slowness
  /// here can only produce a false pass, not a flake.
  Future<void> saveExpectingNothing(String contents) async {
    config.writeAsStringSync(contents);
    events.add(WatchEvent(ChangeType.MODIFY, config.path));
    await Future<void>.delayed(_debounce * 6);
  }

  ShellController controller({Map<String, PluginCoreFactory>? cores}) {
    cores ??= {'a.one': _FakeCore.new, 'a.two': _FakeCore.new};
    return ShellController(
      appContext: AppContext(logger: LogClient.print()),
      flutterSdk: FlutterSdkPath('/tmp/flutter'),
      registry: PluginRegistry({for (var id in cores.keys) id: _Fake.new}),
      coreRegistry: PluginCoreRegistry(cores),
      manifestLoader: _StubLoader(config),
      discovery: WorktreeDiscovery(
        runProcess: (_, _, {workingDirectory}) async => ProcessResult(
          0,
          0,
          'worktree ${root.path}\nbranch refs/heads/main\n',
          '',
        ),
      ),
      watchEvents: (_) => events.stream,
      watchDebounce: _debounce,
    );
  }

  setUp(() {
    _disposedIds = [];
    root = Directory.systemTemp.createTempSync('fw_watch_wiring');
    config = File(p.join(root.path, configFilePath))
      ..createSync(recursive: true)
      ..writeAsStringSync(_one);
    events = StreamController<WatchEvent>.broadcast();
  });

  tearDown(() async {
    shell.dispose();
    await events.close();
    root.deleteSync(recursive: true);
  });

  test(
    'saving the config reloads it without anyone pressing anything',
    () async {
      shell = controller();
      await shell.start(root.path);
      var worktree = shell.selected!;
      expect(shell.sessionFor(worktree)!.plugins.map((pl) => pl.id), ['a.one']);

      await save(_two);

      expect(shell.sessionFor(worktree)!.plugins.map((pl) => pl.id), [
        'a.one',
        'a.two',
      ]);
      expect(shell.lastLoad(worktree)!.outcome, ConfigLoadOutcome.rebuilt);
    },
  );

  test('a save with no byte change does not even run the config', () async {
    shell = controller();
    await shell.start(root.path);
    var worktree = shell.selected!;
    var before = shell.lastLoad(worktree);

    await saveExpectingNothing(_one);

    expect(
      identical(shell.lastLoad(worktree), before),
      isTrue,
      reason:
          'the content gate stops it before the subprocess, so there is '
          'not even a load to report',
    );
  });

  test('a broken save keeps the plugins and reports it', () async {
    shell = controller();
    await shell.start(root.path);
    var worktree = shell.selected!;
    var before = shell.sessionFor(worktree)!.plugins.first;

    await save('this is not json');

    expect(shell.lastLoad(worktree)!.outcome, ConfigLoadOutcome.failed);
    expect(shell.errorFor(worktree), isNotNull);
    expect(
      identical(shell.sessionFor(worktree)!.plugins.first, before),
      isTrue,
    );
    expect(_disposedIds, isEmpty);
  });

  test('a plugin that hard-blocks teardown does not hold the reload', () async {
    shell = controller(
      cores: {'a.one': _BlockingCore.new, 'a.two': _FakeCore.new},
    );
    await shell.start(root.path);
    var worktree = shell.selected!;
    expect(shell.sessionFor(worktree)!.isBlocked, isTrue);

    await save(_two);

    // The guard is honoured by `close`, which is a deliberate act on a
    // worktree. It is not honoured here: deferring the reload was a mechanism
    // protecting state a config change is allowed to cost, and it made the save
    // that *fixes* a config refusable by the plugins the last one left running.
    expect(shell.sessionFor(worktree)!.plugins.map((pl) => pl.id), [
      'a.one',
      'a.two',
    ]);
    expect(_disposedIds, contains('a.one'));
    expect(shell.lastLoad(worktree)!.outcome, ConfigLoadOutcome.rebuilt);
  });

  test('a load that changed nothing still re-checks the disk', () async {
    // The one error that is not a fact about the config: you named a package
    // and it is not there. An unchanged load clears the error before it decides
    // whether to rebuild, so without a re-check it would drop a warning that is
    // still true — and never notice the package you have since created.
    config.writeAsStringSync(_declaringMissing);
    shell = controller(cores: {'a.one': _FakeCore.new});
    await shell.start(root.path);
    var worktree = shell.selected!;
    expect(shell.errorFor(worktree)?.message, contains('pkg'));

    // Same manifest, different bytes — the content gate lets it through and
    // `declares` says nothing moved.
    await save('  $_declaringMissing');

    expect(shell.lastLoad(worktree)!.outcome, ConfigLoadOutcome.unchanged);
    expect(
      shell.errorFor(worktree)?.message,
      contains('pkg'),
      reason: 'the package is still missing, so the warning is still true',
    );

    Directory(p.join(root.path, 'pkg')).createSync();
    await save('   $_declaringMissing');

    expect(shell.lastLoad(worktree)!.outcome, ConfigLoadOutcome.unchanged);
    expect(
      shell.errorFor(worktree),
      isNull,
      reason:
          'and it clears the moment the package exists, without the '
          'config having changed at all',
    );
  });

  test('closing the worktree stops its watcher', () async {
    shell = controller();
    await shell.start(root.path);
    var worktree = shell.selected!;
    expect(shell.watchingFor(worktree), isNotNull);

    shell.close(worktree);

    expect(shell.watchingFor(worktree), isNull);
    // And a save afterwards must not resurrect anything.
    await saveExpectingNothing(_two);
    expect(shell.sessionFor(worktree), isNull);
    expect(shell.isOpen(worktree), isFalse);
  });
}
