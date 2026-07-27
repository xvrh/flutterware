import 'dart:convert';
import 'dart:io';

import 'package:flutterware/plugins.dart';
import 'package:flutterware_app/src/session/session.dart';

/// The CLI renderer of the plugin contract.
///
/// **Pure Dart, and guarded** — `test/utils/entry_point_purity_test.dart`
/// fails if this file's import closure ever reaches `package:flutter`. That is
/// not style: a plugin's panel returns a `Widget`, so reaching one from here
/// would make this unlinkable, and the compile error would arrive far from the
/// import that caused it.
///
/// Run it with:
///
///     cd app && dart run bin/fw.dart status
///
/// `dart compile exe` does **not** work from this package — `flutterware_app`
/// depends on Flutter plugins with native build hooks (`objective_c`, via
/// `path_provider`), and build hooks are a property of the dependency
/// resolution rather than the import closure. Installing `fw` as a binary is a
/// separate problem, deliberately not solved here.
Future<int> main(List<String> arguments) async {
  var command = arguments.isEmpty ? 'help' : arguments.first;
  var rest = arguments.skip(1).toList();
  var json = rest.remove('--json');

  try {
    return switch (command) {
      'status' => await _status(json: json, compute: rest.remove('--compute')),
      'actions' => await _actions(json: json),
      'run' => await _run(rest, json: json),
      'help' || '--help' || '-h' => _help(),
      _ => _fail('unknown command "$command"'),
    };
  } on SessionException catch (e) {
    stderr.writeln('fw: $e');
    return 1;
  }
}

/// Everything every plugin says about itself, right now.
///
/// Cold, this honestly prints "not computed" for anything nobody has looked at
/// — reading a report never starts work. `--compute` is the explicit opt-in,
/// and it is explicit precisely because a CLI invocation must not silently
/// compile or scan thirty packages.
Future<int> _status({required bool json, required bool compute}) async {
  var session = await Session.open(Directory.current);
  try {
    if (compute) {
      for (var core in session.cores) {
        await core.computeAll();
      }
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
      stdout.writeln('No plugins declared in tool/flutterware.dart.');
      return 0;
    }
    for (var report in session.reports) {
      stdout.writeln(report.toText());
      stdout.writeln();
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
  var session = await Session.open(Directory.current);
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
      stdout.writeln(report.id);
      if (report.actions.isEmpty) {
        stdout.writeln('  (no actions)');
      }
      for (var action in report.actions) {
        var flags = [
          for (var p in action.parameters)
            p.required ? '--${p.id}=<${p.kind.name}>' : '[--${p.id}=…]',
        ].join(' ');
        stdout.writeln(
          '  ${action.id}${flags.isEmpty ? '' : ' $flags'}'
          '${action.description == null ? '' : '   ${action.description}'}',
        );
      }
      stdout.writeln();
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
  var positional = arguments.where((a) => !a.startsWith('--')).toList();
  if (positional.length < 2) {
    return _fail('usage: fw run <plugin> <action> [--param=value]');
  }

  var session = await Session.open(Directory.current);
  try {
    var core = session.coreByShortName(positional[0]);
    if (core == null) {
      return _fail(
        'no plugin "${positional[0]}". Declared: '
        '${session.cores.map((c) => c.id).join(', ')}',
      );
    }

    var parsed = <String, Object?>{};
    for (var argument in arguments.where((a) => a.startsWith('--'))) {
      var body = argument.substring(2);
      var eq = body.indexOf('=');
      // A bare `--flag` is `true`; anything else is a string the plugin parses
      // according to its declared ActionParameterKind.
      parsed[eq < 0 ? body : body.substring(0, eq)] = eq < 0
          ? true
          : body.substring(eq + 1);
    }

    var result = await core.invoke(positional[1], arguments: parsed);

    // An artifact prints as its path, so `fw run … | xargs open` works and a
    // shell script does not have to parse anything. Everything else it knows —
    // the address, the resolved axes — is a `--json` away rather than noise on
    // a line something is piping.
    if (result is Artifact) {
      if (json) {
        _printJson(result.toJson());
      } else {
        stdout.writeln(result.path ?? result.text);
      }
      return 0;
    }

    if (result != null) stdout.writeln(json ? jsonEncode(result) : result);
    return 0;
  } on ArgumentError catch (e) {
    return _fail('${e.message} (${e.name})');
  } finally {
    session.dispose();
  }
}

int _help() {
  stdout.writeln('''
fw — the CLI renderer of the flutterware plugin contract.

  fw status [--compute] [--json]   what every plugin says about itself
  fw actions [--json]              what can be invoked, and with what
  fw run <plugin> <action> [--k=v] invoke one action

Reports never start work: cold, `status` says "not computed" for anything
nobody has looked at. `--compute` asks for it explicitly.''');
  return 0;
}

void _printJson(Object? value) =>
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(value));

int _fail(String message) {
  stderr.writeln('fw: $message');
  return 64; // EX_USAGE
}
