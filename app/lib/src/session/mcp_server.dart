import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dart_mcp/server.dart';
import 'package:flutterware/plugins.dart';
import 'package:path/path.dart' as p;

import '../plugins/plugin_core.dart';
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
  }) : workingDirectory = workingDirectory ?? Directory.current,
       super.fromStreamChannel(
         implementation: Implementation(name: 'flutterware', version: '0.5.2'),
         instructions:
             'Inspect and drive a Flutter project through its flutterware '
             'plugins. Start with flutterware_status; it reports what every '
             'declared plugin currently knows. Reading never triggers work, so '
             'a cold project reports "not computed" until you pass '
             'compute: true or invoke an action.',
       ) {
    registerTool(_statusTool, _status);
    registerTool(_actionsTool, _actions);
    registerTool(_invokeTool, _invoke);
  }

  /// Where to resolve the project from. A session walks up to the repo root,
  /// so any directory inside the project works.
  final Directory workingDirectory;

  /// Which cores this server exposes. Null means the default set.
  final PluginCoreRegistry? registry;

  Future<T> _withSession<T>(FutureOr<T> Function(Session) body) async {
    var session = await Session.open(workingDirectory, registry: registry);
    try {
      return await body(session);
    } finally {
      session.dispose();
    }
  }

  static final _statusTool = Tool(
    name: 'flutterware_status',
    description:
        'What every declared flutterware plugin currently says about itself: '
        'status, sub-entries per package, and a text projection of the panel. '
        'Reading is free and never starts work — an untouched project reports '
        '"not computed". Set compute to true to load it first, which can take '
        'seconds.',
    inputSchema: Schema.object(
      properties: {
        'compute': Schema.bool(
          description:
              'Load what has not been loaded before reporting. Off by default '
              'so a status check cannot silently scan or compile a project.',
        ),
      },
    ),
  );

  Future<CallToolResult> _status(CallToolRequest request) =>
      _withSession((session) async {
        if (request.arguments?['compute'] == true) {
          for (var core in session.cores) {
            await core.computeAll();
          }
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
        'each one takes. Call this before flutterware_invoke when you do not '
        'already know an action id.',
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
                'actions': [for (var a in report.actions) a.toJson()],
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

    var core = session.coreByShortName(pluginName);
    if (core == null) {
      return _error(
        'No plugin "$pluginName". Declared: '
        '${session.cores.map((c) => c.id).join(', ')}',
      );
    }

    var arguments =
        (request.arguments?['arguments'] as Map?)?.cast<String, Object?>() ??
        const <String, Object?>{};
    try {
      var result = await core.invoke(actionId, arguments: arguments);
      var summary = {
        'plugin': core.id,
        'action': actionId,
        'result': result is Artifact ? result.toJson() : result,
        // The report after the fact, so an agent sees what changed without
        // a second round-trip.
        'report': core.report.toJson(),
      };

      // An image artifact comes back as an image, not as a path. An agent
      // asked to screenshot something wants to *see* it, and a path it cannot
      // open is the difference between a working tool and a plausible one. The
      // JSON travels alongside, so the address and the resolved axes are still
      // there to ask for the same frame again.
      if (result is Artifact && result.kind.startsWith('image/')) {
        var file = File(p.join(session.root, result.path!));
        if (file.existsSync()) {
          return CallToolResult(
            content: [
              ImageContent(
                data: base64Encode(file.readAsBytesSync()),
                mimeType: result.kind,
              ),
              TextContent(text: _encode(summary)),
            ],
          );
        }
      }

      return _json(summary);
    } on ArgumentError catch (e) {
      return _error('${e.message} (${e.name})');
    }
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
