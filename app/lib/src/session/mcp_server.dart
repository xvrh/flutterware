import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dart_mcp/server.dart';
import 'package:flutterware/plugins.dart';
import 'package:path/path.dart' as p;

import '../plugins/plugin_core.dart';
import 'action_shapes.generated.dart';
import 'job.dart';
import 'session.dart';

/// flutterware over MCP — the third renderer of the plugin contract.
///
/// It reimplements nothing. Every tool below opens a [Session] and reads the
/// same [PluginCore]s the GUI sidebar and `fw` read, which is what makes
/// "no renderer is privileged" true rather than aspirational.
///
/// **A small fixed tool set, not one tool per action.** The obvious mapping —
/// a tool per plugin action — puts every action of every plugin into an
/// agent's context on every request, and 8 plugins with 6 actions each is 50
/// tools to describe before answering a question about one. So discovery is a
/// tool (`flutterware_actions`) and invocation is a tool
/// (`flutterware_invoke`). Individual actions get promoted to their own tool
/// only when a good name beats a discovery round-trip, and none has earned it
/// yet.
base class FlutterwareMcpServer extends MCPServer with ToolsSupport {
  FlutterwareMcpServer(
    super.channel, {
    Directory? workingDirectory,
    this.registry,
    this.openSession,
  }) : workingDirectory = workingDirectory ?? Directory.current,
       super.fromStreamChannel(
         implementation: Implementation(name: 'flutterware', version: '0.5.2'),
         instructions:
             'Inspect and drive a Flutter project through its flutterware '
             'plugins. Start with flutterware_status; it loads and reports what '
             'every declared plugin knows. Anything that compiles, renders or '
             'spawns a process is an action — list them with '
             'flutterware_actions and run them with flutterware_invoke.',
       ) {
    registerTool(_statusTool, _status);
    registerTool(_actionsTool, _actions);
    registerTool(_invokeTool, _invoke);
  }

  /// Every tool this server exposes, in the order it registers them.
  ///
  /// Public because the capability document is generated from it rather than
  /// from a hand-kept list — and `mcp_server_test` asserts a connected client
  /// sees exactly these, so the document cannot describe a surface that is not
  /// there.
  static List<Tool> get tools => [_statusTool, _actionsTool, _invokeTool];

  /// Where to resolve the project from. A session walks up to the repo root,
  /// so any directory inside the project works.
  final Directory workingDirectory;

  /// Which cores this server exposes. Null means the default set.
  final PluginCoreRegistry? registry;

  /// How to get a session, when the caller has an opinion. Public for the same
  /// reason `FwCli` takes one: a test that drives both surfaces over the *same*
  /// session is what makes "the two agree" a checked claim rather than a hope.
  final Future<Session> Function()? openSession;

  Future<T> _withSession<T>(FutureOr<T> Function(Session) body) async {
    var session =
        await (openSession?.call() ??
            Session.open(workingDirectory, registry: registry));
    try {
      return await body(session);
    } finally {
      session.dispose();
    }
  }

  static final _statusTool = Tool(
    name: 'flutterware_status',
    description:
        'What every declared flutterware plugin says about itself: status, '
        'sub-entries per package, and a text projection of the panel. Loads '
        'what has not been loaded yet, so the answer describes the project '
        'rather than what a previous call happened to warm. Loading is parsing '
        '— pubspecs, demo files — and never compiles, spawns a daemon or '
        'touches the network; that work lives behind flutterware_invoke.',
    inputSchema: Schema.object(properties: {}),
  );

  Future<CallToolResult> _status(CallToolRequest request) =>
      _withSession((session) async {
        for (var core in session.cores) {
          await core.computeAll();
        }
        return _json({
          'root': session.root,
          'worktree': session.worktree.branch ?? session.worktree.path,
          'plugins': [for (var report in session.reports) report.toJson()],
        });
      });

  static final _actionsTool = Tool(
    name: 'flutterware_actions',
    description:
        'Every action that can be invoked, per plugin, with the parameters '
        'each one takes and the shape of what it returns. Call this before '
        'flutterware_invoke when you do not already know an action id.',
    inputSchema: Schema.object(properties: {}),
  );

  Future<CallToolResult> _actions(CallToolRequest request) =>
      _withSession((session) async {
        return _json({
          'plugins': [
            for (var report in session.reports)
              {
                'id': report.id,
                'label': report.label,
                'actions': [
                  for (var action in report.actions)
                    {
                      ...action.toJson(),
                      // The shape of what comes back, so an agent knows the
                      // keys before it calls rather than after. Read from
                      // generated data — the extraction ran at build time.
                      if (resultShapes[action.returnsName] case var shape?)
                        'shape': shape.toJson(),
                    },
                ],
              },
          ],
        });
      });

  static final _invokeTool = Tool(
    name: 'flutterware_invoke',
    description:
        'Run one plugin action. Argument keys are the parameter ids reported '
        'by flutterware_actions. Returns whatever the action produced — often '
        'a path to an artifact.',
    inputSchema: Schema.object(
      properties: {
        'plugin': Schema.string(
          description:
              'Plugin id, or its last dotted segment: "flutterware.tests" or '
              'just "tests".',
        ),
        'action': Schema.string(description: 'Action id.'),
        'arguments': Schema.object(
          description: 'Action arguments, keyed by parameter id.',
        ),
      },
      required: ['plugin', 'action'],
    ),
  );

  Future<CallToolResult> _invoke(CallToolRequest request) => _withSession((
    session,
  ) async {
    var pluginName = request.arguments?['plugin'] as String?;
    var actionId = request.arguments?['action'] as String?;
    if (pluginName == null || actionId == null) {
      return _error('Both "plugin" and "action" are required.');
    }

    var arguments =
        (request.arguments?['arguments'] as Map?)?.cast<String, Object?>() ??
        const <String, Object?>{};

    Job job;
    try {
      job = session.invoke(pluginName, actionId, arguments: arguments);
    } on SessionException catch (e) {
      // The message names what *is* declared, so a model that guessed wrong
      // can correct itself without a second round-trip.
      return _error('$e');
    }

    var result = await job.done;
    if (!result.ok) return _error(describeJobError(result.error!));

    var core = session.coreById(job.plugin)!;
    var artifact = result.artifacts.isEmpty ? null : result.artifacts.first;
    var summary = {
      'plugin': job.plugin,
      'action': job.action,
      'result': switch (result.value) {
        PluginResult data => data.toJson(),
        var other => other,
      },
      // The report after the fact, so an agent sees what changed without
      // a second round-trip.
      'report': core.report.toJson(),
    };

    // An image artifact comes back as an image, not as a path. An agent
    // asked to screenshot something wants to *see* it, and a path it cannot
    // open is the difference between a working tool and a plausible one. The
    // JSON travels alongside, so the address and the resolved axes are still
    // there to ask for the same frame again.
    if (artifact != null && artifact.kind.startsWith('image/')) {
      var file = File(p.join(session.root, artifact.path!));
      if (file.existsSync()) {
        return CallToolResult(
          content: [
            ImageContent(
              data: base64Encode(file.readAsBytesSync()),
              mimeType: artifact.kind,
            ),
            TextContent(text: _encode(summary)),
          ],
        );
      }
    }

    return _json(summary);
  });

  static String _encode(Object? value) =>
      const JsonEncoder.withIndent('  ').convert(value);

  static CallToolResult _json(Object? value) =>
      CallToolResult(content: [TextContent(text: _encode(value))]);

  /// Errors go back as tool results with [isError], not as protocol errors —
  /// "you named a plugin that does not exist" is something the model should
  /// read and correct, not a transport failure.
  static CallToolResult _error(String message) =>
      CallToolResult(isError: true, content: [TextContent(text: message)]);
}
