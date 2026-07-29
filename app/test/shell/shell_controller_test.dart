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
  Widget buildPanel(BuildContext context) => const SizedBox();
}

PluginRegistry _panels(Iterable<String> ids) =>
    PluginRegistry({for (var id in ids) id: panelFor<_FakeCore>(_Fake.new)});

/// Mutable so a test can change what git reports between calls.
var _currentListing = _listing;

/// The loader the most recent [_controller] was built with, so a test can
/// change what the config prints between loads.
late _StubLoader _loader;

ShellController _controller({
  String manifest = _manifestJson,
  int manifestExit = 0,
  Map<String, PluginCoreFactory>? cores,
}) {
  cores ??= {'a.one': _FakeCore.new, 'a.two': _FakeCore.new};
  _loader = _StubLoader(manifest, manifestExit);
  return ShellController(
    appContext: AppContext(logger: LogClient.print()),
    flutterSdk: FlutterSdkPath('/tmp/flutter'),
    registry: _panels(cores.keys),
    coreRegistry: PluginCoreRegistry(cores),
    manifestLoader: _loader,
    discovery: WorktreeDiscovery(
      runProcess: (_, _, {workingDirectory}) async =>
          ProcessResult(0, 0, _currentListing, ''),
    ),
  );
}

/// Bypasses the config-file existence check so tests need no fixtures.
///
/// Mutable: a reload test has to change what the config "prints" between two
/// loads, which is the whole thing being exercised.
class _StubLoader implements ManifestLoader {
  _StubLoader(this.manifest, this.exitCode);

  String manifest;
  int exitCode;
  var loads = 0;

  @override
  Future<PluginManifest?> load(String worktreePath) async {
    loads++;
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

  test('reloading an unchanged config disposes nothing at all', () async {
    var shell = _controller();
    await shell.start('/repo');
    shell.selectPlugin('a.two');
    var main = shell.selected!;
    var session = shell.selectedSession!;
    var panel = session.plugins.first;
    _disposedIds = [];

    expect(await shell.reloadConfig(), isTrue);

    expect(_loader.loads, 2, reason: 'the config really was re-run');
    expect(_disposedIds, isEmpty);
    expect(identical(shell.selectedSession, session), isTrue);
    expect(identical(shell.selectedSession!.plugins.first, panel), isTrue);
    expect(shell.selectedPluginId, 'a.two');
    // Reported, not inferred from silence: a no-op reload and a reload that
    // never fired are otherwise indistinguishable.
    expect(shell.lastLoad(main)!.outcome, ConfigLoadOutcome.unchanged);
    expect(shell.lastLoad(main)!.summary, 'no changes');
  });

  test('a changed declaration rebuilds only that plugin', () async {
    var shell = _controller();
    await shell.start('/repo');
    var main = shell.selected!;
    var kept = shell.selectedSession!.plugins.first;
    _disposedIds = [];

    _loader.manifest =
        '{"version":1,"plugins":[{"id":"a.one","label":"One"},'
        '{"id":"a.two","label":"Two","config":{"dir":"unit"}}]}';
    await shell.reloadConfig();

    expect(_disposedIds, ['/repo:a.two']);
    expect(identical(shell.selectedSession!.plugins.first, kept), isTrue);
    var load = shell.lastLoad(main)!;
    expect(load.outcome, ConfigLoadOutcome.reconciled);
    expect(load.rebuilt, ['a.two']);
    expect(load.reasons, {'a.two': 'dir changed'});
    expect(load.summary, 'two rebuilt');
  });

  test('a removed plugin goes; the survivor keeps its panel', () async {
    var shell = _controller();
    await shell.start('/repo');
    var kept = shell.selectedSession!.plugins.first;
    _disposedIds = [];

    _loader.manifest = '{"version":1,"plugins":[{"id":"a.one","label":"One"}]}';
    await shell.reloadConfig();

    expect(_disposedIds, ['/repo:a.two']);
    expect(shell.selectedSession!.plugins.map((p) => p.id), ['a.one']);
    expect(identical(shell.selectedSession!.plugins.first, kept), isTrue);
  });

  test('an added plugin arrives without disposing anything', () async {
    var shell = _controller(
      manifest: '{"version":1,"plugins":[{"id":"a.one","label":"One"}]}',
    );
    await shell.start('/repo');
    var kept = shell.selectedSession!.plugins.first;
    _disposedIds = [];

    _loader.manifest = _manifestJson;
    await shell.reloadConfig();

    expect(_disposedIds, isEmpty);
    expect(shell.selectedSession!.plugins.map((p) => p.id), ['a.one', 'a.two']);
    expect(identical(shell.selectedSession!.plugins.first, kept), isTrue);
    expect(shell.lastLoad(shell.selected!)!.reasons, {
      'a.two': 'newly declared',
    });
  });

  test('a broken config tears nothing down', () async {
    var shell = _controller();
    await shell.start('/repo');
    var main = shell.selected!;
    var session = shell.selectedSession!;
    _disposedIds = [];

    _loader.exitCode = 1;
    expect(await shell.reloadConfig(), isTrue);

    expect(_disposedIds, isEmpty, reason: 'the running plugins are untouched');
    expect(identical(shell.selectedSession, session), isTrue);
    expect(shell.errorFor(main), isNotNull);
    expect(shell.lastLoad(main)!.outcome, ConfigLoadOutcome.failed);

    // And the fix diffs against the last *good* config, so restoring the
    // original file rebuilds nothing.
    _loader.exitCode = 0;
    await shell.reloadConfig();
    expect(_disposedIds, isEmpty);
    expect(shell.errorFor(main), isNull);
    expect(shell.lastLoad(main)!.outcome, ConfigLoadOutcome.unchanged);
  });

  test('a changed packages list rebuilds everything', () async {
    var shell = _controller();
    await shell.start('/repo');
    var main = shell.selected!;
    _disposedIds = [];

    _loader.manifest =
        '{"version":1,"packages":[{"path":"app"}],'
        '"plugins":[{"id":"a.one","label":"One"},{"id":"a.two","label":"Two"}]}';
    await shell.reloadConfig();

    expect(_disposedIds, ['/repo:a.one', '/repo:a.two']);
    var load = shell.lastLoad(main)!;
    expect(load.outcome, ConfigLoadOutcome.rebuilt);
    expect(load.reasons, {
      'a.one': 'packages changed',
      'a.two': 'packages changed',
    });
  });

  test('a reorder moves the rail without rebuilding a thing', () async {
    var shell = _controller();
    await shell.start('/repo');
    var one = shell.selectedSession!.plugins[0];
    var two = shell.selectedSession!.plugins[1];
    _disposedIds = [];

    _loader.manifest =
        '{"version":1,"plugins":[{"id":"a.two","label":"Two"},'
        '{"id":"a.one","label":"One"}]}';
    await shell.reloadConfig();

    expect(_disposedIds, isEmpty);
    expect(shell.selectedSession!.plugins.map((p) => p.id), ['a.two', 'a.one']);
    expect(identical(shell.selectedSession!.plugins[0], two), isTrue);
    expect(identical(shell.selectedSession!.plugins[1], one), isTrue);
    expect(shell.lastLoad(shell.selected!)!.summary, 'reordered');
  });

  test('a reload that drops the selected plugin falls back home', () async {
    var shell = _controller();
    await shell.start('/repo');
    shell.selectPlugin('a.two');
    expect(shell.selectedPluginId, 'a.two');

    _loader.manifest = '{"version":1,"plugins":[{"id":"a.one","label":"One"}]}';
    await shell.reloadConfig();

    expect(shell.selectedPluginId, isNull, reason: 'not a gone plugin');
  });

  test('a blocking guard refuses the reload, and logs nothing', () async {
    var shell = _controller(
      cores: {
        'a.one': (host) =>
            _FakeCore(host, guards: const [Guard.block('dirty')]),
        'a.two': _FakeCore.new,
      },
    );
    await shell.start('/repo');
    var main = shell.selected!;
    var loadsBefore = _loader.loads;

    expect(await shell.reloadConfig(), isFalse);
    expect(_disposedIds, isEmpty);
    expect(_loader.loads, loadsBefore, reason: 'the config never ran');
    expect(shell.lastLoad(main)!.outcome, ConfigLoadOutcome.built);
  });

  test('opening logs a build rather than a rebuild', () async {
    var shell = _controller();
    await shell.start('/repo');
    var load = shell.lastLoad(shell.selected!)!;

    expect(load.outcome, ConfigLoadOutcome.built);
    expect(load.summary, 'opened, 2 plugins');
    expect(load.reasons, isEmpty, reason: 'nothing was lost to lose');
  });

  test('closing forgets the reload history', () async {
    var shell = _controller();
    await shell.start('/repo');
    var explorer = shell.closedWorktrees.first;
    await shell.open(explorer);
    expect(shell.lastLoad(explorer), isNotNull);

    shell.close(explorer);
    expect(shell.lastLoad(explorer), isNull);
    expect(shell.loadLog(explorer), isEmpty);
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
    expect(
      shell.isLoading(shell.worktrees[0]),
      isFalse,
      reason: 'not spinning',
    );
  });

  test('fixing a config that never loaded builds its plugins', () async {
    var shell = _controller(manifestExit: 1);
    await shell.start('/repo');
    var main = shell.worktrees[0];
    expect(shell.sessionFor(main)!.plugins, isEmpty);

    _loader.exitCode = 0;
    await shell.reloadConfig();

    // The empty session it was given to explain itself is not a config it can
    // be diffed against, so this is a build and not a two-plugin "reload".
    expect(shell.sessionFor(main)!.plugins.map((p) => p.id), [
      'a.one',
      'a.two',
    ]);
    expect(shell.errorFor(main), isNull);
    expect(shell.lastLoad(main)!.outcome, ConfigLoadOutcome.built);
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

  group('the address is the state', () {
    test('every selection is legible as one', () async {
      var shell = _controller();
      await shell.start('/repo');

      expect(
        shell.address.toString(),
        'fw:///~',
        reason: 'the main checkout is ~, and names no plugin at home',
      );

      shell.selectPlugin('a.two');
      expect(shell.address.toString(), 'fw:///~/a.two');

      shell.selectChild('a.two', 'packages/app');
      expect(shell.address.toString(), 'fw:///~/a.two/packages%2Fapp');
    });

    test('go is the write every select goes through', () async {
      var shell = _controller();
      await shell.start('/repo');

      shell.go(Address.parse('fw:///~/a.one'));

      expect(shell.selectedPluginId, 'a.one');
      expect(shell.isHome, isFalse);
    });

    test('an address round-trips back to the same place', () async {
      var shell = _controller();
      await shell.start('/repo');
      shell.selectChild('a.two', 'packages/app');
      var written = shell.address.toString();

      shell.selectHome();
      expect(shell.isHome, isTrue);

      shell.go(Address.parse(written));
      expect(shell.selectedPluginId, 'a.two');
      expect(shell.selectedChildId, 'packages/app');
    });

    test('segments past the child ride along untouched', () async {
      var shell = _controller();
      await shell.start('/repo');

      // What a catalog entry looks like: the shell reads the package and
      // leaves the rest for whoever owns it.
      shell.go(Address.parse('fw:///~/a.two/packages%2Fapp/demo.dart%23x'));

      expect(shell.selectedPluginId, 'a.two');
      expect(shell.selectedChildId, 'packages/app');
      expect(shell.address.segments, ['packages/app', 'demo.dart#x']);
    });

    test('a worktree that is not open is opened, not refused', () async {
      var shell = _controller();
      await shell.start('/repo');

      expect(shell.go(Address.parse('fw:///repo-explorer/a.one')), GoResult.ok);

      // Opening is the navigation. Landing on the home screen instead would be
      // the same silent not-where-you-said the refusal used to be.
      expect(shell.address.toString(), 'fw:///repo-explorer/a.one');
      expect(shell.openWorktrees.map((w) => w.name), ['~', 'repo-explorer']);
    });

    test('the tab and the address are there before the config is', () async {
      var shell = _controller();
      await shell.start('/repo');
      var explorer = shell.closedWorktrees.first;

      // Synchronous: no await between the write and these reads.
      shell.go(Address(worktree: explorer.name, plugin: 'a.one'));

      expect(shell.isOpen(explorer), isTrue);
      expect(shell.isLoading(explorer), isTrue, reason: 'no session yet');
      expect(shell.selected, explorer);

      // And the panel arrives without a second navigation.
      await pumpEventQueue();
      expect(shell.isLoading(explorer), isFalse);
      expect(shell.selectedPluginId, 'a.one');
    });

    test('a load that blows up leaves a tab that says why', () async {
      var shell = _controller();
      await shell.start('/repo');

      // `go` opens without awaiting, so nothing downstream is left to catch a
      // throw from the disk. A tab with no session and no reason is a worktree
      // that looks like it opened and then does nothing.
      shell.go(Address(worktree: 'repo-explorer'));
      await pumpEventQueue();

      var explorer = shell.worktreeNamed('repo-explorer')!;
      expect(shell.isOpen(explorer), isTrue);
      expect(
        shell.sessionFor(explorer) != null || shell.errorFor(explorer) != null,
        isTrue,
        reason: 'a tab ends up with a session or with an explanation',
      );
    });

    test('selecting a closed worktree opens it too', () async {
      var shell = _controller();
      await shell.start('/repo');
      var explorer = shell.closedWorktrees.first;

      shell.select(explorer);

      expect(shell.isOpen(explorer), isTrue);
      expect(shell.address.worktree, explorer.name);
    });

    test('closing the selected tab moves the address to a live one', () async {
      var shell = _controller();
      await shell.start('/repo');
      await shell.open(shell.closedWorktrees.first);
      shell.selectPlugin('a.one');

      expect(shell.close(shell.worktrees[1]), isTrue);

      expect(shell.address.worktree, '~');
      expect(shell.selected!.branch, 'main');
    });

    test('the address a tab was left at is what it comes back to', () async {
      var shell = _controller();
      await shell.start('/repo');
      var main = shell.worktrees.first;
      shell.selectChild('a.two', 'packages/app');

      await shell.open(shell.closedWorktrees.first);
      shell.select(main);

      expect(shell.address.toString(), 'fw:///~/a.two/packages%2Fapp');
    });
  });

  group('the same place in another checkout', () {
    test('everything but the worktree rides along', () async {
      var shell = _controller();
      await shell.start('/repo');
      shell.go(
        Address.parse(
          'fw:///~/a.two/packages%2Fapp/demo.dart%23x?axis.theme=dark',
        ),
      );

      shell.goToWorktree(shell.closedWorktrees.first);

      // The demo, the package and the theme are what make it a comparison
      // rather than a navigation.
      expect(
        shell.address.toString(),
        'fw:///repo-explorer/a.two/packages%2Fapp/demo.dart%23x?axis.theme=dark',
      );
    });

    test('it opens the checkout it is comparing against', () async {
      var shell = _controller();
      await shell.start('/repo');
      var explorer = shell.closedWorktrees.first;

      expect(shell.goToWorktree(explorer), GoResult.ok);
      expect(shell.isOpen(explorer), isTrue);
    });

    test('cycling flicks between the open ones and wraps', () async {
      var shell = _controller();
      await shell.start('/repo');
      await shell.open(shell.closedWorktrees.first);
      shell.select(shell.worktrees.first);
      shell.selectPlugin('a.two');

      shell.cycleWorktree(1);
      expect(shell.address.worktree, 'repo-explorer');
      expect(shell.selectedPluginId, 'a.two', reason: 'the place is kept');

      shell.cycleWorktree(1);
      expect(shell.address.worktree, '~', reason: 'two open, so it is a flick');

      shell.cycleWorktree(-1);
      expect(shell.address.worktree, 'repo-explorer', reason: 'and back');
    });

    test('cycling never opens anything', () async {
      var shell = _controller();
      await shell.start('/repo');

      // A keystroke that spawned a config subprocess is a keystroke you learn
      // not to press. With one worktree open there is nowhere to flick to.
      expect(shell.cycleWorktree(1), GoResult.unchanged);
      expect(shell.openWorktrees, hasLength(1));
    });
  });

  group('a branch is input, never identity', () {
    test('an address naming a branch lands', () async {
      var shell = _controller();
      await shell.start('/repo');
      await shell.open(shell.closedWorktrees.first);

      // Nothing ever *writes* this — a branch moves between worktrees, so an
      // address holding one would silently retarget. But a branch is what the
      // tab shows, so it is what someone types.
      expect(
        shell.go(Address(worktree: 'feature/explorer', plugin: 'a.one')),
        GoResult.ok,
      );
      expect(shell.selected!.path, '/repo-explorer');
    });

    test('what comes back out is the identity, not what was typed', () async {
      var shell = _controller();
      await shell.start('/repo');
      await shell.open(shell.closedWorktrees.first);

      shell.go(Address(worktree: 'feature/explorer', plugin: 'a.one'));

      // Rewritten on the way in. Keeping the branch would put a name that moves
      // with `git checkout` into the remembered address and into every artifact
      // minted from where the shell is.
      expect(shell.address.worktree, 'repo-explorer');
      expect(shell.address.toString(), 'fw:///repo-explorer/a.one');
    });

    test('identity wins over another worktree that has it as a branch', () async {
      _currentListing =
          'worktree /repo\nbranch refs/heads/main\n\n'
          'worktree /wt/alpha\nbranch refs/heads/beta\n\n'
          'worktree /wt/beta\nbranch refs/heads/gamma\n';
      addTearDown(() => _currentListing = _listing);

      var shell = _controller();
      await shell.start('/repo');
      for (var closed in shell.closedWorktrees.toList()) {
        await shell.open(closed);
      }

      // `beta` is /wt/beta's name and /wt/alpha's branch. The name wins, so the
      // canonical form always resolves to itself.
      shell.go(Address(worktree: 'beta', plugin: 'a.one'));
      expect(shell.selected!.path, '/wt/beta');
    });

    test('a name that is neither is unknown, not merely closed', () async {
      var shell = _controller();
      await shell.start('/repo');
      expect(
        shell.go(Address(worktree: 'no-such-thing', plugin: 'a.one')),
        GoResult.worktreeUnknown,
      );
    });
  });
}
