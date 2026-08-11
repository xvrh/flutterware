// Throwaway dogfood driver for the run-drive design, step 6
// (docs/superpowers/specs/2026-08-11-run-drive-design.md).
//
// The full stack, exactly as an agent uses it: open a real Session on this
// repo, launch the flutterware GUI itself (Studio dev on macos) through
// run.launch — which wraps it in the run guest — then drive the GUI with
// run.act to its own Run panel and Steps tab, so the final screenshot is the
// GUI showing the journal of the very steps that produced it. The app is
// left running for a human to take over.
//
//   cd app && dart run tool/drive_spike/dogfood.dart <outDir>
import 'dart:convert';
import 'dart:io';

import 'package:flutterware/plugins.dart';
// ignore: implementation_imports
import 'package:flutterware/src/log_client.dart';
import 'package:flutterware_app/src/session/job.dart';
import 'package:flutterware_app/src/session/session.dart';
import 'package:path/path.dart' as p;

late Session session;
late Directory outDir;

Future<Map<String, Object?>> run(
  String action,
  Map<String, Object?> args,
) async {
  stderr.writeln('>> run.$action $args');
  Job job;
  try {
    job = session.invoke('run', action, arguments: args);
  } on SessionException catch (e) {
    stderr.writeln('!! $e');
    return {'error': '$e'};
  }
  var result = await job.done;
  if (!result.ok) {
    var error = describeJobError(result.error!);
    stderr.writeln('!! $error');
    return {'error': error};
  }
  return switch (result.value) {
    PluginResult value => value.toJson(),
    var other => {'value': '$other'},
  };
}

Future<Map<String, Object?>> act(Map<String, Object?> args) async {
  var reply = await run('act', {'maxSide': 1400, ...args});
  stderr.writeln(
    '   ok=${reply['ok']} error=${reply['error']} '
    'settled=${reply['settled']} attempts=${reply['attempts']} '
    'texts=${(reply['texts'] as List?)?.length}',
  );
  return reply;
}

/// Taps [target]; on an ambiguity refusal, retries as the first match — the
/// move an agent makes after reading the refusal.
Future<Map<String, Object?>> tap(String target) async {
  var reply = await act({'verb': 'tap', 'target': target});
  if (reply['failure'] == 'multiple') {
    reply = await act({
      'verb': 'tap',
      'target': jsonEncode({
        'nth': {'target': target, 'index': 0},
      }),
    });
  }
  return reply;
}

void keep(Map<String, Object?> reply, String name) {
  if (reply['screenshot'] case String path) {
    File(path).copySync(p.join(outDir.path, name));
    stderr.writeln('   saved $name');
  }
}

Future<void> main(List<String> args) async {
  outDir = Directory(args.isNotEmpty ? args[0] : '/tmp/fw-dogfood')
    ..createSync(recursive: true);
  var repoRoot = p.dirname(Directory.current.absolute.path);
  session = await Session.open(
    Directory(repoRoot),
    logger: LogClient.writeTo(stderr),
  );
  var report = <String, Object?>{};
  try {
    var launch = await run('launch', {
      'device': 'macos',
      'package': 'app',
      'entrypoint': 'lib/main_dev.dart',
      'wait': true,
      'timeout': 300,
    });
    report['launch'] = launch;
    if (launch['error'] != null) return;

    var first = await act({'verb': 'observe'});
    keep(first, '1-observe.png');
    report['observe'] = {
      'ok': first['ok'],
      'texts': (first['texts'] as List?)?.take(30).toList(),
    };

    var panel = await tap('Run');
    keep(panel, '2-run-panel.png');
    report['tapRun'] = {'ok': panel['ok'], 'error': panel['error']};

    // The panel lists this very run — open it by whatever it is called.
    var texts = (panel['texts'] as List?)?.cast<String>() ?? const [];
    var row = texts.firstWhere(
      (t) => t.contains('Studio'),
      orElse: () =>
          texts.firstWhere((t) => t.contains('main_dev'), orElse: () => ''),
    );
    if (row.isNotEmpty) {
      var open = await tap(row);
      keep(open, '3-run-open.png');
      report['openRun'] = {
        'row': row,
        'ok': open['ok'],
        'error': open['error'],
      };
    } else {
      report['openRun'] = {'error': 'no run row text found', 'texts': texts};
    }

    var steps = await tap('Steps');
    keep(steps, '4-steps-tab.png');
    report['tapSteps'] = {'ok': steps['ok'], 'error': steps['error']};

    report['reload'] = await run('reload', {});
    var after = await act({'verb': 'observe'});
    keep(after, '5-steps-after-reload.png');

    if (after['journal'] case String journalPath) {
      report['journal'] = journalPath;
      File(
        p.join(outDir.path, 'journal.jsonl'),
      ).writeAsStringSync(File(journalPath).readAsStringSync());
    }
  } finally {
    File(
      p.join(outDir.path, 'report.json'),
    ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(report));
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(report));
    session.dispose();
  }
}
