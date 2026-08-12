// The acceptance walk for the native layer: the case that dead-ends an agent
// without it.
//
// A system window opens over the app — the shape every permission prompt,
// share sheet and sign-in sheet has. The drive layer goes blind: the widget
// tree still describes the app underneath, so its observation is confidently
// wrong about what is on screen and its taps land on a window nobody can see.
// The native layer reads the intruder, dismisses it, and hands control back.
//
//   cd app && ../fw dart run tool/native_spike/dialog_check.dart <device>
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
  Job job;
  try {
    job = session.invoke('run', 'act', arguments: {'device': device, ...args});
  } on SessionException catch (e) {
    print('$label: refused: $e');
    return {};
  }
  var result = await job.done;
  if (!result.ok) {
    print('$label: FAILED ${describeJobError(result.error!)}');
    return {};
  }
  var reply = (result.value! as PluginResult).toJson();
  print('$label: ok=${reply['ok']}');
  if (reply['error'] case String error) {
    print('   ! ${error.split('\n').first}');
  }
  return reply;
}

List<String> textsOf(Map<String, Object?> reply) =>
    (reply['texts'] as List?)?.cast<String>() ?? const [];

Future<void> main(List<String> args) async {
  device = args.isNotEmpty ? args[0] : 'emulator-5554';
  var adb = p.join(
    Platform.environment['HOME']!,
    'Library/Android/sdk/platform-tools/adb',
  );
  session = await Session.open(
    Directory(p.dirname(Directory.current.absolute.path)),
    logger: LogClient.writeTo(stderr),
  );
  try {
    var before = await act('1 drive: the app', {'verb': 'observe'});
    print('   sees: ${textsOf(before).take(3).toList()}');

    print('\n-- a system window opens over the app --');
    await Process.run(adb, [
      '-s',
      device,
      'shell',
      'am',
      'start',
      '-a',
      'android.settings.APPLICATION_DETAILS_SETTINGS',
      '-d',
      'package:com.example.flutterware_example',
    ]);
    await Future<void>.delayed(const Duration(seconds: 3));

    var blind = await act('2 drive: still sees the app', {'verb': 'observe'});
    print('   sees: ${textsOf(blind).take(3).toList()}');
    print('   ^ the widget tree is intact and describes a hidden window');

    var native = await act('3 native: sees the intruder', {
      'verb': 'observe',
      'layer': 'native',
    });
    print('   sees: ${textsOf(native).take(6).toList()}');

    await act('4 native: dismiss it', {
      'verb': 'tap',
      'layer': 'native',
      'target': '{"containing": "Navigate up"}',
    });
    await Future<void>.delayed(const Duration(seconds: 2));

    var back = await act('5 native: back on the app', {
      'verb': 'observe',
      'layer': 'native',
    });
    print('   sees: ${textsOf(back).take(3).toList()}');

    var resumed = await act('6 drive: driving again', {'verb': 'observe'});
    print('   reconciled echoes: ${resumed['reconciled'] ?? 0}');
  } finally {
    session.dispose();
    exit(0);
  }
}
