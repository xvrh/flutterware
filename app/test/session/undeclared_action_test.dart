import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware/plugins.dart';
// ignore: implementation_imports
import 'package:flutterware/src/log_client.dart';
import 'package:flutterware_app/src/context.dart';
import 'package:flutterware_app/src/plugins/plugin_core.dart';
import 'package:flutterware_app/src/session/job.dart';
import 'package:flutterware_app/src/session/session.dart';
import 'package:flutterware_app/src/shell/workspace.dart';
import 'package:flutterware_app/src/shell/worktree.dart';
import 'package:flutterware_app/src/utils/flutter_sdk.dart';

/// Declared is what makes an action invocable, not implemented.
///
/// The argument check is keyed on an action's declaration, so a core whose
/// `invoke` handles an id it never declared was exempt from it altogether: the
/// action ran, and every argument it was handed went through unexamined
/// because there was no parameter list to check them against. `run`'s
/// `screenshot` was exactly that for the life of the cockpit, which is how a
/// consumer's `--output` came to be dropped in silence while the reply
/// reported success and named the default path.
///
/// The subject here is that shape and nothing else: one core, one id it
/// answers, no declaration.
void main() {
  late Session session;

  setUp(() async => session = await _session());

  Future<String> refusal(String action) async {
    var result = await session.invoke('test.ghost', action).done;
    expect(result.ok, isFalse, reason: 'the call was meant to be refused');
    return describeJobError(result.error!);
  }

  test('an id the core answers but never declared is refused', () async {
    var message = await refusal('ghost');

    expect(message, contains('unknown action'));
    expect(
      message,
      contains('real'),
      reason: 'the refusal lists what the plugin does declare',
    );
  });

  test('and the core is never reached, so nothing runs', () async {
    await refusal('ghost');

    expect(_GhostCore.ran, isFalse);
  });

  test('a declared action still runs', () async {
    var result = await session.invoke('test.ghost', 'real').done;

    expect(result.ok, isTrue);
    expect(result.value, 'ran');
  });

  /// One sentence, whichever door the caller came through — the session
  /// refuses before dispatch and [PluginCore] refuses after it.
  test('a core invoked directly gives the same words', () async {
    var core = session.coreById('test.ghost')!;

    expect(
      () => core.invoke('nope'),
      throwsA(
        isA<ArgumentError>().having(
          (e) => '${e.message}',
          'message',
          contains('unknown action on test.ghost'),
        ),
      ),
    );
  });
}

Future<Session> _session() async {
  _GhostCore.ran = false;
  return Session.resolved(
    worktree: const Worktree(path: '/project'),
    workspace: Workspace(
      root: '/project',
      declared: const [Pkg('.')],
      discovered: const ['.'],
      appContext: AppContext(logger: LogClient.print()),
      flutterSdk: FlutterSdkPath('/flutter'),
    ),
    manifest: const PluginManifest([
      PluginDeclaration(id: 'test.ghost', label: 'Ghost'),
    ]),
    registry: PluginCoreRegistry({'test.ghost': _GhostCore.new}),
  );
}

/// Answers two ids and declares one, which is the bug in miniature.
class _GhostCore extends PluginCore {
  _GhostCore(super.host);

  static var ran = false;

  @override
  PluginReport get report => PluginReport(
    id: host.id,
    label: host.label,
    actions: const [PluginAction('real', 'Real')],
  );

  @override
  Future<Object?> invoke(
    String actionId, {
    Map<String, Object?> arguments = const {},
  }) async {
    if (actionId == 'real' || actionId == 'ghost') {
      ran = true;
      return 'ran';
    }
    return super.invoke(actionId, arguments: arguments);
  }
}
