import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dart_mcp/server.dart';
import 'package:dart_mcp/stdio.dart';
import 'package:flutterware/plugins.dart';

// ignore: implementation_imports
import 'package:flutterware/src/log_client.dart';
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
/// only when a good name beats a discovery round-trip — which exactly one
/// has: `flutterware_act`, the drive loop's hot path.
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
             'flutterware_actions and run them with flutterware_invoke. '
             'To work on a *running* app, launch it with the run plugin and '
             'live in flutterware_act: edit, reload, act, observe.',
       ) {
    registerTool(_statusTool, _status);
    registerTool(_actionsTool, _actions);
    registerTool(_invokeTool, _invoke);
    registerTool(_actTool, _act);
  }

  /// Every tool this server exposes, in the order it registers them.
  ///
  /// Public because the capability document is generated from it rather than
  /// from a hand-kept list — and `mcp_server_test` asserts a connected client
  /// sees exactly these, so the document cannot describe a surface that is not
  /// there.
  static List<Tool> get tools => [
    _statusTool,
    _actionsTool,
    _invokeTool,
    _actTool,
  ];

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
            Session.open(
              workingDirectory,
              registry: registry,
              // Sessions log, and the default sink is stdout — which here is
              // the wire. A plugin that logs while loading would not be noisy,
              // it would be a corrupt frame, so the sink is part of opening a
              // session on this surface rather than something to remember.
              logger: LogClient.writeTo(stderr),
            ));
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
        'touches the network; that work lives behind flutterware_invoke. What '
        'each plugin can be *told to do* is flutterware_actions, not this.',
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
          'plugins': [
            // Without the declarations, which is what the other tool is for.
            // Carrying them here made this call three quarters a duplicate of
            // flutterware_actions — 33k tokens of first contact on
            // flutterware's own repo, before a question had been asked.
            for (var report in session.reports)
              report.toJson(includeActions: false),
          ],
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
              'Plugin id, or its last dotted segment: "flutterware.scenarios" or '
              'just "scenarios".',
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
      //
      // **Its status, its children and its view — not its declarations.** What
      // changed is the first three; the fourth is the same static list the
      // caller read once from flutterware_actions, and repeating it made a
      // screenshot's reply 94% boilerplate. An agent iterating on a widget
      // calls this every edit, so that was the cost paid most often here: ~6.9k
      // tokens per call on the sample project, ~9.8k on flutterware's own repo.
      'report': core.report.toJson(includeActions: false),
    };

    return _jsonWithImage(session, artifact, summary);
  });

  /// One drive transaction, promoted to its own tool.
  ///
  /// The gui-cli-mcp architecture reserved promotion for "the drive loop,
  /// decided with a real client in front of us" — this is that loop. An agent
  /// iterating on a live app calls this every step; making it ride
  /// flutterware_invoke would cost a discovery round-trip to learn the one
  /// action the whole session is made of.
  static final _actTool = Tool(
    name: 'flutterware_act',
    description:
        'One transaction against the running app — the loop tool for live '
        'work: edit code, hot-reload (flutterware_invoke run.reload), then '
        'act or observe here. Every reply is one settled moment of the app: '
        'screenshot, visible texts, what it printed since the last step — '
        'nothing to correlate. Targets resolve inside the app at act time, '
        'retry through route transitions, and are refused loudly with the '
        'screen they were refused on; a silent wrong-target tap cannot '
        'happen. `settled: false` means the budget ran out with the app '
        'still animating — normal for a spinner, act anyway. Needs an app '
        'launched by flutterware (run.launch); every step lands in the '
        "run's journal, reviewable in the GUI's Steps tab. On a phone, keep "
        'the app in the foreground: iOS suspends a backgrounded app and it '
        'answers nothing until somebody brings it back — you get a timeout '
        'saying exactly that. A hidden desktop window and a backgrounded '
        'Android app both drive fine. For flows '
        'expressible headlessly, scenarios are milliseconds and '
        'deterministic — reach for this tool when it must be the real '
        'thing: real backend, real data, real device, or the flutterware '
        'GUI itself.',
    inputSchema: Schema.object(
      properties: {
        'verb': Schema.string(
          description:
              'tap | longPress | drag | scrollTo | enterText | back | wait '
              '| observe | navigate. observe is the act-less transaction — '
              'the opening move, and the call after a reload.',
        ),
        'target': Schema.string(
          description:
              'Bare text matches a visible string. JSON names the rest: '
              '{"key": …}, {"label": …}, {"tooltip": …}, {"containing": …}, '
              '{"within": {"scope": …, "child": …}}, '
              '{"nth": {"target": …, "index": …}}.',
        ),
        'text': Schema.string(
          description: 'What enterText types, as one editing value.',
        ),
        'route': Schema.string(
          description:
              'For navigate — needs the app to have registered a '
              'navigation handler.',
        ),
        'dx': Schema.num(description: 'Drag distance, logical px.'),
        'dy': Schema.num(
          description: 'Drag distance; negative moves the finger up.',
        ),
        'waitMs': Schema.int(description: 'For wait: real milliseconds.'),
        'settleMs': Schema.int(
          description:
              'Settle budget, default 800. Running out is reported, '
              'never an error.',
        ),
        'tree': Schema.bool(
          description:
              'Include the widget tree inline. Off by default — thousands '
              'of tokens on a real app; the texts ride along either way.',
        ),
        'maxSide': Schema.int(
          description:
              "Cap the screenshot's longest side in pixels. Default 1200 "
              'here.',
        ),
        'device': Schema.string(
          description: 'Which device, when more than one app is running.',
        ),
        'entrypoint': Schema.string(
          description: 'Which entry point, when a device runs more than one.',
        ),
      },
      required: ['verb'],
    ),
  );

  Future<CallToolResult> _act(CallToolRequest request) =>
      _withSession((session) async {
        var arguments = <String, Object?>{
          for (var key in const [
            'verb',
            'target',
            'text',
            'route',
            'dx',
            'dy',
            'waitMs',
            'settleMs',
            'tree',
            'maxSide',
            'device',
            'entrypoint',
          ])
            key: ?request.arguments?[key],
        };
        arguments.putIfAbsent('maxSide', () => 1200);

        Job job;
        try {
          job = session.invoke('run', 'act', arguments: arguments);
        } on SessionException catch (e) {
          return _error('$e');
        }
        var result = await job.done;
        if (!result.ok) return _error(describeJobError(result.error!));

        // Lean on purpose: no report attach. This is the call an agent makes
        // most; the act result is the whole story of the step.
        var summary = {
          'result': switch (result.value) {
            PluginResult data => data.toJson(),
            var other => other,
          },
        };
        var artifact = result.artifacts.isEmpty ? null : result.artifacts.first;
        return _jsonWithImage(session, artifact, summary);
      });

  /// An image artifact comes back as an image, not as a path. An agent
  /// asked to screenshot something wants to *see* it, and a path it cannot
  /// open is the difference between a working tool and a plausible one. The
  /// JSON travels alongside, so the address and the resolved axes are still
  /// there to ask for the same frame again.
  static CallToolResult _jsonWithImage(
    Session session,
    Artifact? artifact,
    Map<String, Object?> summary,
  ) {
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
  }

  /// Compact, unlike the CLI's `--json`.
  ///
  /// The reader here is a model, and indentation is the one thing on this wire
  /// that no reader benefits from: it was 47% of a `flutterware_actions` reply
  /// and 39% of a status. `fw --json` keeps its indentation — that one is read
  /// by a person and piped into `jq`.
  static String _encode(Object? value) => jsonEncode(value);

  static CallToolResult _json(Object? value) =>
      CallToolResult(content: [TextContent(text: _encode(value))]);

  /// Errors go back as tool results with [isError], not as protocol errors —
  /// "you named a plugin that does not exist" is something the model should
  /// read and correct, not a transport failure.
  static CallToolResult _error(String message) =>
      CallToolResult(isError: true, content: [TextContent(text: message)]);
}

/// Serves the tools on this process's stdio, completing when the client hangs
/// up.
///
/// The one implementation of "flutterware as an MCP server". `fw mcp` and
/// `app/bin/mcp.dart` both call it and neither adds anything, so the reachable
/// surface and the one the tests drive cannot come apart.
Future<void> serveMcpOnStdio({Directory? workingDirectory}) {
  var server = FlutterwareMcpServer(
    stdioChannel(input: stdin, output: stdout),
    workingDirectory: workingDirectory,
  );
  return server.done;
}
