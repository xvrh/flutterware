import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware/plugins.dart';
// ignore: implementation_imports
import 'package:flutterware/src/log_client.dart';
import 'package:flutterware_app/src/context.dart';
import 'package:flutterware_app/src/plugins/plugin_core.dart';
import 'package:flutterware_app/src/session/session.dart';
import 'package:flutterware_app/src/shell/workspace.dart';
import 'package:flutterware_app/src/shell/worktree.dart';
import 'package:flutterware_app/src/utils/flutter_sdk.dart';

/// Records construction and disposal in order, so a test can assert not just
/// *what* happened but that a panel got its chance before the core went.
var _log = <String>[];

class _Core extends PluginCore {
  _Core(super.host) {
    _log.add('build ${host.id}');
  }

  @override
  PluginReport get report => PluginReport(id: host.id, label: host.label);

  @override
  void dispose() {
    _log.add('dispose ${host.id}');
    super.dispose();
  }
}

const _one = PluginDeclaration(id: 'a.one', label: 'One');
const _two = PluginDeclaration(id: 'a.two', label: 'Two');

PluginManifest _m(List<PluginDeclaration> plugins) =>
    PluginManifest(plugins, packages: const [Pkg('.')]);

PluginCoreRegistry get _registry =>
    PluginCoreRegistry({'a.one': _Core.new, 'a.two': _Core.new});

Session _session(PluginManifest manifest) {
  var worktree = Worktree(path: '/repo');
  return Session.resolved(
    worktree: worktree,
    workspace: Workspace(
      root: '/repo',
      declared: const [Pkg('.')],
      discovered: const [],
      appContext: AppContext(logger: LogClient.print()),
      flutterSdk: FlutterSdkPath('/tmp/flutter'),
    ),
    manifest: manifest,
    registry: _registry,
  );
}

void main() {
  setUp(() => _log = []);

  test('an empty diff keeps every core, by identity', () {
    var manifest = _m([_one, _two]);
    var session = _session(manifest);
    var before = session.cores;
    _log = [];

    var rebuilt = session.reconcile(manifest, registry: _registry);

    expect(rebuilt.rebuilt, isEmpty);
    expect(_log, isEmpty, reason: 'nothing built, nothing disposed');
    expect(identical(session.cores[0], before[0]), isTrue);
    expect(identical(session.cores[1], before[1]), isTrue);
  });

  test('a changed declaration rebuilds only its own core', () {
    var before = _m([
      _one,
      const PluginDeclaration(
        id: 'a.two',
        label: 'Two',
        config: {'dir': 'test'},
      ),
    ]);
    var after = _m([
      _one,
      const PluginDeclaration(
        id: 'a.two',
        label: 'Two',
        config: {'dir': 'unit'},
      ),
    ]);

    var session = _session(before);
    var kept = session.cores[0];
    _log = [];

    var rebuilt = session.reconcile(after, registry: _registry);

    expect(rebuilt.rebuilt, ['a.two']);
    expect(rebuilt.diff.changed, {
      'a.two': ['dir'],
    }, reason: 'the diff it acted on is the diff it reports');
    expect(_log, ['build a.two', 'dispose a.two']);
    expect(identical(session.cores[0], kept), isTrue);
    expect(session.cores[1].host.config, {'dir': 'unit'});
  });

  test('a removed plugin is disposed and gone', () {
    var before = _m([_one, _two]);
    var after = _m([_one]);
    var session = _session(before);
    _log = [];

    var rebuilt = session.reconcile(after, registry: _registry);

    expect(rebuilt.rebuilt, isEmpty, reason: 'nothing was built');
    expect(rebuilt.diff.removed, ['a.two']);
    expect(_log, ['dispose a.two']);
    expect(session.cores.map((c) => c.id), ['a.one']);
  });

  test('an added plugin arrives in the new manifest order', () {
    var before = _m([_two]);
    var after = _m([_one, _two]);
    var session = _session(before);
    var kept = session.cores[0];
    _log = [];

    var rebuilt = session.reconcile(after, registry: _registry);

    expect(rebuilt.rebuilt, ['a.one']);
    expect(_log, ['build a.one']);
    expect(session.cores.map((c) => c.id), ['a.one', 'a.two']);
    expect(identical(session.cores[1], kept), isTrue);
  });

  test('a reorder moves the cores without rebuilding any', () {
    var before = _m([_one, _two]);
    var after = _m([_two, _one]);
    var session = _session(before);
    var one = session.cores[0];
    var two = session.cores[1];
    _log = [];

    var rebuilt = session.reconcile(after, registry: _registry);

    expect(rebuilt.rebuilt, isEmpty);
    expect(_log, isEmpty);
    expect(identical(session.cores[0], two), isTrue);
    expect(identical(session.cores[1], one), isTrue);
  });

  test('onRelease runs before the core it names is disposed', () {
    var before = _m([_one, _two]);
    var after = _m([_one]);
    var session = _session(before);
    _log = [];

    session.reconcile(
      after,
      registry: _registry,
      onRelease: (core) => _log.add('release ${core.id}'),
    );

    expect(_log, ['release a.two', 'dispose a.two']);
  });

  test('a factory that throws leaves the session untouched', () {
    var before = _m([_one]);
    var after = _m([_one, _two]);
    var session = _session(before);
    var kept = session.cores[0];
    _log = [];

    expect(
      () => session.reconcile(
        after,
        registry: PluginCoreRegistry({
          'a.one': _Core.new,
          'a.two': (host) => throw StateError('nope'),
        }),
      ),
      throwsStateError,
    );

    expect(session.cores.map((c) => c.id), ['a.one']);
    expect(identical(session.cores[0], kept), isTrue);
    expect(_log, isEmpty, reason: 'nothing was disposed on the way out');
  });

  test('the session tracks the manifest its cores came from', () {
    var before = _m([_one]);
    var after = _m([_one, _two]);
    var session = _session(before);
    expect(session.manifest, same(before));

    session.reconcile(after, registry: _registry);

    // Held here rather than beside the session, so it cannot fall out of step
    // with the cores it describes.
    expect(session.manifest, same(after));
    expect(session.diff(after).isEmpty, isTrue);
  });

  test('cores is unmodifiable to callers', () {
    var session = _session(_m([_one]));
    expect(
      () => session.cores.add(session.cores.first),
      throwsUnsupportedError,
    );
  });
}
