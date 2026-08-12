import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware/plugins.dart';
// ignore: implementation_imports
import 'package:flutterware/src/log_client.dart';
import 'package:flutterware_app/src/context.dart';
import 'package:flutterware_app/src/plugins/plugin_core.dart';
import 'package:flutterware_app/src/session/capabilities.dart';
import 'package:flutterware_app/src/session/cli.dart';
import 'package:flutterware_app/src/session/session.dart';
import 'package:flutterware_app/src/shell/workspace.dart';
import 'package:flutterware_app/src/shell/worktree.dart';
import 'package:flutterware_app/src/utils/flutter_sdk.dart';

/// `fw`'s help, and the rule that it is not written anywhere twice.
///
/// Everything printed below is read from a declaration: the command list from
/// [fwCommands], an action's parameters from the same `PluginAction` an agent
/// gets over MCP, and the result tree from the shape extracted out of the class
/// the action returns. The test that matters most is the last one — the
/// capability document renders the same list, and prose in two places is one
/// edit away from a document describing a flag that no longer exists.
void main() {
  late StringBuffer out;
  late StringBuffer err;

  FwCli cli() => FwCli(openSession: _session, out: out, err: err);

  setUp(() {
    out = StringBuffer();
    err = StringBuffer();
  });

  test('help lists every command, from the one list', () async {
    expect(await cli().run(['help']), 0);
    for (var command in fwCommands) {
      expect(out.toString(), contains(command.usage));
      expect(out.toString(), contains(command.summary));
    }
  });

  test('help <command> gives that command in detail', () async {
    expect(await cli().run(['help', 'run']), 0);
    expect(out.toString(), contains('fw run <plugin>'));
    expect(out.toString(), contains('the actions that plugin has'));
  });

  test('an unknown command points at help rather than just refusing', () async {
    expect(await cli().run(['bogus']), FwCli.usageExit);
    expect(err.toString(), contains('fw help'));
  });

  test('run with nothing named explains run', () async {
    // Not an error: somebody typed half a command and wants the other half.
    expect(await cli().run(['run']), 0);
    expect(out.toString(), contains('fw run <plugin> <action>'));
  });

  test("run <plugin> lists that plugin's actions", () async {
    expect(await cli().run(['run', 'fake']), 0);
    expect(out.toString(), contains('test.fake'));
    expect(out.toString(), contains('fw run fake query --name=<string>'));
    expect(out.toString(), contains('Every parameter kind at once'));
  });

  test('-v is a flag, not the name of a plugin', () async {
    // One dash, so `_run`'s "does not start with -- , therefore positional"
    // test would take it for the plugin name and refuse the command it was
    // meant to make louder.
    expect(await cli().run(['run', '-v', 'fake']), 0);
    expect(out.toString(), contains('test.fake'));
    expect(err.toString(), isEmpty);
  });

  test('a global flag works before the command, where one is typed', () async {
    // `fw -v run …` reads better than `fw run … -v`, and used to be answered
    // with `unknown command "-v"`.
    for (var argv in const [
      ['-v', 'run', 'fake'],
      ['--verbose', 'run', 'fake'],
      ['--json', 'run', 'fake'],
    ]) {
      out.clear();
      err.clear();
      expect(await cli().run(argv), 0, reason: '$argv');
      expect(out.toString(), contains('test.fake'), reason: '$argv');
    }
  });

  test('a global flag alone still means the default command', () async {
    // Reaches `app`, which in a test has no launcher and refuses for its own
    // reason. What matters is which refusal: not `unknown command "-v"`.
    await cli().run(['-v']);
    expect(err.toString(), isNot(contains('unknown command')));
    expect(err.toString(), contains('dart run flutterware'));
  });

  test(
    'a leading app flag is the app command, with the flag honored',
    () async {
      // `fw --force-compile` — the documented invocation — used to dispatch as
      // a command named "--force-compile" and exit 64, after the launcher had
      // already paid the forced rebuild the flag asked for.
      bool? forced;
      var cli = FwCli(
        openSession: _session,
        out: out,
        err: err,
        launchGui: ({required bool forceBuild}) async {
          forced = forceBuild;
          return 0;
        },
      );
      expect(await cli.run(['--force-compile']), 0);
      expect(forced, isTrue);
    },
  );

  test("a typo'd leading flag refuses instead of opening a window", () async {
    var cli = FwCli(
      openSession: _session,
      out: out,
      err: err,
      launchGui: ({required bool forceBuild}) async =>
          fail('a window opened for a flag nobody recognizes'),
    );
    expect(await cli.run(['--bogus']), FwCli.usageExit);
    expect(err.toString(), contains('unknown argument "--bogus"'));
  });

  test('the help footer says what -v does, once', () async {
    expect(await cli().run(['help']), 0);
    expect(out.toString(), contains('`-v` on any command'));
  });

  test(
    'run <plugin> <action> --help describes it without running it',
    () async {
      expect(await cli().run(['run', 'fake', 'query', '--help']), 0);

      // The parameters, as declared.
      expect(out.toString(), contains('--name=<string>'));
      expect(out.toString(), contains('required'));
      expect(out.toString(), contains('optional, default 1'));
      expect(out.toString(), contains('values: red, blue'));

      // And it did not invoke anything.
      expect(_FakeCore.invocations, isZero);
    },
  );

  test('a parameter that points elsewhere for its values says where', () async {
    await cli().run(['run', 'fake', 'pointing', '--help']);
    expect(
      out.toString(),
      contains('values: `fw run fake query`'),
      reason: 'optionsFrom names an action, so print the command that runs it',
    );
  });

  test('--help on an action that is not there suggests the list', () async {
    expect(await cli().run(['run', 'fake', 'nope', '--help']), FwCli.usageExit);
    expect(err.toString(), contains('fw run fake'));
  });

  test('the document and the CLI render the same commands', () async {
    // The one that keeps them honest. Both read `fwCommands`, so this can only
    // fail if somebody reintroduces a second copy.
    var document = renderCapabilities();
    await cli().run(['help']);
    for (var command in fwCommands) {
      expect(document, contains(command.usage));
      expect(document, contains(command.summary));
    }
    for (var code in fwExitCodes.entries) {
      expect(document, contains(code.value));
    }
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
    PluginDeclaration(id: 'test.fake', label: 'Fake'),
  ]),
  registry: PluginCoreRegistry({'test.fake': _FakeCore.new}),
);

class _FakeCore extends PluginCore {
  _FakeCore(super.host);

  /// Help must never run anything, so this counts.
  static int invocations = 0;

  @override
  PluginReport get report => PluginReport(
    id: host.id,
    label: host.label,
    actions: const [
      PluginAction(
        'query',
        'Query',
        description: 'Every parameter kind at once',
        parameters: [
          ActionParameter('name', 'Name'),
          ActionParameter(
            'count',
            'Count',
            kind: ActionParameterKind.integer,
            required: false,
            defaultValue: '1',
          ),
          ActionParameter(
            'pick',
            'Pick',
            kind: ActionParameterKind.choice,
            required: false,
            options: [ActionOption('red'), ActionOption('blue')],
          ),
        ],
      ),
      PluginAction(
        'pointing',
        'Pointing',
        parameters: [
          ActionParameter(
            'entry',
            'Entry',
            kind: ActionParameterKind.choice,
            optionsFrom: 'query',
          ),
        ],
      ),
    ],
  );

  @override
  Future<Object?> invoke(
    String actionId, {
    Map<String, Object?> arguments = const {},
  }) async {
    invocations++;
    return null;
  }
}
