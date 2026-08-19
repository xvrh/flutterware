import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware/plugins.dart';
// ignore: implementation_imports
import 'package:flutterware/src/log_client.dart';
import 'package:flutterware_app/src/context.dart';
import 'package:flutterware_app/src/plugins/plugin_core.dart';
import 'package:flutterware_app/src/session/cli.dart';
import 'package:flutterware_app/src/session/session.dart';
import 'package:flutterware_app/src/shell/workspace.dart';
import 'package:flutterware_app/src/shell/worktree.dart';
import 'package:flutterware_app/src/utils/flutter_sdk.dart';

/// The narrowing the MCP tools have had all along, on the command line —
/// and the refusal of what the command line does not know.
///
/// Reported by a consumer migrating a suite: `fw status --brief` and
/// `fw actions --plugin=scenarios` were accepted and silently ignored, and a
/// silently ignored flag reads as "the flag did nothing useful" rather than
/// "the flag does not exist".
void main() {
  late StringBuffer out;
  late StringBuffer err;

  Future<int> run(List<String> arguments) =>
      FwCli(openSession: _session, out: out, err: err).run(arguments);

  setUp(() {
    out = StringBuffer();
    err = StringBuffer();
  });

  group('status', () {
    test('reports every plugin with its projection by default', () async {
      expect(await run(['status']), 0);
      expect(out.toString(), contains('Alpha'));
      expect(out.toString(), contains('Beta'));
      expect(out.toString(), contains('the alpha projection'));
    });

    test('--brief drops the projection and keeps the status line', () async {
      expect(await run(['status', '--brief']), 0);
      expect(out.toString(), contains('Alpha'));
      expect(out.toString(), isNot(contains('the alpha projection')));
    });

    test('a plugin name narrows to that plugin', () async {
      expect(await run(['status', 'beta']), 0);
      expect(out.toString(), contains('Beta'));
      expect(out.toString(), isNot(contains('Alpha')));
    });

    test('an unknown option is refused, not ignored', () async {
      expect(await run(['status', '--nope']), FwCli.usageExit);
      expect(err.toString(), contains('unknown option "--nope"'));
    });

    test('an unknown plugin is refused with the declared ones', () async {
      expect(await run(['status', 'gamma']), FwCli.usageExit);
      expect(err.toString(), contains('gamma'));
    });
  });

  group('actions', () {
    test('a plugin name narrows to that plugin', () async {
      expect(await run(['actions', 'beta']), 0);
      expect(out.toString(), contains('test.beta'));
      expect(out.toString(), isNot(contains('test.alpha')));
    });

    test('an action name narrows to that action', () async {
      expect(await run(['actions', 'beta', 'ping']), 0);
      expect(out.toString(), contains('ping'));
      expect(out.toString(), isNot(contains('pong')));
    });

    test('an action the plugin does not have lists what it has', () async {
      expect(await run(['actions', 'beta', 'zap']), FwCli.usageExit);
      expect(err.toString(), contains('ping, pong'));
    });

    test('an unknown option is refused, not ignored', () async {
      expect(await run(['actions', '--plugin=beta']), FwCli.usageExit);
      expect(err.toString(), contains('unknown option "--plugin=beta"'));
    });

    test('a third positional is refused', () async {
      expect(await run(['actions', 'beta', 'ping', 'extra']), FwCli.usageExit);
    });
  });
}

Future<Session> _session() async => Session.resolved(
  worktree: const Worktree(path: '/project'),
  workspace: Workspace(
    root: '/project',
    declared: const [Pkg('.')],
    discovered: const ['.'],
    appContext: AppContext(logger: LogClient.print()),
    flutterSdk: FlutterSdkPath('/flutter'),
  ),
  manifest: const PluginManifest([
    PluginDeclaration(id: 'test.alpha', label: 'Alpha'),
    PluginDeclaration(id: 'test.beta', label: 'Beta'),
  ]),
  registry: PluginCoreRegistry({
    'test.alpha': (host) => _StaticCore(
      host,
      view: const PluginView([ViewText('the alpha projection')]),
    ),
    'test.beta': (host) => _StaticCore(
      host,
      actions: const [
        PluginAction('ping', 'Ping'),
        PluginAction('pong', 'Pong'),
      ],
    ),
  }),
);

class _StaticCore extends PluginCore {
  _StaticCore(
    super.host, {
    this.view = PluginView.empty,
    this.actions = const [],
  });

  final PluginView view;
  final List<PluginAction> actions;

  @override
  PluginReport get report => PluginReport(
    id: host.id,
    label: host.label,
    actions: actions,
    view: view,
  );

  @override
  Future<Object?> invoke(
    String actionId, {
    Map<String, Object?> arguments = const {},
  }) async => null;
}
