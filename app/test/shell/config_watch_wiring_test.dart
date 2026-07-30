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

/// A core whose guard can be released, so the pending path has something to
/// wait for and then stop waiting for.
class _BlockingCore extends PluginCore {
  _BlockingCore(super.host);

  var blocked = true;

  void release() {
    blocked = false;
    notifyChanged();
  }

  @override
  PluginReport get report => PluginReport(
    id: host.id,
    label: host.label,
    guards: blocked ? const [Guard.block('busy')] : const [],
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

  Future<void> save(String contents) async {
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
      expect(shell.lastLoad(worktree)!.outcome, ConfigLoadOutcome.reconciled);
      expect(_disposedIds, isEmpty, reason: 'a.one was not touched');
    },
  );

  test('a save with no byte change does not even run the config', () async {
    shell = controller();
    await shell.start(root.path);
    var worktree = shell.selected!;
    var loadsBefore = shell.loadLog(worktree).length;

    await save(_one);

    expect(
      shell.loadLog(worktree).length,
      loadsBefore,
      reason: 'the content gate stops it before the subprocess',
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

  test('a blocked guard holds the reload, then it lands', () async {
    late _BlockingCore blocker;
    shell = controller(
      cores: {
        'a.one': (host) => blocker = _BlockingCore(host),
        'a.two': _FakeCore.new,
      },
    );
    await shell.start(root.path);
    var worktree = shell.selected!;

    await save(_two);

    // Held, and *said* to be held — a save that quietly did nothing is
    // indistinguishable from a watcher that is not working.
    expect(shell.isReloadPending(worktree), isTrue);
    expect(shell.sessionFor(worktree)!.plugins.map((pl) => pl.id), ['a.one']);

    blocker.release();
    await Future<void>.delayed(_debounce * 6);

    expect(shell.isReloadPending(worktree), isFalse);
    expect(shell.sessionFor(worktree)!.plugins.map((pl) => pl.id), [
      'a.one',
      'a.two',
    ]);
  });

  test('turning the watch off stops it, and back on resumes', () async {
    shell = controller();
    await shell.start(root.path);
    var worktree = shell.selected!;

    shell.watchEnabled = false;
    expect(shell.watchingFor(worktree), isNull);
    await save(_two);
    expect(shell.sessionFor(worktree)!.plugins, hasLength(1));

    shell.watchEnabled = true;
    expect(shell.watchingFor(worktree), p.join(root.path, 'tool'));
    await save(_one);
    await save(_two);
    expect(shell.sessionFor(worktree)!.plugins, hasLength(2));
  });

  test('closing the worktree stops its watcher', () async {
    shell = controller();
    await shell.start(root.path);
    var worktree = shell.selected!;
    expect(shell.watchingFor(worktree), isNotNull);

    shell.close(worktree);

    expect(shell.watchingFor(worktree), isNull);
    // And a save afterwards must not resurrect anything.
    await save(_two);
    expect(shell.sessionFor(worktree), isNull);
    expect(shell.isOpen(worktree), isFalse);
  });
}
