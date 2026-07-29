import 'dart:convert';
import 'dart:io';

import 'package:flutterware/plugins.dart';

import '../constants.dart';
import '../plugins/plugin_core.dart';
import '../shell/repo_layout.dart';
import '../utils/flutter_sdk.dart';
import 'action_shapes.generated.dart';
import 'gui.dart';
import 'init.dart';
import 'job.dart';
import 'session.dart';

/// One `fw` command, as data.
///
/// This list is the only place a command's name, usage and summary are
/// written. `fw help` renders it and so does `docs/capabilities.md`; a command
/// added here appears in both without either being touched, which is the
/// arrangement that stops a document describing a flag that no longer exists.
class FwCommand {
  const FwCommand(
    this.name, {
    required this.usage,
    required this.summary,
    this.details,
  });

  final String name;

  /// How it is spelled, without the leading `fw`.
  final String usage;

  /// One line, for the command list.
  final String summary;

  /// The rest, for `fw help <command>` and for the document.
  final String? details;
}

const fwCommands = [
  FwCommand(
    'status',
    usage: 'status [--json]',
    summary: 'what every plugin says about itself',
    details:
        'Loads what each plugin has not loaded yet, then reports. A `fw` '
        'process\nstarts cold every time, so a run that reported only cached '
        'state would\nsay "not computed" for everything, every time.\n\n'
        'Loading is parsing — pubspecs, demo files. Nothing here compiles, '
        'spawns\na daemon or touches the network; that work lives behind '
        '`fw run`.',
  ),
  FwCommand(
    'actions',
    usage: 'actions [--json]',
    summary: 'what can be invoked, and with what',
    details:
        'The same list the GUI draws buttons from and an agent reads over '
        'MCP.\nThere is no second source for it.',
  ),
  FwCommand(
    'run',
    usage: 'run <plugin> <action> [--k=v]',
    summary: 'invoke one action',
    details:
        '`<plugin>` may be a full id or its last dotted segment.\n'
        '\n'
        '  fw run <plugin>                  the actions that plugin has\n'
        '  fw run <plugin> <action> --help  what it takes, and what it '
        'returns\n'
        '\n'
        'An artifact prints as its path, so `fw run … | xargs open` works.\n'
        'Structured results print as JSON. `--json` prints the whole '
        'artifact:\naddress, resolved axes and all.',
  ),
  FwCommand(
    'init',
    usage: 'init',
    summary: 'record what this project needs, once',
    details:
        'Writes `.flutterware/`: which Flutter SDK to use, taken from the one\n'
        'that ran this command rather than guessed at later. Adds the '
        'directory\nto .gitignore if nothing already covers it, and writes a '
        'starter\ntool/flutterware.dart if the project has none.\n'
        '\n'
        'It runs by itself the first time you use flutterware in a project, '
        'so\nthis is here for scripts, for CI, and for running it again after '
        'a\nchange of SDK.',
  ),
  FwCommand(
    'app',
    usage: 'app [--release] [--json]',
    summary: 'open the flutterware GUI',
    details:
        'What `dart run flutterware` with no arguments does, spelled out.\n'
        '\n'
        "The first run builds the GUI. That build's output goes to\n"
        '`app/build/gui-build.log` rather than to the terminal; a failure\n'
        'prints the end of it and where the rest is, and `--json` reports the\n'
        'same thing as data.\n'
        '\n'
        'The GUI is one renderer of the plugin contract and this is one\n'
        'command of the CLI — it is not a separate program, and there is no\n'
        'capability it has that the commands above do not.\n'
        '\n'
        'When flutterware is a path dependency — when you are working on\n'
        'flutterware itself — this runs the GUI under `flutter run`, so a\n'
        'change is `r` away instead of a rebuild. `--release` takes the built\n'
        'binary instead, which is what an ordinary install always gets.',
  ),
  FwCommand(
    'help',
    usage: 'help [<command>]',
    summary: 'this, or one command in detail',
  ),
];

/// Closes `fw help`, and the document's CLI section.
const fwHelpFooter =
    'Run `fw help <command>` for detail, or `fw actions` for what this '
    'project can do.';

/// What `fw` exits with — here because the document lists them too.
const fwExitCodes = {
  0: 'success',
  1: 'the action ran and failed',
  64: 'a usage error: unknown plugin, bad argument, malformed command line',
};

/// The CLI renderer of the plugin contract — `fw`, minus the process.
///
/// A class rather than a `main`, and its output goes to injected sinks rather
/// than to `stdout`, for one reason: **what `fw` does has to be testable
/// against what MCP does.** The parity rule is only checkable if both surfaces
/// can be driven by the same test over the same session, and a `bin/` file
/// nothing can import cannot be.
///
/// `bin/fw.dart` is what remains: an `exitCode` and one call.
class FwCli {
  FwCli({
    required this.openSession,
    required this.out,
    required this.err,
    this.launchGui,
  });

  /// How to get a session. A function rather than a session, because `help`
  /// and a bad command line must not open one — running the project's config
  /// file to be told the command was misspelled is a second's wait for nothing.
  final Future<Session> Function() openSession;

  final StringSink out;
  final StringSink err;

  /// Opens the GUI. Injected so a test can drive `app` without a window and
  /// without an SDK; the default reads what the launcher recorded in the
  /// environment.
  final Future<int> Function({required bool forceBuild})? launchGui;

  Future<int> run(List<String> arguments) async {
    // No arguments opens the GUI, because that is what `dart run flutterware`
    // has always done and the point of this CLI is that it is the same
    // program, not a different one with different habits.
    var command = arguments.isEmpty ? 'app' : arguments.first;
    var rest = arguments.skip(1).toList();
    var json = rest.remove('--json');

    try {
      // Initializing is not a step someone should have to be told about: this
      // process already knows everything `init` records. `help` is excluded so
      // that reading the help for a project you have not adopted yet does not
      // write to it.
      if (command != 'help' && command != 'init') await _autoInit();

      return switch (command) {
        'init' => await _init(),
        'status' => await _status(json: json),
        'actions' => await _actions(json: json),
        'run' => await _run(rest, json: json),
        'app' => await _app(
          forceBuild: rest.remove('--$forceCompileOption'),
          release: rest.remove('--release'),
          json: json,
        ),
        'help' || '--help' || '-h' => _help(rest.firstOrNull),
        _ => fail('unknown command "$command". Try `fw help`.'),
      };
    } on SessionException catch (e) {
      err.writeln('fw: $e');
      return 1;
    }
  }

  /// Records the SDK and the rest of `.flutterware/`.
  Future<int> _init({bool quiet = false}) async {
    var init = _projectInit();
    if (init == null) {
      return fail(
        'not inside a project: ${Directory.current.path}\n'
        'Run this from a Flutter project — one with a pubspec.yaml.',
      );
    }
    return init.run(quiet: quiet);
  }

  /// Initializes silently when the project has not been, so no command has to
  /// begin by refusing.
  ///
  /// Only when the launcher told us which `dart` it used. A test driving
  /// [FwCli] directly has no launcher, and must not have its working directory
  /// written to as a side effect of calling a command.
  Future<void> _autoInit() async {
    var init = _projectInit();
    if (init == null || init.isInitialized) return;
    await init.run(quiet: true);
  }

  ProjectInit? _projectInit() {
    var dartExecutable = Platform.environment[dartExecutableEnvironmentKey];
    if (dartExecutable == null) return null;
    var root = findRepoRoot(Directory.current.path);
    if (root == null) return null;
    return ProjectInit(
      root: root,
      dartExecutable: dartExecutable,
      out: out,
      err: err,
    );
  }

  /// Builds the GUI if it is missing, then runs it.
  ///
  /// The context comes from the environment because this process is an AOT
  /// binary: `Platform.resolvedExecutable` is this executable, so the SDK
  /// cannot be found by walking up from it. The launcher ran under `dart run`
  /// and therefore knew — which is the same "record, do not discover" rule the
  /// adoption story applies to `.flutterware/sdk`.
  Future<int> _app({
    required bool forceBuild,
    required bool release,
    required bool json,
  }) async {
    if (launchGui case var launch?) return launch(forceBuild: forceBuild);

    var appToolPath = Platform.environment[appPathEnvironmentKey];
    var dartExecutable = Platform.environment[dartExecutableEnvironmentKey];
    if (appToolPath == null || dartExecutable == null) {
      return fail(
        'the GUI has to be started through the launcher, which is what '
        'knows\nwhich SDK and which copy to use:\n\n    dart run flutterware',
      );
    }

    var sdk = await FlutterSdkPath.tryFind(dartExecutable);
    if (sdk == null) {
      return fail(
        'no Flutter SDK above $dartExecutable.\n'
        'Run flutterware with the `dart` from a Flutter SDK, not a standalone '
        'one.',
      );
    }

    return GuiLauncher(
      appToolPath: appToolPath,
      flutterSdk: sdk.root,
      projectDirectory: Directory.current,
      out: out,
      err: err,
      editableSources:
          Platform.environment[editableSourcesEnvironmentKey] == 'true',
      json: json,
    ).run(forceBuild: forceBuild, release: release);
  }

  /// Everything every plugin says about itself.
  ///
  /// Computes first. Reading a report never starts work — that rule protects
  /// the GUI, where a sidebar row reads one per frame — but a `fw` process has
  /// no such history: it opens a session, reads, and exits. Reporting only
  /// cached state here would print "not computed" for every package on every
  /// run, which is the config file read back rather than a status.
  Future<int> _status({required bool json}) async {
    var session = await openSession();
    try {
      for (var core in session.cores) {
        await core.computeAll();
      }

      if (json) {
        _printJson({
          'root': session.root,
          'worktree': session.worktree.branch ?? session.worktree.path,
          'plugins': [for (var report in session.reports) report.toJson()],
        });
        return 0;
      }

      if (session.cores.isEmpty) {
        out.writeln('No plugins declared in tool/flutterware.dart.');
        return 0;
      }
      for (var report in session.reports) {
        out.writeln(report.toText());
        out.writeln();
      }
      return 0;
    } finally {
      session.dispose();
    }
  }

  /// What can be invoked, and what each action needs to be told.
  ///
  /// The same list the GUI draws buttons from and an agent reads — there is no
  /// second source for it.
  Future<int> _actions({required bool json}) async {
    var session = await openSession();
    try {
      if (json) {
        _printJson({
          'plugins': [
            for (var report in session.reports)
              {
                'id': report.id,
                'actions': [for (var a in report.actions) a.toJson()],
              },
          ],
        });
        return 0;
      }
      for (var report in session.reports) {
        out.writeln(report.id);
        if (report.actions.isEmpty) {
          out.writeln('  (no actions)');
        }
        for (var action in report.actions) {
          var flags = [
            for (var p in action.parameters)
              p.required ? '--${p.id}=<${p.kind.name}>' : '[--${p.id}=…]',
          ].join(' ');
          out.writeln(
            '  ${action.id}${flags.isEmpty ? '' : ' $flags'}'
            '${action.description == null ? '' : '   ${action.description}'}',
          );
        }
        out.writeln();
      }
      return 0;
    } finally {
      session.dispose();
    }
  }

  /// `fw run <plugin> <action> [--param=value]`
  ///
  /// Arguments are keyed by `ActionParameter.id`, which is the same map the GUI
  /// builds from a form and an agent passes directly.
  Future<int> _run(List<String> arguments, {required bool json}) async {
    var wantsHelp = arguments.contains('--help') || arguments.contains('-h');
    var positional = arguments.where((a) => !a.startsWith('--')).toList();
    // Nothing named and nothing to describe: this is someone asking how.
    if (positional.isEmpty) return _help('run');

    var session = await openSession();
    try {
      PluginCore core;
      try {
        core = session.requireCore(positional.first);
      } on SessionException catch (e) {
        // Naming a plugin that does not exist is a usage error, not a failed
        // run — nothing ran, so it exits like a bad command line.
        return fail('$e');
      }

      // `fw run <plugin>` is a question, not a mistake. Answering it with the
      // plugin's own actions beats repeating a usage line already read.
      if (positional.length < 2) return _describePlugin(core);

      var declared = core.report.actions
          .where((action) => action.id == positional[1])
          .firstOrNull;
      if (wantsHelp) {
        if (declared == null) {
          return fail(
            'no action "${positional[1]}" on ${core.id}. '
            'Try `fw run ${_short(core)}`.',
          );
        }
        return _describeAction(core, declared);
      }

      Job job;
      try {
        job = session.invoke(
          positional[0],
          positional[1],
          arguments: parseArguments(arguments),
        );
      } on SessionException catch (e) {
        return fail('$e');
      }

      var result = await job.done;
      if (!result.ok) return _failed(result);

      // An artifact prints as its path, so `fw run … | xargs open` works and a
      // shell script does not have to parse anything. Everything else it knows
      // — the address, the resolved axes — is a `--json` away rather than noise
      // on a line something is piping.
      if (result.artifacts.isNotEmpty) {
        var artifact = result.artifacts.first;
        if (json) {
          _printJson(artifact.toJson());
        } else {
          out.writeln(artifact.path ?? artifact.text);
        }
        return 0;
      }

      // Structured data prints as JSON whether or not `--json` was asked for.
      // A query returns whatever shape the plugin chose, and the framework
      // cannot invent a table for it; JSON is the one rendering that is always
      // honest and always pipes into `jq`. A plugin that wants prose has
      // `PluginView` for that.
      //
      // Switched on the type, not on `is Map || is List`: that test asked
      // "did somebody build a map" and went false the moment a core returned
      // something typed, quietly degrading the output to `toString()`.
      var value = result.value;
      if (value is PluginResult) {
        _printJson(value.toJson());
      } else if (value is Map || value is List) {
        // An action that has not adopted a result type yet. Still data, still
        // prints as data.
        _printJson(value);
      } else if (value != null) {
        out.writeln(json ? jsonEncode(value) : value);
      }
      return 0;
    } finally {
      session.dispose();
    }
  }

  /// Flags to the argument map an action is invoked with.
  ///
  /// A bare `--flag` is `true`; anything else is a string the plugin parses
  /// according to its declared `ActionParameterKind`. A shell has no types to
  /// pass, so this is where the CLI stops and the plugin's own contract starts.
  static Map<String, Object?> parseArguments(List<String> arguments) {
    var parsed = <String, Object?>{};
    for (var argument in arguments.where((a) => a.startsWith('--'))) {
      var body = argument.substring(2);
      var equals = body.indexOf('=');
      parsed[equals < 0 ? body : body.substring(0, equals)] = equals < 0
          ? true
          : body.substring(equals + 1);
    }
    return parsed;
  }

  /// Reports a job that ran and came back with an error.
  ///
  /// A bad argument is the user's mistake and gets the usage exit code and no
  /// stack; anything else is ours, and dropping the stack there would make a
  /// plugin bug unreportable from the one surface that has a terminal to print
  /// it in.
  int _failed(JobResult result) {
    var error = result.error;
    if (error is ArgumentError) return fail(describeJobError(error));
    err.writeln('fw: ${describeJobError(error!)}');
    if (result.stackTrace case var stackTrace?) err.writeln(stackTrace);
    return 1;
  }

  /// The whole surface, or one command of it.
  ///
  /// Rendered from [fwCommands] rather than typed out, because the capability
  /// document renders the same list — and two copies of a command summary is
  /// how a document ends up describing a flag that no longer exists.
  int _help([String? command]) {
    if (command != null) {
      var found = fwCommands.where((c) => c.name == command).firstOrNull;
      if (found == null) return fail('no command "$command". Try `fw help`.');
      out.writeln('fw ${found.usage}');
      out.writeln();
      out.writeln('  ${found.summary}');
      if (found.details case var details?) {
        out.writeln();
        out.writeln(details);
      }
      return 0;
    }

    out.writeln('fw — the CLI renderer of the flutterware plugin contract.');
    out.writeln();
    var width = fwCommands
        .map((c) => c.usage.length)
        .reduce((a, b) => a > b ? a : b);
    for (var entry in fwCommands) {
      out.writeln('  fw ${entry.usage.padRight(width)}  ${entry.summary}');
    }
    out.writeln();
    out.writeln(fwHelpFooter);
    return 0;
  }

  /// What one plugin can do — the answer to `fw run <plugin>`.
  int _describePlugin(PluginCore core) {
    var report = core.report;
    out.writeln('${report.label} — ${report.id}');
    out.writeln();
    if (report.actions.isEmpty) {
      out.writeln('  This plugin declares no actions.');
      return 0;
    }
    for (var action in report.actions) {
      out.writeln('  ${usageLine(_short(core), action)}');
      if (action.description case var description?) {
        out.writeln('      $description');
      }
    }
    out.writeln();
    out.writeln(
      'Run `fw run ${_short(core)} <action> --help` for what one takes and '
      'what it returns.',
    );
    return 0;
  }

  /// One action: what it takes, and what comes back.
  ///
  /// Every line is read from the declaration — the same parameters an agent
  /// gets over MCP, and the result shape extracted from the class the action
  /// returns. Nothing here is written a second time.
  int _describeAction(PluginCore core, PluginAction action) {
    out.writeln(usageLine(_short(core), action));
    out.writeln();
    if (action.description case var description?) {
      out.writeln('  $description');
      out.writeln();
    }

    if (action.parameters.isNotEmpty) {
      out.writeln('Parameters:');
      for (var parameter in action.parameters) {
        var flag = '--${parameter.id}=<${parameter.kind.name}>';
        var fallback = parameter.defaultValue;
        out.writeln(
          '  ${flag.padRight(28)}'
          '${parameter.required ? 'required' : 'optional'}'
          '${fallback == null ? '' : ', default $fallback'}',
        );
        var pad = ' ' * 30;
        if (parameter.description case var description?) {
          out.writeln('$pad$description');
        }
        if (parameter.optionsFrom case var from?) {
          out.writeln('${pad}values: `fw run ${_short(core)} $from`');
        } else if (parameter.options.isNotEmpty) {
          out.writeln(
            '${pad}values: '
            '${parameter.options.map((o) => o.value).take(6).join(', ')}'
            '${parameter.options.length > 6 ? ', …' : ''}',
          );
        }
      }
      out.writeln();
    }

    if (action.returnsName case var returns?) {
      if (resultShapes[returns] case var shape?) {
        out.writeln('Returns $returns:');
        out.write(shape.toText(indent: '  '));
      } else {
        out.writeln('Returns $returns.');
      }
    }
    return 0;
  }

  static String _short(PluginCore core) => core.id.split('.').last;

  /// How an action is spelled on a command line.
  ///
  /// Shared with the capability document, so the two cannot disagree about
  /// which parameters are optional.
  static String usageLine(String plugin, PluginAction action) =>
      'fw run $plugin ${action.id}'
      '${[for (var parameter in action.parameters) parameter.required ? ' --${parameter.id}=<${parameter.kind.name}>' : ' [--${parameter.id}=…]'].join()}';

  void _printJson(Object? value) =>
      out.writeln(const JsonEncoder.withIndent('  ').convert(value));

  int fail(String message) {
    err.writeln('fw: $message');
    return usageExit;
  }

  /// `EX_USAGE`. What a bad command line exits with, as opposed to an action
  /// that ran and failed.
  static const usageExit = 64;
}
