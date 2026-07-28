import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware/plugins.dart';
// ignore: implementation_imports
import 'package:flutterware/src/logs/remote_log_client.dart';
import 'package:flutterware_app/src/context.dart';
import 'package:flutterware_app/src/plugins/manifest_loader.dart';
import 'package:flutterware_app/src/plugins/native_plugin.dart';
import 'package:flutterware_app/src/plugins/plugin_core.dart';
import 'package:flutterware_app/src/plugins/registry.dart';
import 'package:flutterware_app/src/shell/shell_controller.dart';
import 'package:flutterware_app/src/shell/worktree_discovery.dart';
import 'package:flutterware_app/src/utils/flutter_sdk.dart';

const _listing =
    'worktree /repo\nbranch refs/heads/main\n\n'
    'worktree /repo-explorer\nbranch refs/heads/feature/explorer\n\n'
    'worktree /repo-pty\nbranch refs/heads/fix/pty\n';

const _manifestJson =
    '{"version":1,"plugins":[{"id":"a.one","label":"One"},'
    '{"id":"a.two","label":"Two"}]}';

var _disposedIds = <String>[];

class _FakeCore extends PluginCore {
  _FakeCore(super.host, {this.guards = const []});

  final List<Guard> guards;

  @override
  PluginReport get report =>
      PluginReport(id: host.id, label: host.label, guards: guards);

  /// Closing a worktree has to reach the core: that is where watchers,
  /// subscriptions and processes live, and the panel is only a screen.
  @override
  void dispose() {
    _disposedIds.add('${host.worktree.path}:${host.id}');
    super.dispose();
  }
}

class _Fake extends NativePlugin<_FakeCore> {
  _Fake(super.core);

  @override
  Widget buildPanel(BuildContext context, String? childId) => const SizedBox();
}

PluginRegistry _panels(Iterable<String> ids) =>
    PluginRegistry({for (var id in ids) id: panelFor<_FakeCore>(_Fake.new)});

/// Mutable so a test can change what git reports between calls.
var _currentListing = _listing;

ShellController _controller({
  String manifest = _manifestJson,
  int manifestExit = 0,
  Map<String, PluginCoreFactory>? cores,
}) {
  cores ??= {'a.one': _FakeCore.new, 'a.two': _FakeCore.new};
  return ShellController(
    appContext: AppContext(logger: LogClient.print()),
    flutterSdk: FlutterSdkPath('/tmp/flutter'),
    registry: _panels(cores.keys),
    coreRegistry: PluginCoreRegistry(cores),
    manifestLoader: _StubLoader(manifest, manifestExit),
    discovery: WorktreeDiscovery(
      runProcess: (_, _, {workingDirectory}) async =>
          ProcessResult(0, 0, _currentListing, ''),
    ),
  );
}

/// Bypasses the config-file existence check so tests need no fixtures.
class _StubLoader implements ManifestLoader {
  _StubLoader(this.manifest, this.exitCode);

  final String manifest;
  final int exitCode;

  @override
  Future<PluginManifest?> load(String worktreePath) async {
    if (exitCode != 0) {
      throw ManifestLoadException('config failed', details: 'boom');
    }
    return PluginManifest.parse(manifest);
  }

  @override
  Future<({PluginManifest? manifest, String? error})> tryLoad(
    String worktreePath,
  ) async {
    try {
      return (manifest: await load(worktreePath), error: null);
    } on ManifestLoadException catch (e) {
      return (manifest: null, error: '$e');
    }
  }

  @override
  String get dartExecutable => 'dart';
}

void main() {
  setUp(() {
    _disposedIds = <String>[];
    _currentListing = _listing;
  });

  test('start opens only the launch worktree', () async {
    var shell = _controller();
    await shell.start('/repo');

    expect(shell.worktrees, hasLength(3));
    expect(shell.openWorktrees.map((w) => w.branch), ['main']);
    expect(shell.closedWorktrees.map((w) => w.branch), [
      'feature/explorer',
      'fix/pty',
    ]);
    expect(shell.selected!.branch, 'main');
    // Nothing is mounted: a worktree opens on its own home screen rather than
    // on whichever plugin happens to be declared first.
    expect(shell.isHome, isTrue);
    expect(shell.selectedPluginId, isNull);
  });

  test('the tab exists before the config finishes running', () async {
    var shell = _controller();
    await shell.start('/repo');
    var explorer = shell.closedWorktrees.first;

    // Not awaited: this is the window the user used to spend looking at an
    // unchanged window.
    var opening = shell.open(explorer);
    expect(shell.openWorktrees.map((w) => w.branch), [
      'main',
      'feature/explorer',
    ]);
    expect(shell.isLoading(explorer), isTrue);
    expect(shell.sessionFor(explorer), isNull);

    await opening;
    expect(shell.isLoading(explorer), isFalse);
    expect(shell.sessionFor(explorer), isNotNull);
  });

  test('a worktree closed while it was still loading stays closed', () async {
    var shell = _controller();
    await shell.start('/repo');
    var explorer = shell.closedWorktrees.first;

    var opening = shell.open(explorer);
    expect(shell.close(explorer), isTrue);
    await opening;

    expect(shell.openWorktrees.map((w) => w.branch), ['main']);
    expect(shell.sessionFor(explorer), isNull);
  });

  test('selection is remembered per worktree', () async {
    var shell = _controller();
    await shell.start('/repo');
    var main = shell.worktrees.first;
    var explorer = shell.closedWorktrees.first;

    shell.selectPlugin('a.two');
    await shell.open(explorer);
    expect(shell.isHome, isTrue, reason: 'the new worktree opens on its home');

    shell.select(main);
    expect(shell.selectedPluginId, 'a.two');
  });

  test('reloading the config rebuilds the plugins in place', () async {
    var shell = _controller();
    await shell.start('/repo');
    shell.selectPlugin('a.two');
    var before = shell.selectedSession!.plugins.first;

    expect(await shell.reloadConfig(), isTrue);

    expect(shell.openWorktrees.map((w) => w.branch), ['main']);
    expect(_disposedIds, ['/repo:a.one', '/repo:a.two']);
    expect(identical(shell.selectedSession!.plugins.first, before), isFalse);
    // Where you were survives the reload; the plugin is still declared.
    expect(shell.selectedPluginId, 'a.two');
  });

  test('a blocking guard refuses the reload too', () async {
    var shell = _controller(
      cores: {
        'a.one': (host) =>
            _FakeCore(host, guards: const [Guard.block('dirty')]),
        'a.two': _FakeCore.new,
      },
    );
    await shell.start('/repo');

    expect(await shell.reloadConfig(), isFalse);
    expect(_disposedIds, isEmpty);
  });

  test('opening a second worktree gives it its own plugin instances', () async {
    var shell = _controller();
    await shell.start('/repo');
    await shell.open(shell.closedWorktrees.first);

    expect(shell.openWorktrees.map((w) => w.branch), [
      'main',
      'feature/explorer',
    ]);
    var a = shell.sessionFor(shell.worktrees[0])!.plugins.first;
    var b = shell.sessionFor(shell.worktrees[1])!.plugins.first;
    expect(identical(a, b), isFalse);
    expect(a.host.worktree.path, isNot(b.host.worktree.path));
  });

  test("closing disposes only that worktree's plugins", () async {
    var shell = _controller();
    await shell.start('/repo');
    await shell.open(shell.closedWorktrees.first);

    expect(shell.close(shell.worktrees[1]), isTrue);
    expect(_disposedIds, ['/repo-explorer:a.one', '/repo-explorer:a.two']);
    expect(shell.openWorktrees.map((w) => w.branch), ['main']);
    // Selection falls back to a worktree that is still open.
    expect(shell.selected!.branch, 'main');
  });

  test('a blocking guard refuses the close', () async {
    var shell = _controller(
      cores: {
        'a.one': (host) =>
            _FakeCore(host, guards: const [Guard.block('dirty')]),
        'a.two': _FakeCore.new,
      },
    );
    await shell.start('/repo');

    expect(shell.sessionFor(shell.worktrees[0])!.isBlocked, isTrue);
    expect(shell.close(shell.worktrees[0]), isFalse);
    expect(shell.openWorktrees, hasLength(1));
    expect(_disposedIds, isEmpty);
  });

  test('a warning guard does not refuse the close', () async {
    var shell = _controller(
      cores: {
        'a.one': (host) => _FakeCore(host, guards: const [Guard.warn('busy')]),
      },
    );
    await shell.start('/repo');
    expect(shell.close(shell.worktrees[0]), isTrue);
  });

  test('a broken config still opens the worktree, with the reason', () async {
    var shell = _controller(manifestExit: 1);
    await shell.start('/repo');

    expect(shell.openWorktrees, hasLength(1));
    expect(shell.errorFor(shell.worktrees[0])!.message, contains('boom'));
    // Open but empty — the shell can explain rather than showing nothing.
    expect(shell.sessionFor(shell.worktrees[0])!.plugins, isEmpty);
  });

  test('rescanning closes worktrees git no longer reports', () async {
    var shell = _controller();
    await shell.start('/repo');
    await shell.open(shell.closedWorktrees.first);
    expect(shell.openWorktrees.map((w) => w.branch), [
      'main',
      'feature/explorer',
    ]);

    // The explorer worktree is removed behind our back (git worktree remove).
    _currentListing =
        'worktree /repo\nbranch refs/heads/main\n\n'
        'worktree /repo-pty\nbranch refs/heads/fix/pty\n';
    await shell.rescanWorktrees();

    expect(shell.worktrees.map((w) => w.branch), ['main', 'fix/pty']);
    expect(shell.openWorktrees.map((w) => w.branch), ['main']);
    // Its plugins were disposed, not merely hidden.
    expect(_disposedIds, ['/repo-explorer:a.one', '/repo-explorer:a.two']);
  });

  test('disposing the controller releases every open worktree', () async {
    var shell = _controller();
    await shell.start('/repo');
    await shell.open(shell.closedWorktrees.first);

    shell.dispose();
    expect(_disposedIds, hasLength(4));
  });
}
