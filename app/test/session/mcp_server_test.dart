import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dart_mcp/client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware_app/src/plugins/plugin_core.dart';
import 'package:flutterware_app/src/session/mcp_server.dart';
import 'package:flutterware_app/src/shell/repo_layout.dart';
import 'package:stream_channel/stream_channel.dart';

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

  test('status reports every declared plugin, computing nothing', () async {
    var result = await connection.callTool(
      CallToolRequest(name: 'flutterware_status'),
    );
    var payload = _decode(result);

    var plugins = (payload['plugins']! as List).cast<Map<String, Object?>>();
    expect(plugins.map((p) => p['id']), [
      'flutterware.dependencies',
      'flutterware.ui_catalog',
    ]);
    // Nothing subscribed, so nothing loaded — the same answer `fw status`
    // gives cold, and the reason `compute` has to be asked for.
    expect(jsonEncode(payload), contains('not computed'));
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
    expect(plugins, hasLength(2));
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
      ['reload'],
    );
  });

  test('invoke runs the action and returns the report with it', () async {
    var payload = _decode(
      await connection.callTool(
        CallToolRequest(
          name: 'flutterware_invoke',
          arguments: {'plugin': 'dependencies', 'action': 'reload'},
        ),
      ),
    );
    expect(payload['plugin'], 'flutterware.dependencies');
    expect(payload['action'], 'reload');
    // Saves the agent a second round-trip to see what changed.
    expect(payload['report'], isA<Map<String, Object?>>());
  });

  group('errors come back as tool results, not protocol failures', () {
    test('unknown plugin', () async {
      var result = await connection.callTool(
        CallToolRequest(
          name: 'flutterware_invoke',
          arguments: {'plugin': 'nope', 'action': 'reload'},
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
}

String _text(CallToolResult result) =>
    (result.content.first as TextContent).text;

Map<String, Object?> _decode(CallToolResult result) =>
    jsonDecode(_text(result)) as Map<String, Object?>;
