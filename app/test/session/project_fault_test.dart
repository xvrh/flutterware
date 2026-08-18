import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware/plugins.dart';
// ignore: implementation_imports
import 'package:flutterware/src/log_client.dart';
import 'package:flutterware_app/src/context.dart';
import 'package:flutterware_app/src/plugins/plugin_core.dart';
import 'package:flutterware_app/src/run/inspect.dart';
import 'package:flutterware_app/src/session/cli.dart';
import 'package:flutterware_app/src/session/session.dart';
import 'package:flutterware_app/src/shell/workspace.dart';
import 'package:flutterware_app/src/shell/worktree.dart';
import 'package:flutterware_app/src/utils/flutter_sdk.dart';

/// **Who a stack trace accuses.**
///
/// `fw` prints one for any failure it does not recognise, and that is right: a
/// plugin bug has to be reportable from the surface that has a terminal. But a
/// stack names files in this package, and a reader who gets one starts
/// debugging this package. When the failure is a fact about *their* app, that
/// is the wrong reader sent to the wrong program — which is exactly what a
/// consumer hit when an app that threw before `runApp` answered `screenshot`
/// with a stack out of `RunCore`.
void main() {
  late StringBuffer out;
  late StringBuffer err;
  late Object? Function() action;

  Future<int> run() => FwCli(
    openSession: () => _session(action),
    out: out,
    err: err,
  ).run(['run', 'fake', 'boom']);

  setUp(() {
    out = StringBuffer();
    err = StringBuffer();
  });

  test('a ProjectFault is reported without a stack', () async {
    action = () => throw AppNotStarted(
      'The launcher log says:\n'
      '  [ERROR:flutter/runtime/dart_vm_initializer.cc(40)] Unhandled '
      'Exception: Connection refused',
    );

    expect(await run(), 1, reason: 'their app really did fail');

    var text = err.toString();
    expect(text, contains('runApp'));
    expect(text, contains('[ERROR:'), reason: 'the reason rides along');
    expect(
      text,
      isNot(contains('package:flutterware_app')),
      reason: 'no stack, so nobody is sent to debug this package',
    );
  });

  test('anything else still prints its stack', () async {
    action = () => throw StateError('a genuine bug in here');

    expect(await run(), 1);

    var text = err.toString();
    expect(text, contains('a genuine bug in here'));
    expect(
      text,
      contains('package:flutterware_app'),
      reason: 'a plugin bug stays reportable',
    );
  });
}

Future<Session> _session(Object? Function() invoke) async => Session.resolved(
  worktree: const Worktree(path: '/project'),
  workspace: Workspace(
    root: '/project',
    declared: const [Pkg('.')],
    discovered: const ['.'],
    appContext: AppContext(logger: LogClient.print()),
    flutterSdk: FlutterSdkPath('/flutter'),
  ),
  manifest: const PluginManifest([
    PluginDeclaration(id: 'test.fake', label: 'Fake'),
  ]),
  registry: PluginCoreRegistry({
    'test.fake': (host) => _ThrowingCore(host, invoke),
  }),
);

class _ThrowingCore extends PluginCore {
  _ThrowingCore(super.host, this._invoke);

  final Object? Function() _invoke;

  @override
  PluginReport get report => PluginReport(
    id: host.id,
    label: host.label,
    actions: const [PluginAction('boom', 'Boom')],
  );

  @override
  Future<Object?> invoke(
    String actionId, {
    Map<String, Object?> arguments = const {},
  }) async => _invoke();
}
