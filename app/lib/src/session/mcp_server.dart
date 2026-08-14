import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dart_mcp/server.dart';
import 'package:dart_mcp/stdio.dart';
import 'package:flutterware/plugins.dart';

// ignore: implementation_imports
import 'package:flutterware/src/log_client.dart';
import 'package:path/path.dart' as p;

import '../constants.dart';
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
         // The same constant `fw --version` prints. It was a literal here, and
         // this handshake was the only place a consumer could read the
         // version at all — which is the report that gave the CLI the command.
         implementation: Implementation(
           name: 'flutterware',
           version: flutterwareVersion,
         ),
         instructions:
             'Inspect and drive a Flutter project through its flutterware '
             'plugins. Start with flutterware_status; it loads and reports what '
             'every declared plugin knows. Anything that compiles, renders or '
             'spawns a process is an action — list them with '
             'flutterware_actions and run them with flutterware_invoke. '
             'To work on a *running* app, launch it with the run plugin and '
             'live in flutterware_act: edit, reload, act, observe. '
             'Whatever you are looking at — a live app (flutterware_act), a '
             'preview (previews.inspect) or a step a scenario captured '
             '(scenarios.read) — the reply is the same **screen**: the things '
             'carrying words or responding to touch, nested under the layout, '
             'with their boxes and their state. And it takes the same '
             'questions: `find` for where something is, `at` for what is '
             'under a point, `styles` for the type ramp, `tree` for all of it '
             '(expensive), and `lens: act|look|design|raw` for how much to '
             'hand back at once. Learn it once; it is the same everywhere.',
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

  /// How many rows of any one list a status reply carries.
  ///
  /// Chosen against what the plugins actually show: it keeps every device, every
  /// surface of a splash, every icon role and every scenario whole, and cuts
  /// only the catalogues — dependencies, preview entries — which are what their
  /// own actions answer in full.
  static const _statusViewRows = 10;

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
            //
            // And with the long lists cut short for the same reason: what was
            // left was still 10k tokens, three quarters of it rows naming every
            // dependency of every package — a catalogue this plugin has an
            // action for. The count of what was left out rides along, so a
            // reader that wants the rest knows there is a rest.
            for (var report in session.reports)
              report.toJson(includeActions: false, viewRows: _statusViewRows),
          ],
        });
      });

  static final _actionsTool = Tool(
    name: 'flutterware_actions',
    description:
        'Every action that can be invoked, per plugin. Call this before '
        'flutterware_invoke when you do not already know an action id. '
        'Without "plugin" it answers the index: every action of every plugin, '
        'with what it does and the names of the parameters it takes. Name a '
        'plugin to get that one in full — every parameter documented, and the '
        'shape of what comes back. Name an action too and it answers that one '
        'alone, which is the cheap ask when you already know what you are '
        'calling. In the full forms an action lists its parameters by key in '
        '"takes"; the keys are documented once each in the top-level '
        '"parameters", and "returns" names an entry in "types". Everything a '
        'key names is in the reply — a lookup never misses.',
    inputSchema: Schema.object(
      properties: {
        'plugin': Schema.string(
          description:
              'One plugin, in full: its id or the last dotted segment — '
              '"flutterware.previews" or just "previews". Omitted, the index.',
        ),
        'action': Schema.string(
          description:
              'One action of that plugin, alone — "act", "launch". Needs '
              '"plugin". Omitted, every action of the plugin.',
        ),
      },
    ),
  );

  /// The index, or one plugin in full.
  ///
  /// **Because the full answer does not fit.** Every parameter of every action
  /// documented is 34k tokens on flutterware's own repo — past the 25k a client
  /// hands a model, so the reply an agent got was a note saying it had been
  /// written to a file. The one documented way to learn an action id could not
  /// be read. The index is a twentieth of that and carries what a call usually
  /// needs — the id, what it does, what it takes — and the plugin that turns out
  /// to matter is one more round trip away, in full.
  Future<CallToolResult> _actions(CallToolRequest request) => _withSession((
    session,
  ) async {
    var requested = request.arguments?['plugin'] as String?;
    var wantedAction = request.arguments?['action'] as String?;
    if (requested == null && wantedAction != null) {
      return _error(
        'naming an action needs the plugin it belongs to — '
        '{"plugin": "run", "action": "$wantedAction"}. Without "plugin" this '
        'answers the index of every plugin.',
      );
    }
    if (requested == null) {
      return _json({
        'plugins': [
          for (var report in session.reports)
            {
              'id': report.id,
              'label': report.label,
              'actions': [
                for (var action in report.actions)
                  {
                    'id': action.id,
                    'description': ?action.description,
                    // Names only. Enough to call a parameterless action, or
                    // one whose parameters say what they are; anything else
                    // is what naming the plugin is for.
                    if (action.parameters.isNotEmpty)
                      'takes': [
                        for (var parameter in action.parameters) parameter.id,
                      ],
                  },
              ],
            },
        ],
      });
    }

    PluginCore core;
    try {
      core = session.requireCore(requested);
    } on SessionException catch (e) {
      return _error('$e');
    }
    var report = core.report;
    var actions = report.actions;
    if (wantedAction != null) {
      var one = actions.where((a) => a.id == wantedAction).toList();
      if (one.isEmpty) {
        return _error(
          '"$wantedAction" is not an action of ${report.id}. It has: '
          '${actions.map((a) => a.id).join(', ')}.',
        );
      }
      actions = one;
    }
    return _json(_describeActions(report.id, report.label, actions));
  });

  /// One plugin's actions, with everything they share said once.
  ///
  /// **The repetition was the size.** Measured on `run` 2026-08-13: 93KB, of
  /// which `act`, `observe` and `navigate` were 45KB between them — three
  /// actions that take the same twenty-odd parameters and hand back the same
  /// `RunActResult`, spelled out three times. `RunControlResult` appeared four
  /// times. Nothing was wrong with any of it; it was just said over and over.
  ///
  /// So a parameter and a result shape are each documented once, in a table,
  /// and an action names them. A parameter id that means the *same* thing
  /// everywhere it appears is keyed by that id; one that differs between two
  /// actions is keyed `<action>.<id>`, so a key is never a claim that two
  /// different things are one. Every key in `takes` is in `parameters`, and
  /// every `returns` with a known shape is in `types` — a reader never has to
  /// guess whether a lookup will land.
  Map<String, Object?> _describeActions(
    String id,
    String label,
    List<PluginAction> actions,
  ) {
    // **The commonest spelling of an id wins the plain key; the odd ones out
    // get scoped.** Not "shared only if every action agrees" — that was the
    // first rule and it collapsed: `run` has sixteen actions taking `device`,
    // fifteen of them word for word and only `launch` saying something else,
    // and one disagreement scoped all sixteen. Majority-wins hoists the fifteen
    // and leaves `launch.device` standing on its own, which is the honest
    // reading of what is actually shared.
    //
    // Compared on the encoded form, because that is exactly what would have
    // been repeated.
    var spellings = <String, Map<String, int>>{};
    for (var action in actions) {
      for (var parameter in action.parameters) {
        var counts = spellings[parameter.id] ??= <String, int>{};
        var encoded = jsonEncode(parameter.toJson());
        counts[encoded] = (counts[encoded] ?? 0) + 1;
      }
    }
    // The winner per id, by count; ties broken by the encoding so two runs of
    // the same session never disagree about which one is `device`.
    var winner = {
      for (var entry in spellings.entries)
        entry.key:
            (entry.value.entries.toList()..sort((a, b) {
                  var byCount = b.value.compareTo(a.value);
                  return byCount != 0 ? byCount : a.key.compareTo(b.key);
                }))
                .first
                .key,
    };

    var parameters = <String, Object?>{};
    var takes = <String, List<String>>{};
    for (var action in actions) {
      var keys = <String>[];
      for (var parameter in action.parameters) {
        var encoded = jsonEncode(parameter.toJson());
        var key = encoded == winner[parameter.id]
            ? parameter.id
            : '${action.id}.${parameter.id}';
        keys.add(key);
        parameters[key] = parameter.toJson();
      }
      takes[action.id] = keys;
    }

    var types = <String, Object?>{};
    for (var action in actions) {
      if (action.returnsName case var name?) {
        // Read from generated data — the extraction ran at build time.
        if (resultShapes[name] case var shape?) types[name] = shape.toJson();
      }
    }

    return {
      'plugins': [
        {
          'id': id,
          'label': label,
          'actions': [
            for (var action in actions)
              {
                ...action.toJson()..remove('parameters'),
                if (takes[action.id] case var ids? when ids.isNotEmpty)
                  'takes': ids,
              },
          ],
        },
      ],
      if (parameters.isNotEmpty) 'parameters': parameters,
      if (types.isNotEmpty) 'types': types,
    };
  }

  static final _invokeTool = Tool(
    name: 'flutterware_invoke',
    description:
        'Run one plugin action. Argument keys are the parameter ids reported '
        'by flutterware_actions. Returns whatever the action produced — often '
        'a path to an artifact. A slow action narrates: ask for progress and '
        'what the panel is saying arrives as it changes — the entry being '
        'compiled, the point of a matrix, the launcher building an app.',
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

    PluginCore core;
    try {
      // Resolved before the job rather than from it, so progress can be
      // followed from before the first line: `invoke` starts the action
      // running, and a plugin that says something in its first synchronous
      // step would have said it into an empty room.
      core = session.requireCore(pluginName);
    } on SessionException catch (e) {
      // The message names what *is* declared, so a model that guessed wrong
      // can correct itself without a second round-trip.
      return _error('$e');
    }

    var stopFollowing = _followProgress(core, request.meta?.progressToken);
    var job = session.invoke(pluginName, actionId, arguments: arguments);
    var result = await job.done;
    stopFollowing();
    if (!result.ok) return _error(describeJobError(result.error!));

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

  /// Forwards what the plugin is saying about itself while the job runs, and
  /// returns the way to stop.
  ///
  /// **The line the panel is showing, and nothing invented.** A core moves its
  /// report's status as it works — `building`, `2 of 40 · 3 broken`, `Syncing
  /// files to device macOS` — because that is what the sidebar renders, and
  /// [PluginCore.changes] is the same bump every renderer already subscribes
  /// to. So an agent watching a three-minute action reads what a human beside
  /// it would read, out of one source. A plugin that says nothing while it
  /// works sends nothing: silence is honest, and a heartbeat that only means
  /// "still alive" is what a timeout is for.
  ///
  /// Only when the client asked. The token is the opt-in the protocol defines
  /// — no token, no traffic — and the notifications never extend a client's
  /// timeout, so this buys visibility rather than patience.
  void Function() _followProgress(PluginCore core, ProgressToken? token) {
    if (token == null) return () {};
    var sent = 0;
    // Seeded with what the plugin is already saying, because this subscribes
    // before the action starts: a device count from before the call, or a
    // failure from this morning's build, is not progress. What the action says
    // next is.
    var said = _progressLines(core);
    var subscription = core.changes.stream.listen((_) {
      // The bump carries no payload, so most of them are about something else
      // entirely — a report is one object and any part of it moving rings this
      // bell. Only a changed line is progress.
      for (var line in _progressLines(core).entries) {
        if (said[line.key] == line.value) continue;
        said[line.key] = line.value;
        notifyProgress(
          ProgressNotification(
            progressToken: token,
            // Monotonic and unitless: the protocol asks progress to increase
            // and takes `total` as optional. A count of things said is the only
            // honest number here — an action that knows its own denominator
            // says so in its message.
            progress: ++sent,
            message: line.value,
          ),
        );
      }
    });
    return () => unawaited(subscription.cancel());
  }

  /// What the plugin is saying right now, keyed by who is saying it.
  ///
  /// The plugin *and* its children, because which one carries the news depends
  /// on the plugin: previews moves its own line while it audits, and a run
  /// moves the row of the app being built — `Studio (dev) · macOS: Syncing
  /// files to device macOS…` — while its own line goes on counting devices.
  /// Keying by speaker is what lets both be followed without either drowning
  /// the other in repeats.
  static Map<String, String> _progressLines(PluginCore core) {
    var report = core.report;
    return {
      if (!report.status.isEmpty) '': report.status.message,
      for (var child in report.children)
        if (!child.status.isEmpty)
          child.id: '${child.label}: ${child.status.message}',
    };
  }

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
        'screenshot, visible texts, what it printed since the last step, and '
        'what the human tapped since the last step (`human`) — nothing to '
        'correlate. Targets resolve inside the app at act time, '
        'retry through route transitions, and are refused loudly with the '
        'screen they were refused on; a silent wrong-target tap cannot '
        'happen. `settled` is about painting, not about loading: false means '
        'the budget ran out with the app still animating (normal for a '
        'spinner, act anyway), and true means nothing is animating — a '
        'pending fetch schedules no frame, so a screen still reading '
        '"Loading…" reports settled: true and wants another wait. Needs an '
        'app '
        'launched by flutterware (run.launch). Every step is archived whole '
        "— picture, tree, semantics, texts and a manifest — under the reply's "
        "`capture`, and the reply's `journal` is the JSON-lines index of all "
        'of them with absolute paths, so a client that can read files can go '
        'back to any step without asking. Read the `.png` and the '
        '`.capture.json` that way; do not read a `.tree.json`, which is ~120KB '
        'of raw nodes — that is what screen/find/at/styles exist to spare you. '
        "The GUI's Steps tab renders the same journal. On a phone, keep "
        'the app in the foreground: iOS suspends a backgrounded app and it '
        'answers nothing until somebody brings it back — you get a timeout '
        'saying exactly that, and `{"verb": "foreground", "layer": '
        '"native"}` is how you fix it yourself. A hidden desktop window and '
        'a backgrounded Android app both drive fine. When a target is '
        'refused for something you can see in the screenshot but not in the '
        "texts — a permission dialog, a webview's contents — retry it with "
        'layer: native. For flows '
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
              'the opening move, and the call after a reload. On '
              'layer: native: observe | tap | enterText | foreground.',
        ),
        'layer': Schema.string(
          description:
              "Which tree to address. Omit for the app's own widget tree — "
              'fast, exact, and where everything Flutter draws lives. '
              '"native" addresses the platform\'s accessibility tree '
              'instead: slower (Android ~4s a step, iOS simulator ~0.6s) but '
              'it sees what Flutter cannot — permission dialogs and other '
              'native popups, the contents of a webview or map, another app '
              'the flow jumped to — and its screenshot is the real device '
              'screen rather than a raster of the Flutter layer. Two limits '
              'worth knowing: on Android the tree is the focused window, so '
              'a dialog is fully there but the soft keyboard is not; on '
              'macOS it is for native chrome, because a Flutter app usually '
              'publishes none of its own widgets to macOS accessibility — '
              'some processes do, and then you simply see more. '
              'Use verb: foreground here to bring back a suspended iOS app.',
        ),
        'target': Schema.string(
          description:
              'Bare text matches a visible string. JSON names the rest: '
              '{"key": …}, {"label": …}, {"tooltip": …}, {"containing": …}, '
              '{"within": {"scope": …, "child": …}}, '
              '{"nth": {"target": …, "index": …}}. A reply text ending in … '
              'was truncated — target it with {"containing": <prefix>}, not '
              'the truncated string. On layer: native the same grammar minus '
              'key/tooltip/within, plus {"role": …} and {"at": {"x": …, '
              '"y": …}} for a point no element covers — divide a point read '
              "off the screenshot by the reply's screenshotScale first.",
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
              'Settle budget, default 800. Running out is reported, never an '
              'error. It waits on frames, tickers and image decodes — a '
              'pending fetch is invisible to it, so raising this does not '
              'make a loading screen finish; `wait` and observe again does.',
        ),
        'lens': Schema.string(
          description:
              'How much to hand back, as one word, for this call: "act" (the '
              'screen alone — the default, and what nearly every step wants), '
              '"look" (+ the picture), "design" (+ every text style on the '
              'screen), "raw" (+ the whole widget tree, ~20,000 tokens). Any '
              'flag you name explicitly beats it. To keep one shape for a '
              'stretch of work, pin it once with the run plugin\u2019s `lens` '
              'action instead of repeating it — replies say which lens shaped '
              'them, and mark a pinned one.',
        ),
        'item': Schema.int(
          description:
              "Act on the numbered thing from the last reply's screen, "
              'instead of naming a target. The way past "2 widgets match", '
              'and the only way to reach a control with no words. Resolved to '
              "that item's box centre and then through the usual ladder, so "
              'covered or gone is still refused. Numbers are per observation.',
        ),
        'screen': Schema.bool(
          description:
              'What is on the screen and what can be done to it — every '
              'control and every text, with its words, its box and whether '
              'it is the current one of its group, nested under the panes '
              'and lists that hold them. On by default, and the thing to '
              'read first: a twentieth of the tree, and it answers more, '
              'because a tree cannot say which control is disabled or which '
              'tab is selected. Pass false when you only want the picture.',
        ),
        'find': Schema.string(
          description:
              'Report only nodes whose type, description or accessibility '
              'label contains this — "ElevatedButton", "Save". The cheap way '
              "to a widget's colour, size and source, and how to get a node "
              'id without reading a tree first.',
        ),
        'at': Schema.string(
          description:
              'Report the chain of widgets under this point, as "x,y" in '
              'logical pixels — the same space every box in this reply uses, '
              'so a box centre from `screen` needs no translation. Outermost '
              'first, capped at the innermost eight. Where the layout answers '
              'are: the Row three levels out is what has the alignment.',
        ),
        'styles': Schema.bool(
          description:
              'Every distinct size/weight/colour of text on screen, most-used '
              'first, with a sample each — the type ramp and the palette as '
              'one small table. What to ask instead of reading a tree when '
              'the question is "are these two greys the same grey".',
        ),
        'tree': Schema.bool(
          description:
              'Include the widget tree inline. Off by default and the '
              'heaviest thing in a reply by an order of magnitude — `screen` '
              'says what is there, and find/at/styles answer most of what a '
              'whole tree gets read for. Scope it with treeRoot, treeDepth '
              'and treeNoise.',
        ),
        'treeRoot': Schema.string(
          description:
              'Report this node and everything under it instead of the whole '
              'tree — a node id from an earlier read of the same screen, like '
              '"0/3/1/0". An id names a position, so one from a screen that '
              'has changed is refused rather than guessed at.',
        ),
        'treeDepth': Schema.int(
          description:
              'How many levels below the reported root to include, counted '
              'after the noise filter. A node whose children were cut says '
              'how many with `elided`, so a bounded read is never mistaken '
              'for a complete one.',
        ),
        'treeNoise': Schema.bool(
          description:
              "Default true: drop widgets that share their only child's box "
              '— MouseRegion, GestureDetector, Gap, Expanded and the rest of '
              'the wrappers — keeping whichever of the two carries the words, '
              'the flex or the properties. Ids never move, so a surviving '
              'child can sit directly under a node that is not its parent. '
              'Pass false when the question is about the wrappers themselves.',
        ),
        'screenshot': Schema.bool(
          description:
              'Return the picture, not just archive it. Every step is '
              'photographed either way and the frame is on disk under the '
              "reply's `capture` — this decides whether it enters your "
              'context, at ~810 tokens. Off by default: `screen` answers most '
              'of what a picture used to be read for. Ask for it when the '
              'question is how something *looks*; it attaches itself when a '
              'step is refused or the app throws.',
        ),
        'maxSide': Schema.int(
          description:
              "Cap the screenshot's longest side in pixels. 900 by default.",
        ),
        'device': Schema.string(
          description: 'Which device, when more than one app is running.',
        ),
        'entrypoint': Schema.string(
          description: 'Which entry point, when a device runs more than one.',
        ),
        'worktree': Schema.string(
          description:
              'Worktree name or path, to drive a run another checkout '
              'launched. Only runs from this worktree match when omitted — '
              'the refusals name the worktrees that have one.',
        ),
        'run': Schema.string(
          description:
              'The run key, when nothing else separates two runs — two '
              'Studios on one device from one worktree. The ambiguity refusal '
              'lists the keys; `apps` reports them too.',
        ),
      },
      required: ['verb'],
    ),
  );

  /// Every property `_actTool` advertises, and nothing else. The schema and
  /// this list drift independently — an argument declared but not forwarded
  /// is silently dropped, and the refusal that told the agent to pass it
  /// becomes a dead end — so a test asserts they stay equal.
  static const actArguments = [
    'verb',
    'layer',
    'target',
    'item',
    'lens',
    'text',
    'route',
    'dx',
    'dy',
    'waitMs',
    'settleMs',
    'screen',
    'find',
    'at',
    'styles',
    'tree',
    'treeRoot',
    'treeDepth',
    'treeNoise',
    'screenshot',
    'maxSide',
    'device',
    'entrypoint',
    'worktree',
    'run',
  ];

  Future<CallToolResult> _act(CallToolRequest request) =>
      _withSession((session) async {
        var arguments = <String, Object?>{
          for (var key in actArguments) key: ?request.arguments?[key],
        };

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
