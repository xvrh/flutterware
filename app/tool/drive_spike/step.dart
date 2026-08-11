// Throwaway one-shot driver: one run-plugin action per invocation, for
// driving the GUI from a shell loop when the MCP server is not connected.
// A fresh process per hop is the CLI's own shape — the run's state lives in
// the run dir, not in this process.
//
//   cd app && dart run tool/drive_spike/step.dart <action> ['<json args>']
import 'dart:convert';
import 'dart:io';

import 'package:flutterware/plugins.dart';
// ignore: implementation_imports
import 'package:flutterware/src/log_client.dart';
import 'package:flutterware_app/src/session/job.dart';
import 'package:flutterware_app/src/session/session.dart';
import 'package:path/path.dart' as p;

Future<void> main(List<String> args) async {
  var action = args[0];
  var arguments = args.length > 1
      ? (jsonDecode(args[1]) as Map).cast<String, Object?>()
      : <String, Object?>{};
  var repoRoot = p.dirname(Directory.current.absolute.path);
  var session = await Session.open(
    Directory(repoRoot),
    logger: LogClient.writeTo(stderr),
  );
  try {
    Object? reply;
    try {
      var job = session.invoke('run', action, arguments: arguments);
      var result = await job.done;
      reply = !result.ok
          ? {'error': describeJobError(result.error!)}
          : switch (result.value) {
              PluginResult value => value.toJson(),
              var other => {'value': '$other'},
            };
    } on SessionException catch (e) {
      reply = {'error': '$e'};
    }
    stdout.writeln(jsonEncode(reply));
  } finally {
    session.dispose();
  }
}
