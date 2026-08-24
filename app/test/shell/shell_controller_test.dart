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
import 'package:flutterware_app/src/changes/changes_config_cache.dart';
import 'package:flutterware_app/src/utils/flutter_sdk.dart';
import 'package:flutterware_app/src/worktrees/facts_controller.dart';
import 'package:flutterware_app/src/worktrees/facts_probe.dart';
import 'package:flutterware_app/src/worktrees/facts_store.dart';
import 'package:path/path.dart' as p;

const _listing =
    'worktree /repo\nbranch refs/heads/main\n\n'
    'worktree /repo-explorer\nbranch refs/heads/feature/explorer\n\n'
    'worktree /repo-pty\nbranch refs/heads/fix/pty\n';

const _manifestJson =
    '{"version":1,"plugins":[{"id":"a.one","label":"One"},'
    '{"id":"a.two","label":"Two"}]}';

var _disposedIds = <String>[];
var _builtIds = <String>[];

class _FakeCore extends PluginCore {
  _FakeCore(super.host, {this.guards = const []}) {
    _builtIds.add('${host.worktree.path}:${host.id}');
  }

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

/// A facts controller a test can move by hand, without a probe and without
/// touching the filesystem.
class _BumpableFacts extends WorktreeFactsController {
  _BumpableFacts({required super.repoRoot, required super.probe});

  /// Stands in for a probe landing — which is all the shell ever sees of one.
  void bump() => notifyListeners();
}

ShellController _controller({
  String manifest = _manifestJson,
  int manifestExit = 0,
  Map<String, PluginCoreFactory>? cores,
  WorktreeFactsStore? factsStore,
  WorktreeFactsController Function(String repoRoot)? facts,
}) {
  cores ??= {'a.one': _FakeCore.new, 'a.two': _FakeCore.new};
  _loader = _StubLoader(manifest, manifestExit);
  return ShellController(
    appContext: AppContext(logger: LogClient.print()),
    flutterSdk: FlutterSdkPath('/tmp/flutter'),
    registry: _panels(cores.keys),
    coreRegistry: PluginCoreRegistry(cores),
    manifestLoader: _loader,
    // The shell writes the changes config through the explorer's store, so a
    // test that wants to read it back injects the controller that holds one.
    worktreeFacts:
        facts ??
        (factsStore == null
            ? null
            : (root) => WorktreeFactsController(
                repoRoot: root,
                probe: WorktreeFactsProbe(repoRoot: root, store: factsStore),
              )),
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
  @override
  String? get flutterRoot => null;

  _StubLoader(this.manifest, this.exitCode);

  String manifest;
  int exitCode;
  var loads = 0;

  /// Held open to keep a load in flight while another is started.
  Completer<void>? gate;

  @override
  Future<PluginManifest?> load(String worktreePath) async {
    loads++;
    if (gate case var gate?) {
      this.gate = null;
      await gate.future;
    }
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

  @override
  Duration get timeout => Duration.zero; // Unused: no stub spawns a process.
}

void main() {
  setUp(() {
    _disposedIds = <String>[];
    _builtIds = <String>[];
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
    expect(shell.launchFallback, isNull);
  });

  test('start opens the worktree the launch directory is inside', () async {
    var shell = _controller();
    // The repro: `dart run flutterware` in a nested project of a *linked*
    // worktree. `examples/example` equals no worktree path, and matching by
    // equality opened the main checkout — a plausible-looking window onto
    // somebody else's branch.
    await shell.start('/repo-explorer/examples/example');

    expect(shell.openWorktrees.map((w) => w.branch), ['feature/explorer']);
    expect(shell.launchFallback, isNull);
  });

  test('containment is component-wise, not a prefix', () async {
    var shell = _controller();
    // `/repo` is a string prefix of `/repo-explorer` and contains none of it.
    await shell.start('/repo-explorer/app');

    expect(shell.openWorktrees.map((w) => w.branch), ['feature/explorer']);
  });

  test('a worktree nested inside another opens itself', () async {
    _currentListing =
        'worktree /repo\nbranch refs/heads/main\n\n'
        'worktree /repo/vendor/widgets\nbranch refs/heads/widgets\n';
    var shell = _controller();
    await shell.start('/repo/vendor/widgets/lib/src');

    expect(shell.openWorktrees.map((w) => w.branch), ['widgets']);
  });

  test('a launch directory in no worktree is opened, and said so', () async {
    var shell = _controller();
    await shell.start('/elsewhere/project');

    // Something still opens — the shell has to show a window — but it no
    // longer claims to be where you started.
    expect(shell.openWorktrees.map((w) => w.branch), ['main']);
    var fallback = shell.launchFallback;
    expect(fallback, isNotNull);
    expect(fallback!.launchDirectory, '/elsewhere/project');
    expect(fallback.opened.path, '/repo');
    expect(fallback.message, contains('/elsewhere/project'));
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

  test('a changed declaration rebuilds the graph', () async {
    var shell = _controller();
    await shell.start('/repo');
    var main = shell.selected!;
    _disposedIds = [];

    _loader.manifest =
        '{"version":1,"plugins":[{"id":"a.one","label":"One"},'
        '{"id":"a.two","label":"Two","config":{"dir":"unit"}}]}';
    await shell.reloadConfig();

    // Everything goes, including the plugin whose own declaration did not move.
    // That is the accepted price of the config having changed at all.
    expect(_disposedIds, ['/repo:a.one', '/repo:a.two']);
    var load = shell.lastLoad(main)!;
    expect(load.outcome, ConfigLoadOutcome.rebuilt);
    expect(load.summary, 'rebuilt, 2 plugins');
  });

  test('a removed plugin is gone after the rebuild', () async {
    var shell = _controller();
    await shell.start('/repo');

    _loader.manifest = '{"version":1,"plugins":[{"id":"a.one","label":"One"}]}';
    await shell.reloadConfig();

    expect(shell.selectedSession!.plugins.map((p) => p.id), ['a.one']);
  });

  test('an added plugin arrives', () async {
    var shell = _controller(
      manifest: '{"version":1,"plugins":[{"id":"a.one","label":"One"}]}',
    );
    await shell.start('/repo');

    _loader.manifest = _manifestJson;
    await shell.reloadConfig();

    expect(shell.selectedSession!.plugins.map((p) => p.id), ['a.one', 'a.two']);
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

  test('a changed package list rebuilds everything', () async {
    var shell = _controller();
    await shell.start('/repo');
    _disposedIds = [];

    // The packages are read off the plugins that name them, so a package only
    // ever moves as part of a plugin's config moving — and that is a change to
    // the manifest like any other. `Workspace` interns a `Pkg` for identity, and
    // every `PluginHost` holds the workspace, so a package that moved cannot
    // reach a plugin that was kept.
    _loader.manifest =
        '{"version":1,"plugins":['
        '{"id":"a.one","label":"One","config":{"packages":[{"path":"app"}]}},'
        '{"id":"a.two","label":"Two"}]}';
    await shell.reloadConfig();

    expect(_disposedIds, ['/repo:a.one', '/repo:a.two']);
    expect(shell.lastLoad(shell.selected!)!.outcome, ConfigLoadOutcome.rebuilt);
  });

  test('a reorder is a change, and the rail follows it', () async {
    var shell = _controller();
    await shell.start('/repo');

    _loader.manifest =
        '{"version":1,"plugins":[{"id":"a.two","label":"Two"},'
        '{"id":"a.one","label":"One"}]}';
    await shell.reloadConfig();

    expect(shell.selectedSession!.plugins.map((p) => p.id), ['a.two', 'a.one']);
    expect(shell.lastLoad(shell.selected!)!.outcome, ConfigLoadOutcome.rebuilt);
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

  test('a blocking guard does not refuse the reload', () async {
    var shell = _controller(
      cores: {
        'a.one': (host) =>
            _FakeCore(host, guards: const [Guard.block('dirty')]),
        'a.two': _FakeCore.new,
      },
    );
    await shell.start('/repo');
    var main = shell.selected!;
    expect(shell.sessionFor(main)!.isBlocked, isTrue);

    // A close still asks the guards — that is a deliberate act on a worktree.
    // A reload does not: it is what the config you just changed asked for, and
    // making it refusable meant the plugins a broken config left running could
    // block the reload that would replace them.
    _loader.manifest = '{"version":1,"plugins":[{"id":"a.two","label":"Two"}]}';
    expect(await shell.reloadConfig(), isTrue);

    expect(_disposedIds, contains('/repo:a.one'));
    expect(shell.sessionFor(main)!.plugins.map((pl) => pl.id), ['a.two']);
    expect(shell.lastLoad(main)!.outcome, ConfigLoadOutcome.rebuilt);
  });

  test('opening logs a build rather than a rebuild', () async {
    var shell = _controller();
    await shell.start('/repo');
    var load = shell.lastLoad(shell.selected!)!;

    expect(load.outcome, ConfigLoadOutcome.built);
    expect(load.summary, 'opened, 2 plugins');
  });

  test('a superseded load does not commit its stale manifest', () async {
    var shell = _controller();
    await shell.start('/repo');
    var main = shell.selected!;

    // Two reloads on the *same* open worktree, the first still running when the
    // second is asked for. Close-and-reopen is caught by object identity
    // instead — this is the case only the generation counter can decide.
    // Every distinct load that got reported, so a superseded one cannot hide
    // behind the winner having overwritten it.
    var reported = <ConfigLoad>[];
    shell.addListener(() {
      var load = shell.lastLoad(main);
      if (load != null && !reported.any((l) => identical(l, load))) {
        reported.add(load);
      }
    });

    var gate = Completer<void>();
    _loader.gate = gate;
    _loader.manifest = '{"version":1,"plugins":[{"id":"a.one","label":"One"}]}';
    var first = shell.reloadConfig();

    _loader.manifest = _manifestJson;
    var second = shell.reloadConfig();
    gate.complete();
    await Future.wait([first, second]);

    expect(shell.sessionFor(main)!.plugins.map((pl) => pl.id), [
      'a.one',
      'a.two',
    ], reason: 'the later load wins, whichever finishes first');
    expect(
      reported,
      hasLength(1),
      reason: 'and the superseded one reports nothing at all',
    );
  });

  test('a load whose tab was reopened underneath it builds nothing', () async {
    var shell = _controller();
    await shell.start('/repo');
    var main = shell.worktrees.first;

    // The stale load holds the *old* per-worktree state, whose generation it
    // still matches — only object identity can tell that the tab it belonged to
    // is gone. Getting this wrong builds a whole session nobody can reach and
    // nobody disposes, which is invisible except by counting.
    var gate = Completer<void>();
    _loader.gate = gate;
    var stale = shell.reloadConfig();
    shell.close(main);
    await shell.open(main);
    gate.complete();
    await stale;

    var live = shell.sessionFor(shell.worktrees.first)!.plugins.length;
    expect(
      _builtIds.length - _disposedIds.length,
      live,
      reason: 'every core built is either live or disposed — none orphaned',
    );
  });

  test('closing forgets what the last load did', () async {
    var shell = _controller();
    await shell.start('/repo');
    var explorer = shell.closedWorktrees.first;
    await shell.open(explorer);
    expect(shell.lastLoad(explorer), isNotNull);

    shell.close(explorer);
    expect(shell.lastLoad(explorer), isNull);
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
    // No session at all — and, crucially, *not loading*. That used to be
    // inferred from the missing session, so a first load that failed looked
    // like one still running and span forever; the workaround was an empty
    // session built purely to make the inference come out right.
    expect(shell.sessionFor(shell.worktrees[0]), isNull);
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
    expect(shell.sessionFor(main), isNull);

    _loader.exitCode = 0;
    await shell.reloadConfig();

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

  /// Why the shell is quiet when nothing on it moved.
  ///
  /// Every one of these used to notify. The shell is one notifier under one
  /// `AnimatedBuilder`, so each of them was the whole window — band, rail and
  /// panel — rebuilt for something a corner of one screen draws. Measured on
  /// this app with the window idle and untouched: a 15–40 ms build about twice
  /// a second, indefinitely.
  group('an idle shell stays still', () {
    test('a rescan that finds the same worktrees notifies nobody', () async {
      var shell = _controller();
      await shell.start('/repo');

      var notifications = 0;
      shell.addListener(() => notifications++);

      // What the git watch does all day. It fires for any write under `.git` —
      // a commit, an index refresh, another window running `git status` — and
      // the list it re-derives is almost always the list it already had.
      await shell.rescanWorktrees();
      expect(notifications, 0);
    });

    test('a rescan that finds a moved branch does notify', () async {
      var shell = _controller();
      await shell.start('/repo');

      var notifications = 0;
      shell.addListener(() => notifications++);

      // The tab is named after the branch, so this is on screen.
      _currentListing =
          'worktree /repo\nbranch refs/heads/main\n\n'
          'worktree /repo-explorer\nbranch refs/heads/feature/renamed\n\n'
          'worktree /repo-pty\nbranch refs/heads/fix/pty\n';
      addTearDown(() => _currentListing = _listing);
      await shell.rescanWorktrees();

      expect(notifications, 1);
      expect(shell.worktrees[1].branch, 'feature/renamed');
    });

    test('a plugin changing does not reach the shell', () async {
      var shell = _controller();
      await shell.start('/repo');
      await shell.open(shell.closedWorktrees.first);

      var notifications = 0;
      shell.addListener(() => notifications++);

      // A health probe, a compile step, a log line. The rail subscribes to the
      // plugin per row and a panel subscribes to its own; neither needs the
      // window marked dirty.
      var session = shell.selectedSession!;
      var pluginNotifications = 0;
      session.plugins.first.addListener(() => pluginNotifications++);
      session.plugins.first.core.notifyChanged();
      await pumpEventQueue();

      expect(pluginNotifications, 1);
      expect(notifications, 0);
    });

    test('the worktree facts changing does not reach the shell', () async {
      var shell = _controller(
        facts: (root) => _BumpableFacts(
          repoRoot: root,
          probe: WorktreeFactsProbe(
            repoRoot: root,
            store: WorktreeFactsStore.open(
              root,
              at: File(p.join(Directory.systemTemp.path, 'no-such-cache.json')),
            ),
          ),
        ),
      );
      await shell.start('/repo');

      var notifications = 0;
      shell.addListener(() => notifications++);

      var facts = shell.worktreeFacts! as _BumpableFacts;
      var factsNotifications = 0;
      facts.addListener(() => factsNotifications++);
      // What an agent appending to its session file produces, floored at one
      // signal every two seconds for as long as anybody anywhere is working.
      // Three screens draw these; none of them is the window.
      facts.bump();

      expect(factsNotifications, 1);
      expect(notifications, 0);
    });
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
        'fw:///worktrees/~',
        reason: 'the main checkout is ~, and names no plugin at home',
      );

      shell.selectPlugin('a.two');
      expect(shell.address.toString(), 'fw:///worktrees/~/a.two');

      shell.selectChild('a.two', 'packages/app');
      expect(
        shell.address.toString(),
        'fw:///worktrees/~/a.two/packages%2Fapp',
      );
    });

    test('go is the write every select goes through', () async {
      var shell = _controller();
      await shell.start('/repo');

      shell.go(Address.parse('fw:///worktrees/~/a.one'));

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
      shell.go(
        Address.parse('fw:///worktrees/~/a.two/packages%2Fapp/demo.dart%23x'),
      );

      expect(shell.selectedPluginId, 'a.two');
      expect(shell.selectedChildId, 'packages/app');
      expect(shell.address.segments, ['packages/app', 'demo.dart#x']);
    });

    test('a worktree that is not open is opened, not refused', () async {
      var shell = _controller();
      await shell.start('/repo');

      expect(
        shell.go(Address.parse('fw:///worktrees/repo-explorer/a.one')),
        GoResult.ok,
      );

      // Opening is the navigation. Landing on the home screen instead would be
      // the same silent not-where-you-said the refusal used to be.
      expect(shell.address.toString(), 'fw:///worktrees/repo-explorer/a.one');
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

      expect(
        shell.address.toString(),
        'fw:///worktrees/~/a.two/packages%2Fapp',
      );
    });
  });

  group('the same place in another checkout', () {
    test('everything but the worktree rides along', () async {
      var shell = _controller();
      await shell.start('/repo');
      shell.go(
        Address.parse(
          'fw:///worktrees/~/a.two/packages%2Fapp/demo.dart%23x?axis.theme=dark',
        ),
      );

      shell.goToWorktree(shell.closedWorktrees.first);

      // The demo, the package and the theme are what make it a comparison
      // rather than a navigation.
      expect(
        shell.address.toString(),
        'fw:///worktrees/repo-explorer/a.two/packages%2Fapp/demo.dart%23x?axis.theme=dark',
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
      expect(shell.address.toString(), 'fw:///worktrees/repo-explorer/a.one');
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

  /// The one destination that does not open what it names.
  ///
  /// Every other address in the shell needs a session to render, so `go` opens
  /// the worktree it is pointed at. The changes screen reads git rather than
  /// the project, and the whole reason it exists is to answer a question about
  /// a checkout *before* you decide to spend a config subprocess on it.
  group('a shell screen that needs no session', () {
    test('naming it does not open the worktree, or spend a config', () async {
      var shell = _controller();
      await shell.start('/repo');
      var loadsAfterStart = _loader.loads;
      var closed = shell.closedWorktrees.first;

      expect(
        shell.go(Address(worktree: closed.name, plugin: Address.shellChanges)),
        GoResult.ok,
      );
      await pumpEventQueue();

      expect(shell.isOpen(closed), isFalse, reason: 'no tab was grown');
      expect(
        _loader.loads,
        loadsAfterStart,
        reason: 'and no config subprocess was spent',
      );
      expect(
        shell.address.toString(),
        'fw:///worktrees/${closed.name}/changes',
        reason: 'it still lands where it was told',
      );
    });

    test(
      'the worktree resolves even though `selected` cannot see it',
      () async {
        var shell = _controller();
        await shell.start('/repo');
        var closed = shell.closedWorktrees.first;

        shell.go(Address(worktree: closed.name, plugin: Address.shellChanges));

        // `selected` resolves among the *open* ones, which is right for every
        // screen that needs a session and wrong for this one.
        expect(shell.selected, isNull);
        expect(shell.addressedWorktree, closed);
      },
    );

    test('it is neither the home screen nor a plugin', () async {
      var shell = _controller();
      await shell.start('/repo');
      var closed = shell.closedWorktrees.first;

      shell.go(Address(worktree: closed.name, plugin: Address.shellChanges));

      expect(shell.isChangesScreen, isTrue);
      expect(shell.isHome, isFalse, reason: 'or the rail would light Overview');
      expect(shell.selectedPluginId, isNull);
      expect(shell.isConfigScreen, isFalse);
    });

    test(
      'an unopened one is in the worktrees space; an open one is not',
      () async {
        var shell = _controller();
        await shell.start('/repo');
        var closed = shell.closedWorktrees.first;

        shell.go(Address(worktree: closed.name, plugin: Address.shellChanges));
        expect(shell.isUnopenedScreen, isTrue);
        expect(
          shell.inWorktreesSpace,
          isTrue,
          reason: 'no rail, and the pinned tab is lit',
        );

        // The same address, once the checkout has a tab of its own, is an
        // ordinary place inside that tab.
        await shell.open(closed);
        shell.go(Address(worktree: closed.name, plugin: Address.shellChanges));
        expect(shell.isUnopenedScreen, isFalse);
        expect(shell.inWorktreesSpace, isFalse);
      },
    );

    test('every other address still opens what it names', () async {
      // The regression that matters: the exemption is for one id, not for
      // "shell-owned", and certainly not for everything.
      var shell = _controller();
      await shell.start('/repo');
      var closed = shell.closedWorktrees.first;

      shell.go(Address(worktree: closed.name, plugin: Address.shellConfig));
      expect(
        shell.isOpen(closed),
        isTrue,
        reason: 'the config screen is about the session, so it needs one',
      );
    });

    test('a name matching nothing is still unknown', () async {
      var shell = _controller();
      await shell.start('/repo');
      expect(
        shell.go(Address(worktree: 'nope', plugin: Address.shellChanges)),
        GoResult.worktreeUnknown,
      );
    });

    test(
      'selectChanges can name a checkout other than the current one',
      () async {
        var shell = _controller();
        await shell.start('/repo');
        var closed = shell.closedWorktrees.first;

        // How the explorer reaches a row that is not where the window is.
        shell.selectChanges(closed);

        expect(shell.addressedWorktree, closed);
        expect(shell.isOpen(closed), isFalse);
      },
    );
  });

  group('running a config remembers what it said about changes', () {
    late Directory repo;
    late File cacheFile;

    setUp(() {
      repo = Directory.systemTemp.createTempSync('fw-shell-changes');
      File(p.join(repo.path, 'tool', 'flutterware.dart'))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('void main() {}');
      cacheFile = File(p.join(repo.path, '.cache', 'worktrees.json'));
      _currentListing = 'worktree ${repo.path}\nbranch refs/heads/main\n';
      addTearDown(() {
        _currentListing = _listing;
        repo.deleteSync(recursive: true);
      });
    });

    /// A fresh instance each call — so what a test reads back has come off the
    /// file, not out of the object the shell wrote into.
    WorktreeFactsStore store() =>
        WorktreeFactsStore.open(repo.path, at: cacheFile);

    test('the executed value is cached, and reads back fresh', () async {
      // **One writer.** This is the only place the GUI runs a config, so it is
      // the only place that can record what the config produced — which is how
      // a checkout nobody has opened gets ranked by real rules later.
      var shell = _controller(
        manifest:
            '{"version":1,"plugins":[],'
            '"changes":{"attention":["db/**"],"base":"develop"}}',
        cores: const {},
        factsStore: store(),
      );
      await shell.start(repo.path);

      var resolved = resolveChangesConfig(repo.path, store());
      expect(resolved.state, ChangesConfigState.fresh);
      expect(resolved.config?.attention, ['db/**']);
      expect(resolved.config?.base, 'develop');
    });

    test('a config that declares nothing is still recorded', () async {
      // Otherwise a project with no ranking rules looks permanently unknown,
      // and the header would keep offering to run a config that already ran.
      var shell = _controller(
        manifest: '{"version":1,"plugins":[]}',
        cores: const {},
        factsStore: store(),
      );
      await shell.start(repo.path);

      expect(
        resolveChangesConfig(repo.path, store()).state,
        ChangesConfigState.fresh,
      );
    });

    test('a config that failed to run leaves the last good value alone', () async {
      var shell = _controller(
        manifest:
            '{"version":1,"plugins":[],"changes":{"attention":["lib/api/**"]}}',
        cores: const {},
        factsStore: store(),
      );
      await shell.start(repo.path);
      expect(resolveChangesConfig(repo.path, store()).config?.attention, [
        'lib/api/**',
      ]);

      // Now break it. Nothing is torn down on a failed load, and the rules the
      // running plugins came from must survive it too.
      _loader
        ..manifest = ''
        ..exitCode = 1;
      await shell.reloadConfig();

      expect(resolveChangesConfig(repo.path, store()).config?.attention, [
        'lib/api/**',
      ]);
    });
  });

  group('the rail width', () {
    test('is clamped to what a rail can be, and to nothing else', () {
      var shell = _controller();
      expect(shell.sidebarWidth, defaultSidebarWidth);

      shell.resizeSidebar(300);
      expect(shell.sidebarWidth, 300);

      shell.resizeSidebar(2000);
      expect(shell.sidebarWidth, maxSidebarWidth);

      shell.resizeSidebar(10);
      expect(shell.sidebarWidth, minSidebarWidth);

      // Not against the window. It used to be, and a scaled window — where the
      // pane is on its floor and there is no room by that measure — could not
      // be resized at all.
      shell.resizeSidebar(400);
      expect(shell.sidebarWidth, maxSidebarWidth);
    });
  });
}
