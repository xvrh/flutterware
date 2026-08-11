import 'dart:async';
import 'dart:convert';

import 'package:dart_mcp/client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware/plugins.dart';
// ignore: implementation_imports
import 'package:flutterware/src/log_client.dart';
import 'package:flutterware_app/src/context.dart';
import 'package:flutterware_app/src/plugins/plugin_core.dart';
import 'package:flutterware_app/src/session/cli.dart';
import 'package:flutterware_app/src/session/mcp_server.dart';
import 'package:flutterware_app/src/session/session.dart';
import 'package:flutterware_app/src/shell/workspace.dart';
import 'package:flutterware_app/src/shell/worktree.dart';
import 'package:flutterware_app/src/utils/flutter_sdk.dart';
import 'package:stream_channel/stream_channel.dart';

/// The parity rule, checked rather than asserted.
///
/// > The GUI is not a required participant in anything except being looked at.
///
/// The checkable half of that is: **every action a plugin declares is
/// invocable, identically, from `fw` and from MCP.** These tests walk the
/// manifest rather than naming actions one by one, so a new action is covered
/// the day it is declared and a surface that forgets one fails here.
///
/// Both surfaces are driven over the *same* session, so a difference is a
/// difference in the renderer and nothing else. That is why `FwCli` and
/// `FlutterwareMcpServer` both take a session factory.
///
/// The plugin under test is a fake covering every [ActionParameterKind], not
/// the real two: this is about the surfaces, and a fake needs no Flutter SDK,
/// no compiler and no guest, so it runs everywhere and in milliseconds.
void main() {
  late _Surfaces surfaces;

  setUp(() => surfaces = _Surfaces());
  tearDown(() => surfaces.close());

  group('discovery', () {
    test('both surfaces list the same plugins', () async {
      var fromCli = await surfaces.cliJson(['status', '--json']);
      var fromMcp = await surfaces.mcpJson('flutterware_status');

      expect(
        [for (var p in fromCli['plugins']! as List) (p as Map)['id']],
        [for (var p in fromMcp['plugins']! as List) (p as Map)['id']],
      );
    });

    test('every declared action is discoverable from both', () async {
      var cli = _actionIds(await surfaces.cliJson(['actions', '--json']));
      var mcp = _actionIds(await surfaces.mcpJson('flutterware_actions'));

      expect(cli, isNotEmpty);
      expect(
        cli,
        mcp,
        reason:
            'An action visible on one surface and not the other is exactly '
            'the drift the parity rule exists to catch.',
      );
      // And the manifest is the third opinion: neither renderer invents or
      // drops one.
      expect(cli, {
        for (var report in surfaces.session.reports)
          for (var action in report.actions) '${report.id}/${action.id}',
      });
    });

    test('the parameters of every action are declared identically', () async {
      var cli = await surfaces.cliJson(['actions', '--json']);

      Map<String, Object?> parameters(Map<String, Object?> payload) => {
        for (var plugin in payload['plugins']! as List)
          for (var action in (plugin as Map)['actions']! as List)
            '${plugin['id']}/${(action as Map)['id']}': action['parameters'],
      };

      // Plugin by plugin, because MCP documents the parameters only when asked
      // for one — the whole catalogue at once does not fit in a reply. Walking
      // what the CLI answered means a plugin MCP cannot serve at all fails here
      // rather than being skipped.
      var fromMcp = <String, Object?>{};
      for (var plugin in cli['plugins']! as List) {
        fromMcp.addAll(
          parameters(
            await surfaces.mcpJson('flutterware_actions', {
              'plugin': (plugin as Map)['id'],
            }),
          ),
        );
      }

      expect(parameters(cli), fromMcp);
    });

    test('the index names every action, and the plugin fills one in', () async {
      var index = await surfaces.mcpJson('flutterware_actions');
      var indexed = (index['plugins']! as List)
          .expand((p) => (p as Map)['actions']! as List)
          .map((a) => (a as Map)['id'])
          .toSet();

      // The index is the reply an agent reads first, so what it must carry is
      // every id — `takes` is a convenience, and the documentation is one call
      // away, but an action missing here is an action nobody knows to ask for.
      expect(indexed, {for (var action in _FakeCore.declared) action.id});
      expect(
        index.toString().contains('description'),
        isTrue,
        reason: 'an id with no sentence saying what it does is a guess',
      );
    });

    test('an unknown plugin is refused with the declared ones', () async {
      var refusal = await surfaces.mcpError('flutterware_actions', {
        'plugin': 'previewz',
      });
      expect(refusal, contains('previewz'));
      expect(refusal, contains(surfaces.session.reports.first.id));
    });
  });

  group('invocation', () {
    // The matrix: every action the fake declares, exercised through both
    // surfaces with arguments derived from its own declaration.
    for (var action in _FakeCore.succeeding) {
      test('${action.id} returns the same thing on both surfaces', () async {
        var arguments = _validArguments(action);

        var cli = await surfaces.cliJson([
          'run',
          'fake',
          action.id,
          for (var entry in arguments.entries) '--${entry.key}=${entry.value}',
        ]);
        var mcp = await surfaces.mcpJson('flutterware_invoke', {
          'plugin': 'fake',
          'action': action.id,
          'arguments': arguments,
        });

        // MCP wraps the result and adds the report after it; the payload
        // underneath has to be the same object the CLI printed.
        expect(mcp['result'], cli);
        expect(mcp['action'], action.id);
        expect(
          mcp['plugin'],
          'test.fake',
          reason: 'the resolved id, never the short name the caller typed',
        );
      });

      test('${action.id} reaches the core with the same arguments', () async {
        var arguments = _validArguments(action);

        await surfaces.cli([
          'run',
          'fake',
          action.id,
          for (var entry in arguments.entries) '--${entry.key}=${entry.value}',
        ]);
        var viaCli = surfaces.core.lastArguments;

        await surfaces.mcpJson('flutterware_invoke', {
          'plugin': 'fake',
          'action': action.id,
          'arguments': arguments,
        });
        var viaMcp = surfaces.core.lastArguments;

        // Values arrive as strings from a shell and as typed JSON from an
        // agent, so they are compared by their string form: what matters is
        // that the plugin is told the same thing, not that two transports
        // agree on `7` versus `"7"`.
        expect(_stringify(viaCli), _stringify(viaMcp));
      });
    }

    test(
      'a bare flag is true, which is the only way a shell says so',
      () async {
        await surfaces.cli(['run', 'fake', 'query', '--loud']);
        expect(surfaces.core.lastArguments['loud'], isTrue);
      },
    );

    group('a flag and its value', () {
      // `--name Ada` is how everyone types it, and it used to be dropped:
      // `name` became `true` and "Ada" was counted as a positional, which came
      // back as `required (name): true` — or, where the action cast it, as a
      // type error with a stack trace and no mention of the flag.

      test('may be separated by a space', () async {
        await surfaces.cli(['run', 'fake', 'query', '--name', 'Ada']);
        expect(surfaces.core.lastArguments['name'], 'Ada');
      });

      test('is the same thing as an equals sign', () async {
        await surfaces.cli(['run', 'fake', 'query', '--name=Ada']);
        var equals = surfaces.core.lastArguments;
        await surfaces.cli(['run', 'fake', 'query', '--name', 'Ada']);

        expect(surfaces.core.lastArguments, equals);
      });

      test('is typed by the declaration either way', () async {
        await surfaces.cli([
          'run',
          'fake',
          'query',
          '--name',
          'Ada',
          '--count',
          '7',
        ]);
        expect(surfaces.core.lastArguments['count'], 7);
      });

      test('is not eaten by a boolean in front of it', () async {
        // The one case greed would get wrong: a declared boolean takes no
        // value, so what follows belongs to whatever comes next.
        await surfaces.cli(['run', 'fake', 'query', '--loud', '--name', 'Ada']);

        expect(surfaces.core.lastArguments['loud'], isTrue);
        expect(surfaces.core.lastArguments['name'], 'Ada');
      });

      test('is refused, naming the flag, when there is no value', () async {
        var refusal = await surfaces.cliError([
          'run',
          'fake',
          'query',
          '--name',
        ]);

        expect(refusal.code, isNot(0));
        expect(
          refusal.text,
          allOf(contains('needs a value'), contains('--name=')),
          reason:
              'a flag that lost its value must not reach the action as true',
        );
      });
    });
  });

  group('a result that reports failure', () {
    // The action succeeded — it ran, it answered, and the answer is the
    // point. Only the shell's view differs, so that `fw run … && deploy`
    // stops.
    test('exits 1 from `fw`, and still prints the result', () async {
      var red = await surfaces.cliRun(['run', 'fake', 'red']);

      expect(red.code, 1);
      expect(jsonDecode(red.out), {'ok': false});
    });

    test('leaves a passing result at 0', () async {
      var plain = await surfaces.cliRun(['run', 'fake', 'plain']);

      expect(plain.code, 0);
      expect(jsonDecode(plain.out), {'ok': true});
    });

    test('is not an MCP error — the data is the answer', () async {
      var mcp = await surfaces.mcpCall('flutterware_invoke', {
        'plugin': 'fake',
        'action': 'red',
      });

      expect(mcp.isError ?? false, isFalse);
    });
  });

  group('failure', () {
    test(
      'an unknown plugin is legible on both, and names what exists',
      () async {
        var cli = await surfaces.cliError(['run', 'ghost', 'query']);
        var mcp = await surfaces.mcpError('flutterware_invoke', {
          'plugin': 'ghost',
          'action': 'query',
        });

        for (var message in [cli.text, mcp]) {
          expect(message, contains('ghost'));
          expect(
            message,
            contains('test.fake'),
            reason: 'the recovery path is the list of what *is* declared',
          );
        }
        expect(cli.code, FwCli.usageExit);
      },
    );

    test('an unknown action is legible on both', () async {
      var cli = await surfaces.cliError(['run', 'fake', 'nope']);
      var mcp = await surfaces.mcpError('flutterware_invoke', {
        'plugin': 'fake',
        'action': 'nope',
      });

      expect(cli.text, contains('nope'));
      expect(mcp, contains('nope'));
      expect(cli.code, FwCli.usageExit);
    });

    test('a bad argument is reported, not swallowed', () async {
      var cli = await surfaces.cliError([
        'run',
        'fake',
        'query',
        '--pick=purple',
      ]);
      var mcp = await surfaces.mcpError('flutterware_invoke', {
        'plugin': 'fake',
        'action': 'query',
        'arguments': {'pick': 'purple'},
      });

      expect(cli.text, contains('purple'));
      expect(mcp, contains('purple'));
      expect(cli.code, FwCli.usageExit);
    });

    // Every declared kind, given something it cannot be. A bad value must be
    // a legible message on both surfaces — never a stack trace, and never a
    // silent default.
    for (var (parameter, bad) in [('loud', 'maybe'), ('count', 'lots')]) {
      test('a $parameter that is not one is refused on both', () async {
        var cli = await surfaces.cliError([
          'run',
          'fake',
          'query',
          '--name=x',
          '--$parameter=$bad',
        ]);
        var mcp = await surfaces.mcpError('flutterware_invoke', {
          'plugin': 'fake',
          'action': 'query',
          'arguments': {'name': 'x', parameter: bad},
        });

        for (var message in [cli.text, mcp]) {
          expect(message, contains(parameter));
          expect(message, contains(bad));
        }
        expect(cli.code, FwCli.usageExit);
        expect(
          cli.text,
          isNot(contains('#0')),
          reason: "a bad argument is the caller's mistake, not a crash",
        );
      });
    }

    test('an action that returns the wrong type is a failed run', () async {
      // `returns:` is what the capability document resolves and publishes, so
      // a mismatch is a document describing a response nobody sends. Both
      // surfaces have to say so rather than serialise it anyway.
      var cli = await surfaces.cliError(['run', 'fake', 'liar']);
      var mcp = await surfaces.mcpError('flutterware_invoke', {
        'plugin': 'fake',
        'action': 'liar',
      });

      for (var message in [cli.text, mcp]) {
        expect(message, contains('_FakeResult'));
        expect(message, contains('liar'));
      }
    });

    test('an action that throws does not take the surface down', () async {
      var cli = await surfaces.cliError(['run', 'fake', 'explode']);
      var mcp = await surfaces.mcpError('flutterware_invoke', {
        'plugin': 'fake',
        'action': 'explode',
      });

      expect(cli.text, contains('boom'));
      expect(mcp, contains('boom'));
      // Not a usage error: the command was right and the action failed.
      expect(cli.code, 1);
      // And MCP answers with a tool result, not a protocol error — a model
      // should read this and correct itself.
      expect(surfaces.lastMcpResult!.isError, isTrue);
    });

    test('errors never escape as an exception', () async {
      // The whole matrix again, with nothing supplied: whatever each action
      // requires is missing, and no surface may throw.
      for (var action in _FakeCore.declared) {
        await expectLater(
          surfaces.cli(['run', 'fake', action.id]),
          completes,
          reason: '${action.id} threw out of fw',
        );
        await expectLater(
          surfaces.mcpCall('flutterware_invoke', {
            'plugin': 'fake',
            'action': action.id,
          }),
          completes,
          reason: '${action.id} threw out of MCP',
        );
      }
    });
  });

  group('reading', () {
    test('reading a report starts no work on either surface', () async {
      // `actions` reads every report to list what each plugin declares, and
      // declarations are static — so this is the surface that shows the rule
      // still holds. It is the same rule the GUI leans on, where a sidebar row
      // reads a report per frame.
      await surfaces.cli(['actions', '--json']);
      await surfaces.mcpJson('flutterware_actions');
      expect(
        surfaces.core.computed,
        isFalse,
        reason:
            'A report is read by every sidebar row and every tab glyph; one '
            'that computed would make reading unusable.',
      );
    });

    test('both surfaces compute before reporting status', () async {
      // A `fw` process and an MCP call both start cold, so a status that
      // reported only cached state would say "not computed" every time. Both
      // load first, and neither asks to be told to.
      await surfaces.cli(['status', '--json']);
      expect(surfaces.core.computed, isTrue);

      surfaces.core.computed = false;
      await surfaces.mcpJson('flutterware_status');
      expect(
        surfaces.core.computed,
        isTrue,
        reason:
            'A surface that reported cold where the other loaded is exactly '
            'the drift the parity rule exists to catch.',
      );
    });
  });
}

/// Arguments that satisfy an action's own declaration.
///
/// Derived from the declaration rather than written per action, so a new
/// parameter is exercised without this file being touched.
Map<String, Object?> _validArguments(PluginAction action) => {
  for (var parameter in action.parameters)
    if (parameter.required || parameter.defaultValue == null)
      parameter.id: switch (parameter.kind) {
        ActionParameterKind.integer => 7,
        ActionParameterKind.boolean => true,
        ActionParameterKind.choice => parameter.options.first.value,
        ActionParameterKind.string => 'text',
      },
};

Map<String, String> _stringify(Map<String, Object?> arguments) => {
  for (var entry in arguments.entries) entry.key: '${entry.value}',
};

Set<String> _actionIds(Map<String, Object?> payload) => {
  for (var plugin in payload['plugins']! as List)
    for (var action in (plugin as Map)['actions']! as List)
      '${plugin['id']}/${(action as Map)['id']}',
};

/// One session, and both renderers of it.
class _Surfaces {
  _Surfaces() {
    _toServer = StreamController<String>();
    _toClient = StreamController<String>();
    FlutterwareMcpServer(
      StreamChannel<String>(_toServer.stream, _toClient.sink),
      openSession: _open,
    );
    _client = MCPClient(Implementation(name: 'parity-test', version: '1'));
    _connection = _client.connectServer(
      StreamChannel<String>(_toClient.stream, _toServer.sink),
    );
    _ready = _connection
        .initialize(
          InitializeRequest(
            protocolVersion: ProtocolVersion.latestSupported,
            capabilities: _client.capabilities,
            clientInfo: _client.implementation,
          ),
        )
        .then((_) => _connection.notifyInitialized());
  }

  late final StreamController<String> _toServer;
  late final StreamController<String> _toClient;
  late final MCPClient _client;
  late final ServerConnection _connection;
  late final Future<void> _ready;

  late final _FakeCore core = session.cores.single as _FakeCore;

  late final Session session = Session.resolved(
    worktree: const Worktree(path: '/project'),
    workspace: _workspace(),
    manifest: const PluginManifest([
      PluginDeclaration(id: 'test.fake', label: 'Fake'),
    ]),
    registry: PluginCoreRegistry({'test.fake': _FakeCore.new}),
  );

  // The same session for both surfaces: a difference in what they answer is
  // then a difference in the renderer, which is the only thing being measured.
  Future<Session> _open() async => session;

  CallToolResult? lastMcpResult;

  Future<({int code, String text})> cliError(List<String> arguments) async {
    var err = StringBuffer();
    var code = await FwCli(
      openSession: _open,
      out: StringBuffer(),
      err: err,
    ).run(arguments);
    return (code: code, text: err.toString());
  }

  Future<String> cli(List<String> arguments) async {
    var out = StringBuffer();
    await FwCli(
      openSession: _open,
      out: out,
      err: StringBuffer(),
    ).run(arguments);
    return out.toString();
  }

  Future<({int code, String out})> cliRun(List<String> arguments) async {
    var out = StringBuffer();
    var code = await FwCli(
      openSession: _open,
      out: out,
      err: StringBuffer(),
    ).run(arguments);
    return (code: code, out: out.toString());
  }

  Future<Map<String, Object?>> cliJson(List<String> arguments) async =>
      (jsonDecode(await cli(arguments)) as Map).cast<String, Object?>();

  Future<CallToolResult> mcpCall(
    String tool, [
    Map<String, Object?> arguments = const {},
  ]) async {
    await _ready;
    return lastMcpResult = await _connection.callTool(
      CallToolRequest(name: tool, arguments: arguments),
    );
  }

  Future<Map<String, Object?>> mcpJson(
    String tool, [
    Map<String, Object?> arguments = const {},
  ]) async {
    var result = await mcpCall(tool, arguments);
    expect(result.isError, isNot(isTrue), reason: '$tool: ${_text(result)}');
    return (jsonDecode(_text(result)) as Map).cast<String, Object?>();
  }

  Future<String> mcpError(
    String tool, [
    Map<String, Object?> arguments = const {},
  ]) async {
    var result = await mcpCall(tool, arguments);
    expect(result.isError, isTrue, reason: '$tool did not report an error');
    return _text(result);
  }

  static String _text(CallToolResult result) =>
      result.content.whereType<TextContent>().map((c) => c.text).join('\n');

  Future<void> close() async {
    session.dispose();
    await _connection.shutdown();
    await _toServer.close();
    await _toClient.close();
  }
}

/// A typed result, so the matrix covers the [PluginResult] branch as well as
/// the plain-map one `query` still returns.
class _FakeResult implements PluginResult, ReportsFailure {
  _FakeResult({required this.ok});

  @override
  final bool ok;

  @override
  Map<String, Object?> toJson() => {'ok': ok};
}

/// A plugin whose actions cover every parameter kind, and every way an
/// invocation can go wrong.
class _FakeCore extends PluginCore {
  _FakeCore(super.host);

  var lastArguments = <String, Object?>{};
  var computed = false;

  /// Every action that succeeds when given what it declares — the matrix the
  /// happy-path tests walk.
  /// The happy-path matrix: everything except the two actions that exist to
  /// fail — one by throwing, one by breaking its own `returns:` declaration.
  static List<PluginAction> get succeeding => [
    for (var a in declared)
      if (a.id != 'explode' && a.id != 'liar') a,
  ];

  /// Declared once, walked by the tests. Adding one here adds it to every
  /// matrix below.
  static const declared = [
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
          'loud',
          'Loud',
          kind: ActionParameterKind.boolean,
          required: false,
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
    PluginAction('plain', 'Plain', returns: _FakeResult),
    PluginAction(
      'red',
      'Red',
      returns: _FakeResult,
      description: 'Succeeds as an action; what it ran did not pass',
    ),
    PluginAction('explode', 'Explode', description: 'Always fails'),
    PluginAction(
      'liar',
      'Liar',
      returns: _FakeResult,
      description: 'Declares one result type and returns another',
    ),
  ];

  @override
  PluginReport get report =>
      PluginReport(id: host.id, label: host.label, actions: declared);

  @override
  Future<void> computeAll() async => computed = true;

  @override
  Future<Object?> invoke(
    String actionId, {
    Map<String, Object?> arguments = const {},
  }) async {
    lastArguments = arguments;
    switch (actionId) {
      case 'explode':
        throw StateError('boom');
      case 'plain':
        return _FakeResult(ok: true);
      case 'red':
        return _FakeResult(ok: false);
      case 'liar':
        return {'ok': true};
      case 'query':
        var pick = arguments['pick'];
        if (pick != null && !['red', 'blue'].contains(pick)) {
          throw ArgumentError.value(pick, 'pick', 'expected red or blue');
        }
        if (arguments['name'] is! String) {
          throw ArgumentError.value(arguments['name'], 'name', 'required');
        }
        return {
          'name': arguments['name'],
          'pick': pick,
          'loud': arguments['loud'] == true,
        };
      default:
        return super.invoke(actionId, arguments: arguments);
    }
  }
}

Workspace _workspace() => Workspace(
  root: '/project',
  declared: const [Pkg('.')],
  discovered: const ['.'],
  appContext: AppContext(logger: LogClient.print()),
  flutterSdk: FlutterSdkPath('/flutter'),
);
