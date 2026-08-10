import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dart_mcp/client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware_app/src/plugins/plugin_core.dart';
import 'package:flutterware_app/src/session/cli.dart';
import 'package:flutterware_app/src/session/mcp_server.dart';
import 'package:flutterware_app/src/shell/repo_layout.dart';
import 'package:stream_channel/stream_channel.dart';

/// What `tool/flutterware.dart` declares, in declared order.
///
/// One list, read by both tests that care: one checks the ids a client gets,
/// the other that a build with no cores still reports every one of them. Two
/// literals would mean the second silently stops covering the plugin the first
/// just gained.
const _declaredPlugins = [
  'flutterware.dependencies',
  'flutterware.assets',
  'flutterware.previews',
  'flutterware.splash',
  'flutterware.launcher_icon',
  'flutterware.server',
  'flutterware.run',
  'flutterware.scenarios',
];

/// Drives the server through a real MCP client over an in-memory channel, so
/// what is asserted is what a client actually receives — tool schemas
/// included — rather than the shape of a Dart method.
void main() {
  late MCPClient client;
  late ServerConnection connection;

  late StreamController<String> toServer;
  late StreamController<String> toClient;

  setUp(() async {
    toServer = StreamController<String>();
    toClient = StreamController<String>();

    FlutterwareMcpServer(
      StreamChannel<String>(toServer.stream, toClient.sink),
      workingDirectory: Directory(findRepoRoot('..')!),
    );

    client = MCPClient(
      Implementation(name: 'flutterware test client', version: '1.0.0'),
    );
    connection = client.connectServer(
      StreamChannel<String>(toClient.stream, toServer.sink),
    );
    await connection.initialize(
      InitializeRequest(
        protocolVersion: ProtocolVersion.latestSupported,
        capabilities: client.capabilities,
        clientInfo: client.implementation,
      ),
    );
    connection.notifyInitialized();
  });

  tearDown(() async {
    await connection.shutdown();
    await toServer.close();
    await toClient.close();
  });

  test('the declared tool list is what a client receives', () async {
    // The capability document is generated from `FlutterwareMcpServer.tools`;
    // this is what stops that list describing a surface nobody serves.
    var listed = (await connection.listTools()).tools.map((t) => t.name);
    expect(listed, FlutterwareMcpServer.tools.map((t) => t.name));
  });

  test('exposes a small fixed tool set, not one tool per action', () async {
    var tools = (await connection.listTools()).tools
        .map((t) => t.name)
        .toList();
    expect(tools, [
      'flutterware_status',
      'flutterware_actions',
      'flutterware_invoke',
    ]);
  });

  test('status reports every declared plugin, loaded', () async {
    var result = await connection.callTool(
      CallToolRequest(name: 'flutterware_status'),
    );
    var payload = _decode(result);

    var plugins = (payload['plugins']! as List).cast<Map<String, Object?>>();
    expect(plugins.map((p) => p['id']), _declaredPlugins);
    // An MCP call starts cold, so a status that reported only cached state
    // would say "not computed" for every package on every call — the config
    // file read back rather than an answer. Both cores load first.
    expect(
      jsonEncode(payload),
      isNot(contains('not computed')),
      reason: 'every declared package is loaded, or says why it could not be',
    );
  });

  test('a plugin with no core is reported, not omitted', () async {
    // Both real plugins have cores now, so this needs a build that lacks one.
    // The behaviour still matters: a status that silently skipped a declared
    // plugin would read as "this project has fewer plugins than it does".
    var toServer = StreamController<String>();
    var toClient = StreamController<String>();
    FlutterwareMcpServer(
      StreamChannel<String>(toServer.stream, toClient.sink),
      workingDirectory: Directory(findRepoRoot('..')!),
      registry: PluginCoreRegistry(),
    );
    var bare = MCPClient(Implementation(name: 'bare', version: '1.0.0'));
    var bareConnection = bare.connectServer(
      StreamChannel<String>(toClient.stream, toServer.sink),
    );
    await bareConnection.initialize(
      InitializeRequest(
        protocolVersion: ProtocolVersion.latestSupported,
        capabilities: bare.capabilities,
        clientInfo: bare.implementation,
      ),
    );
    bareConnection.notifyInitialized();

    var payload = _decode(
      await bareConnection.callTool(
        CallToolRequest(name: 'flutterware_status'),
      ),
    );
    var plugins = (payload['plugins']! as List).cast<Map<String, Object?>>();
    // One per declaration, whatever the config declares — a registry with
    // nothing in it must not shrink the list, which is the whole point.
    expect(plugins, hasLength(_declaredPlugins.length));
    for (var plugin in plugins) {
      expect(
        (plugin['status']! as Map)['message'],
        contains('no implementation'),
      );
    }

    await bareConnection.shutdown();
    await toServer.close();
    await toClient.close();
  });

  group('what a reply does not repeat', () {
    // Every byte here is read by a model, and an action declaration is static:
    // the same list, in every reply, for the whole session. `flutterware_actions`
    // serves it once. Measured before this rule existed: 77% of a status and 94%
    // of a screenshot's reply were declarations, and an agent iterating on a
    // widget paid the second on every edit.

    test(
      'status describes the project, not what it can be told to do',
      () async {
        var payload = _decode(
          await connection.callTool(
            CallToolRequest(name: 'flutterware_status'),
          ),
        );
        var plugins = (payload['plugins']! as List)
            .cast<Map<String, Object?>>();
        expect(plugins, isNotEmpty);
        for (var plugin in plugins) {
          expect(
            plugin,
            isNot(contains('actions')),
            reason: '${plugin['id']} repeated its declarations into a status',
          );
        }
        // What a status is actually for is still there.
        expect(plugins.map((p) => p['id']), _declaredPlugins);
        expect(plugins.every((p) => p.containsKey('status')), isTrue);
      },
    );

    test(
      'the report after an invoke carries state, not declarations',
      () async {
        var payload = _decode(
          await connection.callTool(
            CallToolRequest(
              name: 'flutterware_invoke',
              arguments: {'plugin': 'dependencies', 'action': 'list'},
            ),
          ),
        );
        var report = payload['report']! as Map<String, Object?>;
        expect(report, isNot(contains('actions')));
        // The point of sending it at all: what changed.
        expect(report, contains('status'));
      },
    );

    test('and the declarations are still one tool away', () async {
      var payload = _decode(
        await connection.callTool(CallToolRequest(name: 'flutterware_actions')),
      );
      var plugins = (payload['plugins']! as List).cast<Map<String, Object?>>();
      expect(plugins.every((p) => p.containsKey('actions')), isTrue);
    });

    test('replies are compact — indentation is bytes no model reads', () async {
      var text = _text(
        await connection.callTool(CallToolRequest(name: 'flutterware_status')),
      );
      expect(
        text,
        isNot(contains('\n')),
        reason:
            'Pretty-printing was 39% of a status and 47% of an actions reply. '
            '`fw --json` keeps its indentation; that one is read by a person.',
      );
    });
  });

  test('actions lists what can be invoked, with parameters', () async {
    var payload = _decode(
      await connection.callTool(CallToolRequest(name: 'flutterware_actions')),
    );
    var dependencies = (payload['plugins']! as List)
        .cast<Map<String, Object?>>()
        .firstWhere((p) => p['id'] == 'flutterware.dependencies');
    expect(
      (dependencies['actions']! as List).cast<Map<String, Object?>>().map(
        (a) => a['id'],
      ),
      ['list'],
    );
  });

  test('invoke runs the action and returns the report with it', () async {
    var payload = _decode(
      await connection.callTool(
        CallToolRequest(
          name: 'flutterware_invoke',
          arguments: {'plugin': 'dependencies', 'action': 'list'},
        ),
      ),
    );
    expect(payload['plugin'], 'flutterware.dependencies');
    expect(payload['action'], 'list');
    // Saves the agent a second round-trip to see what changed.
    expect(payload['report'], isA<Map<String, Object?>>());
  });

  group('errors come back as tool results, not protocol failures', () {
    test('unknown plugin', () async {
      var result = await connection.callTool(
        CallToolRequest(
          name: 'flutterware_invoke',
          arguments: {'plugin': 'nope', 'action': 'list'},
        ),
      );
      expect(result.isError, isTrue);
      expect(_text(result), contains('No plugin "nope"'));
      // The recovery path is in the message: it says what *is* declared.
      expect(_text(result), contains('flutterware.dependencies'));
    });

    test('unknown action', () async {
      var result = await connection.callTool(
        CallToolRequest(
          name: 'flutterware_invoke',
          arguments: {'plugin': 'dependencies', 'action': 'not-an-action'},
        ),
      );
      expect(result.isError, isTrue);
      expect(_text(result), contains('unknown action'));
      // Like every other refusal on this surface, it names what *is* there —
      // this was the one that did not, and it is the one a caller reaches by
      // guessing at a name.
      expect(_text(result), contains('list'));
    });

    test('missing required argument', () async {
      var result = await connection.callTool(
        CallToolRequest(
          name: 'flutterware_invoke',
          arguments: {'plugin': 'dependencies'},
        ),
      );
      expect(result.isError, isTrue);
    });
  });

  group('fw mcp', () {
    // The command is how a client reaches any of the above. `app/bin/mcp.dart`
    // only exists inside a checkout, so a server nobody can spawn is a server
    // that is not there.
    test('serves, rather than reporting an unknown command', () async {
      var served = false;
      var err = StringBuffer();
      var exit = await FwCli(
        openSession: () => throw StateError('mcp opens no session of its own'),
        out: StringBuffer(),
        err: err,
        serveMcp: () async => served = true,
      ).run(['mcp']);

      expect(served, isTrue);
      expect(exit, 0);
      expect(err.toString(), isEmpty);
    });

    test('writes nothing to stdout — that is the wire', () async {
      var out = StringBuffer();
      await FwCli(
        openSession: () => throw StateError('mcp opens no session of its own'),
        out: out,
        err: StringBuffer(),
        serveMcp: () async {},
      ).run(['mcp']);

      expect(out.toString(), isEmpty);
    });
  });
}

String _text(CallToolResult result) =>
    (result.content.first as TextContent).text;

Map<String, Object?> _decode(CallToolResult result) =>
    jsonDecode(_text(result)) as Map<String, Object?>;
