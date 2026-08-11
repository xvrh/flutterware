import 'dart:async';
import 'dart:convert';

import 'package:dart_mcp/client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware/plugins.dart';
// ignore: implementation_imports
import 'package:flutterware/src/log_client.dart';
import 'package:flutterware_app/src/context.dart';
import 'package:flutterware_app/src/plugins/plugin_core.dart';
import 'package:flutterware_app/src/session/mcp_server.dart';
import 'package:flutterware_app/src/session/session.dart';
import 'package:flutterware_app/src/shell/workspace.dart';
import 'package:flutterware_app/src/shell/worktree.dart';
import 'package:flutterware_app/src/utils/flutter_sdk.dart';
import 'package:stream_channel/stream_channel.dart';

/// What an agent hears while a three-minute action runs.
///
/// Before this, nothing: `flutterware_invoke` went silent from the call to the
/// result, so a build, an audit or a motion capture — 177s, measured — looked
/// identical to a hang. The plugin was not silent, though; it was moving its
/// status the whole time, because that is what the sidebar renders. These tests
/// are about that being the *same* source: what the panel says is what the
/// client is told, with nothing invented in between.
///
/// Driven through a real MCP client over an in-memory channel, so what is
/// asserted is what a client receives on the wire.
void main() {
  late _Harness harness;

  setUp(() => harness = _Harness());
  tearDown(() => harness.close());

  test("the plugin's own lines arrive while the action runs", () async {
    var messages = await harness.progressOf('narrate');

    expect(messages, ['building', 'linking', 'signing']);
  });

  test('progress increases, as the protocol asks', () async {
    var notifications = await harness.notificationsOf('narrate');

    expect([for (var n in notifications) n.progress], [1, 2, 3]);
  });

  test('a line that has not changed is not progress', () async {
    // A report is one object and any part of it moving rings the same bell —
    // an artifact recorded, a child loaded, a view rebuilt. Re-sending the
    // status each time would turn one build into a stutter of identical lines.
    expect(await harness.progressOf('repeat'), ['building']);
  });

  test('a row that moves is followed, and named', () async {
    // Where a run puts its news: the plugin's own line goes on counting
    // devices while the row for the app being built carries the launcher's
    // progress. Two rows saying the same word are two pieces of news, and the
    // same row saying it twice is one — which is why the dedupe is per row.
    expect(await harness.progressOf('rows'), [
      'Row a: building',
      'Row b: building',
      'Row a: live',
    ]);
  });

  test('a plugin that says nothing sends nothing', () async {
    // Silence is honest. A heartbeat that only means "still alive" is what the
    // client's timeout is for, and inventing one would make every action look
    // like it was reporting.
    expect(await harness.progressOf('quiet'), isEmpty);
  });

  test('nothing is sent to a client that did not ask', () async {
    // The token is the opt-in the protocol defines: a notification for a token
    // nobody issued is a frame the client has to discard.
    await harness.call('narrate');
    await pumpEventQueue();

    expect(harness.progressSent, isEmpty);
  });

  test(
    'the reply still carries the result, not just the running commentary',
    () async {
      var result = await harness.call('narrate', progressToken: 'tok');
      var payload =
          jsonDecode(result.content.whereType<TextContent>().single.text)
              as Map;

      expect(payload['action'], 'narrate');
      expect((payload['report']! as Map)['status'], {
        'tone': 'neutral',
        'message': 'signing',
      });
    },
  );
}

/// One server, one client, one plugin that narrates.
class _Harness {
  _Harness() {
    _toServer = StreamController<String>();
    _toClient = StreamController<String>();
    FlutterwareMcpServer(
      StreamChannel<String>(_toServer.stream, _toClient.sink),
      openSession: () async => session,
    );
    _client = MCPClient(Implementation(name: 'progress-test', version: '1'));
    // Tapped on the way to the client: what is asserted is then the frames the
    // server actually wrote, including the ones a client would drop.
    _connection = _client.connectServer(
      StreamChannel<String>(
        _toClient.stream.map((frame) {
          _frames.add(frame);
          return frame;
        }),
        _toServer.sink,
      ),
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

  late final Session session = Session.resolved(
    worktree: const Worktree(path: '/project'),
    workspace: Workspace(
      root: '/project',
      declared: const [Pkg('.')],
      discovered: const ['.'],
      appContext: AppContext(logger: LogClient.print()),
      flutterSdk: FlutterSdkPath('/flutter'),
    ),
    manifest: const PluginManifest([
      PluginDeclaration(id: 'test.narrator', label: 'Narrator'),
    ]),
    registry: PluginCoreRegistry({'test.narrator': _NarratorCore.new}),
  );

  final _frames = <String>[];

  /// Every progress notification the server has written so far.
  List<ProgressNotification> get progressSent => [
    for (var frame in _frames)
      if ((jsonDecode(frame) as Map)['method'] ==
          ProgressNotification.methodName)
        ProgressNotification.fromMap(
          ((jsonDecode(frame) as Map)['params'] as Map).cast<String, Object?>(),
        ),
  ];

  Future<CallToolResult> call(String action, {String? progressToken}) async {
    await _ready;
    return _connection.callTool(
      CallToolRequest(
        name: 'flutterware_invoke',
        arguments: {'plugin': 'narrator', 'action': action},
        meta: progressToken == null
            ? null
            : MetaWithProgressToken(
                progressToken: ProgressToken(progressToken),
              ),
      ),
    );
  }

  Future<List<ProgressNotification>> notificationsOf(String action) async {
    var result = await call(action, progressToken: 'tok');
    expect(result.isError, isNot(isTrue), reason: '$action failed');
    // The last notification and the result travel the same channel; letting
    // the queue drain is what makes the count deterministic.
    await pumpEventQueue();
    return progressSent;
  }

  Future<List<String?>> progressOf(String action) async => [
    for (var notification in await notificationsOf(action))
      notification.message,
  ];

  Future<void> close() async {
    session.dispose();
    await _connection.shutdown();
    await _toServer.close();
    await _toClient.close();
  }
}

/// A plugin that moves its status while it works — the shape every real core
/// has, with the timing made explicit.
class _NarratorCore extends PluginCore {
  _NarratorCore(super.host);

  Status _status = Status.none;
  final _rows = <String, Status>{};

  @override
  PluginReport get report => PluginReport(
    id: host.id,
    label: host.label,
    status: _status,
    children: [
      for (var row in _rows.entries)
        PluginChild(id: row.key, label: 'Row ${row.key}', status: row.value),
    ],
    actions: const [
      PluginAction('narrate', 'Narrate', description: 'Says three things'),
      PluginAction('repeat', 'Repeat', description: 'Says one thing twice'),
      PluginAction('quiet', 'Quiet', description: 'Says nothing'),
      PluginAction('rows', 'Rows', description: 'Moves two children in turn'),
    ],
  );

  Future<void> _say(String message) async {
    _status = Status.neutral(message);
    notifyChanged();
    // The bump is deferred by a microtask, so a step that does not yield would
    // coalesce with the next one — which is exactly what a real core's work
    // does *not* do.
    await pumpEventQueue();
  }

  Future<void> _row(String id, String message) async {
    _rows[id] = Status.neutral(message);
    notifyChanged();
    await pumpEventQueue();
  }

  @override
  Future<Object?> invoke(
    String actionId, {
    Map<String, Object?> arguments = const {},
  }) async {
    switch (actionId) {
      case 'narrate':
        for (var step in ['building', 'linking', 'signing']) {
          await _say(step);
        }
      case 'repeat':
        await _say('building');
        await _say('building');
      case 'rows':
        await _row('a', 'building');
        await _row('b', 'building');
        await _row('a', 'live');
      case 'quiet':
        await pumpEventQueue();
      default:
        return super.invoke(actionId, arguments: arguments);
    }
    return null;
  }
}
