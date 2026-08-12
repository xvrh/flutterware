// The iOS dead end, and the way out of it.
//
// Backgrounds the app under test (by launching Safari over it), confirms the
// drive layer reports the documented timeout, then asks the native layer to
// bring it back and drives it again — the recovery an agent could not perform
// before this layer existed.
//
//   cd app && ../fw dart run tool/native_spike/foreground_check.dart <udid>
import 'dart:io';

import 'package:flutterware/plugins.dart';
// ignore: implementation_imports
import 'package:flutterware/src/log_client.dart';
import 'package:flutterware_app/src/session/job.dart';
import 'package:flutterware_app/src/session/session.dart';
import 'package:path/path.dart' as p;

late Session session;
late String device;

Future<Map<String, Object?>> act(
  String label,
  Map<String, Object?> args,
) async {
  var started = DateTime.now();
  Job job;
  try {
    job = session.invoke('run', 'act', arguments: {'device': device, ...args});
  } on SessionException catch (e) {
    print('$label: session refused: $e');
    return {'error': '$e'};
  }
  var result = await job.done;
  var ms = DateTime.now().difference(started).inMilliseconds;
  if (!result.ok) {
    print('$label: FAILED after ${ms}ms — ${describeJobError(result.error!)}');
    return {'error': 'job failed'};
  }
  var reply = (result.value as PluginResult?)?.toJson() ?? const {};
  var texts = (reply['texts'] as List?)?.length;
  print(
    '$label: ok=${reply['ok']} ${ms}ms ${texts == null ? '' : 'texts=$texts'}',
  );
  if (reply['error'] case String error) {
    print('   ! ${error.split('\n').first}');
  }
  return reply;
}

Future<void> main(List<String> args) async {
  device = args.isNotEmpty ? args[0] : '';
  session = await Session.open(
    Directory(p.dirname(Directory.current.absolute.path)),
    logger: LogClient.writeTo(stderr),
  );
  try {
    var before = await act('1 drive, foreground', {'verb': 'observe'});
    var counter = (before['texts'] as List?)?.cast<String>().firstWhere(
      (text) => int.tryParse(text) != null,
      orElse: () => '?',
    );
    print('   counter reads $counter');

    print('\n-- backgrounding the app --');
    await Process.run('xcrun', [
      'simctl',
      'launch',
      device,
      'com.apple.mobilesafari',
    ]);
    await Future<void>.delayed(const Duration(seconds: 3));

    await act('2 drive, suspended', {'verb': 'observe', 'settleMs': 300});

    print('\n-- native foreground --');
    await act('3 native foreground', {'verb': 'foreground', 'layer': 'native'});

    var after = await act('4 drive, resumed', {'verb': 'observe'});
    var resumed = (after['texts'] as List?)?.cast<String>().firstWhere(
      (text) => int.tryParse(text) != null,
      orElse: () => '?',
    );
    print('   counter reads $resumed (was $counter — state survived if equal)');
  } finally {
    session.dispose();
    exit(0);
  }
}
