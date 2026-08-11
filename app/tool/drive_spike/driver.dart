// Throwaway driver for the run-drive spike
// (docs/superpowers/specs/2026-08-11-run-drive-design.md).
//
// Launches examples/example/tool/drive_spike.dart with `flutter run -d macos
// --machine`, connects to the VM service, and runs the four spike suites
// against `ext.spike.call`. Prints a JSON report and writes artifacts next to
// the report path given as the first argument (default: /tmp/drive_spike).
//
//   cd app && dart run tool/drive_spike/driver.dart <outDir>
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutterware_app/src/run/drive_session.dart';
import 'package:flutterware_app/src/run/handle.dart';
import 'package:path/path.dart' as p;
import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

late VmService service;
late String isolateId;
final report = <String, Object?>{};

Future<void> main(List<String> args) async {
  var outDir = Directory(args.isNotEmpty ? args[0] : '/tmp/drive_spike')
    ..createSync(recursive: true);
  var repoRoot = p.dirname(Directory.current.path);
  var flutter = p.join(repoRoot, '.fvm', 'flutter_sdk', 'bin', 'flutter');
  var exampleDir = p.join(repoRoot, 'examples', 'example');

  var launchWatch = Stopwatch()..start();
  var process = await Process.start(flutter, [
    'run',
    '-d',
    'macos',
    '-t',
    'tool/drive_spike.dart',
    '--machine',
  ], workingDirectory: exampleDir);
  unawaited(process.stderr.transform(utf8.decoder).forEach(stderr.write));

  String? wsUri;
  String? appId;
  var started = Completer<void>();
  var lines = process.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter());
  var sub = lines.listen((line) {
    if (!line.startsWith('[{')) {
      stderr.writeln('| $line');
      return;
    }
    Object? decoded;
    try {
      decoded = jsonDecode(line);
    } catch (_) {
      return;
    }
    if (decoded is! List) return;
    for (var entry in decoded.cast<Map<String, dynamic>>()) {
      var params = entry['params'];
      switch (entry['event']) {
        case 'app.debugPort':
          wsUri = (params as Map)['wsUri'] as String;
        case 'app.start':
          appId = (params as Map)['appId'] as String;
        case 'app.started':
          if (!started.isCompleted) started.complete();
        case 'app.stop':
          if (!started.isCompleted) {
            started.completeError(StateError('app stopped before start'));
          }
        case 'app.log':
          stderr.writeln('| ${(params as Map)['log']}');
      }
    }
  });

  try {
    await started.future.timeout(const Duration(minutes: 10));
    report['launchMs'] = launchWatch.elapsedMilliseconds;
    stderr.writeln('>> app started in ${launchWatch.elapsed}, ws=$wsUri');

    service = await vmServiceConnectUri(wsUri!);
    var vm = await service.getVM();
    isolateId = vm.isolates!.first.id!;

    await _retryPing();
    await _suiteBasics(outDir);
    await _suiteSettle('settleEarly', outDir);
    await _suiteAnimation();
    await _suiteEnterText();
    await _suiteSettle('settleLate', outDir);
    await _suiteEngine();
    await _suiteGuestWire(outDir);
    await _suiteSession(wsUri!);

    File(
      p.join(outDir.path, 'report.json'),
    ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(report));
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(report));
  } finally {
    try {
      if (appId != null) {
        process.stdin.writeln(
          jsonEncode([
            {
              'id': 99,
              'method': 'app.stop',
              'params': {'appId': appId},
            },
          ]),
        );
        await process.exitCode.timeout(const Duration(seconds: 15));
      }
    } catch (_) {
      process.kill();
    }
    await sub.cancel();
  }
}

Future<Map<String, dynamic>> call(Map<String, String> args) async {
  var response = await service.callServiceExtension(
    'ext.spike.call',
    isolateId: isolateId,
    args: args,
  );
  var json = response.json!;
  if (json['error'] != null) {
    stderr.writeln('!! ${args['cmd']} -> ${json['error']}');
  }
  return json;
}

Future<void> _retryPing() async {
  var sw = Stopwatch()..start();
  while (true) {
    try {
      var pong = await call({'cmd': 'ping'});
      if (pong['ok'] == true) {
        report['pingMs'] = sw.elapsedMilliseconds;
        return;
      }
    } catch (_) {}
    if (sw.elapsed > const Duration(seconds: 30)) {
      throw StateError('extension never responded');
    }
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
}

/// Q1 evidence + plain tap + scrollUntilVisible + screenshot.
Future<void> _suiteBasics(Directory outDir) async {
  await call({'cmd': 'reset'});
  var tap = await call({'cmd': 'tap', 'text': 'Increment'});
  var counts = (tap['texts'] as List?)?.cast<String>() ?? [];
  report['basicTap'] = {
    'tapLog': tap['tapLog'],
    'countText': counts.where((t) => t.startsWith('Count:')).toList(),
    'settled': tap['settled'],
    'tapMs': tap['tapMs'],
    'settleMs': tap['elapsedMs'],
  };

  var shot = await call({'cmd': 'screenshot'});
  if (shot['png'] != null) {
    var file = File(p.join(outDir.path, 'home.png'));
    file.writeAsBytesSync(base64Decode(shot['png'] as String));
    report['screenshot'] = {
      'ms': shot['ms'],
      'width': shot['width'],
      'height': shot['height'],
      'path': file.path,
    };
  } else {
    report['screenshot'] = shot;
  }

  await call({'cmd': 'home'});
  await call({'cmd': 'reset'});
  await call({'cmd': 'tap', 'text': 'List'});
  var scroll = await call({'cmd': 'scrollToRow', 'text': 'Row 50'});
  var tapRow = await call({'cmd': 'tap', 'text': 'Row 50'});
  report['scrollUntilVisible'] = {
    'scrollError': scroll['error'],
    'tapLog': tapRow['tapLog'],
  };
  await call({'cmd': 'home'});
}

/// Q2: tap-by-target while everything oscillates and slides.
Future<void> _suiteAnimation() async {
  Future<Map<String, Object?>> stress({
    required bool entrance,
    required bool checkReach,
    required int rounds,
  }) async {
    var ok = 0, wrong = 0, missed = 0, covered = 0, errors = <String>[];
    for (var i = 0; i < rounds; i++) {
      if (entrance || i == 0) {
        await call({'cmd': 'home'});
        await call({'cmd': 'reset'});
        // Tap "Moving" and barely settle: enough frames for the route to
        // build (a hidden window pumps nothing on its own), still deep inside
        // the route transition and the entrance slide.
        await call({
          'cmd': 'tap',
          'text': 'Moving',
          'settleMs': entrance ? '80' : '1000',
        });
        if (entrance) {
          await Future<void>.delayed(const Duration(milliseconds: 150));
        }
      }
      await call({'cmd': 'reset'});
      var result = await call({
        'cmd': 'tap',
        'text': 'Item 7',
        'settleMs': '0',
        if (checkReach) 'checkReach': 'true',
      });
      if (result['covered'] == true) {
        covered++;
        continue;
      }
      if (result['error'] != null) {
        errors.add(result['error'] as String);
        continue;
      }
      var log = (result['tapLog'] as List).cast<String>();
      if (log.isEmpty) {
        missed++;
      } else if (log.length == 1 && log.single == 'item-7') {
        ok++;
      } else {
        wrong++;
        stderr.writeln('!! wrong target: $log');
      }
    }
    return {
      'rounds': rounds,
      'ok': ok,
      'wrong': wrong,
      'missed': missed,
      'covered': covered,
      'errors': errors,
    };
  }

  report['animationSteady'] = await stress(
    entrance: false,
    checkReach: false,
    rounds: 30,
  );
  report['animationSteadyChecked'] = await stress(
    entrance: false,
    checkReach: true,
    rounds: 30,
  );
  report['animationEntrance'] = await stress(
    entrance: true,
    checkReach: false,
    rounds: 10,
  );
  report['animationEntranceChecked'] = await stress(
    entrance: true,
    checkReach: true,
    rounds: 10,
  );

  // The retry ladder: reach-check with retry until the transition-time
  // IgnorePointer lifts, then tap. What a real drive verb would do.
  var retryOk = 0, retryWrong = 0, retryGaveUp = 0;
  var attemptsUsed = <int>[];
  for (var i = 0; i < 10; i++) {
    await call({'cmd': 'home'});
    await call({'cmd': 'reset'});
    await call({'cmd': 'tap', 'text': 'Moving', 'settleMs': '80'});
    await Future<void>.delayed(const Duration(milliseconds: 70));
    var landed = false;
    for (var attempt = 1; attempt <= 25; attempt++) {
      await call({'cmd': 'reset'});
      var result = await call({
        'cmd': 'tap',
        'text': 'Item 7',
        'settleMs': '0',
        'checkReach': 'true',
      });
      if (result['covered'] == true || result['error'] != null) {
        // Between attempts the app must be pumped, not merely waited on: a
        // hidden window advances zero frames during a plain sleep.
        await call({'cmd': 'observe', 'settleMs': '60'});
        continue;
      }
      var log = (result['tapLog'] as List).cast<String>();
      if (log.isEmpty) {
        await call({'cmd': 'observe', 'settleMs': '60'});
        continue;
      }
      landed = true;
      attemptsUsed.add(attempt);
      if (log.length == 1 && log.single == 'item-7') {
        retryOk++;
      } else {
        retryWrong++;
        stderr.writeln('!! retry wrong target: $log');
      }
      break;
    }
    if (!landed) retryGaveUp++;
  }
  report['animationEntranceRetry'] = {
    'rounds': 10,
    'ok': retryOk,
    'wrong': retryWrong,
    'gaveUp': retryGaveUp,
    'attemptsUsed': attemptsUsed,
  };
  await call({'cmd': 'home'});
}

/// Q3: both enterText mechanisms, with focus diagnostics.
Future<void> _suiteEnterText() async {
  await call({'cmd': 'home'});
  await call({'cmd': 'reset'});
  await call({'cmd': 'tap', 'text': 'Text'});
  var tapField = await call({'cmd': 'tap', 'key': 'field'});
  report['tapField'] = {
    'error': tapField['error'],
    'lifecycle': tapField['lifecycle'],
    'primaryFocus': tapField['primaryFocus'],
  };

  var one = await call({'cmd': 'enterText1', 'text': 'hello'});
  if (one['error'] != null) {
    // Tap did not focus the field; try programmatic focus, then retry.
    report['focusField'] = await call({'cmd': 'focusField'});
    one = await call({'cmd': 'enterText1', 'text': 'hello'});
  }
  report['enterText1'] = {
    'error': one['error'],
    'valueText': _valueText(one),
    'textEvents': one['textEvents'],
    'lifecycle': one['lifecycle'],
    'primaryFocus': one['primaryFocus'],
  };

  var two = await call({'cmd': 'enterText2', 'text': 'world'});
  report['enterText2'] = {
    'error': two['error'],
    'valueText': _valueText(two),
    'textEvents': two['textEvents'],
  };
  await call({'cmd': 'home'});
}

String? _valueText(Map<String, dynamic> result) {
  var texts = (result['texts'] as List?)?.cast<String>();
  return texts?.where((t) => t.startsWith('Value:')).join(', ');
}

/// Q4: bounded wall-clock settle.
Future<void> _suiteSettle(String name, Directory outDir) async {
  await call({'cmd': 'home'});
  var idle = await call({'cmd': 'observe', 'settleMs': '1000'});

  await call({'cmd': 'reset'});
  var spinner = await call({
    'cmd': 'tap',
    'text': 'Spinner',
    'settleMs': '1500',
  });
  await _shot(outDir, '$name-spinner.png');
  await call({'cmd': 'home'});

  await call({'cmd': 'reset'});
  var push = await call({'cmd': 'tap', 'text': 'Push', 'settleMs': '3000'});
  await _shot(outDir, '$name-push.png');
  report[name] = {
    'idle': _settleView(idle),
    'spinner': {..._settleView(spinner), 'tapLog': spinner['tapLog']},
    'push': {
      ..._settleView(push),
      'tapLog': push['tapLog'],
      'sawPushedPage': ((push['texts'] as List?) ?? []).contains('Pushed page'),
    },
  };
  await call({'cmd': 'home'});
}

/// The production engine (`package:flutterware/drive.dart`) end to end,
/// driving the same app the hand-rolled mechanism probes drove. The Item 7
/// tap lands mid-entrance on purpose: the verb's own retry ladder must absorb
/// the route transition without driver-side pacing.
Future<void> _suiteEngine() async {
  await call({'cmd': 'home'});
  await call({'cmd': 'reset'});

  var increment = await call({'cmd': 'etap', 'text': 'Increment'});
  await call({'cmd': 'etap', 'text': 'Moving', 'settleMs': '0'});
  var item = await call({'cmd': 'etap', 'text': 'Item 7'});
  var back = await call({'cmd': 'eback'});
  await call({'cmd': 'etap', 'text': 'Text'});
  var enter = await call({'cmd': 'eenter', 'key': 'field', 'value': 'engine!'});
  await call({'cmd': 'eback'});
  await call({'cmd': 'etap', 'text': 'List'});
  var scroll = await call({'cmd': 'escroll', 'text': 'Row 50'});
  var row = await call({'cmd': 'etap', 'text': 'Row 50'});
  await call({'cmd': 'eback'});
  var spinner = await call({
    'cmd': 'etap',
    'text': 'Spinner',
    'settleMs': '1200',
  });
  await call({'cmd': 'eback'});
  var end = await call({'cmd': 'eobserve'});

  Map<String, Object?>? step(Map<String, dynamic> result) =>
      (result['step'] as Map?)?.cast<String, Object?>();
  report['engine'] = {
    'incrementError': increment['error'],
    'item7': {'step': step(item), 'error': item['error']},
    'backSettle': step(back)?['settle'],
    'enterValue': _valueText(enter),
    'enterError': enter['error'],
    'scrollError': scroll['error'],
    'row50Error': row['error'],
    'spinnerSettle': step(spinner)?['settle'],
    'finalLog': end['tapLog'],
    'finalTexts': (end['texts'] as List?)
        ?.cast<String>()
        .where((t) => t.startsWith('Count:'))
        .toList(),
  };
}

/// The real wire: `ext.flutterware.act` served by the run guest
/// (`package:flutterware/run_guest.dart`) — transaction in, bundle out.
Future<void> _suiteGuestWire(Directory outDir) async {
  await call({'cmd': 'home'});
  await call({'cmd': 'reset'});
  Future<Map<String, dynamic>> act(Map<String, String> args) async {
    var response = await service.callServiceExtension(
      'ext.flutterware.act',
      isolateId: isolateId,
      args: args,
    );
    var json = response.json!;
    if (json['error'] != null) {
      stderr.writeln('!! act ${args['verb']} -> ${json['error']}');
    }
    return json;
  }

  var tap = await act({'verb': 'tap', 'target': 'Increment'});
  var shot = tap['screenshot'] as Map?;
  if (shot?['base64'] != null) {
    File(
      p.join(outDir.path, 'guest-tap.png'),
    ).writeAsBytesSync(base64Decode(shot!['base64'] as String));
  }
  var logs = (tap['logs'] as List?) ?? [];

  var refusal = await act({'verb': 'tap', 'target': 'Nope'});
  var navigate = await act({'verb': 'navigate', 'route': 'somewhere'});

  await act({'verb': 'tap', 'target': 'Text'});
  var enter = await act({
    'verb': 'enterText',
    'target': '{"key": "field"}',
    'text': 'wire!',
  });
  var back = await act({'verb': 'back'});

  report['guestWire'] = {
    'tap': {
      'step': tap['step'],
      'lifecycle': tap['lifecycle'],
      'countText': (tap['texts'] as List?)
          ?.cast<String>()
          .where((t) => t.startsWith('Count:'))
          .toList(),
      'treeRoot': ((tap['tree'] as Map?)?['root'] as Map?)?['type'],
      'treePresent': tap['tree'] != null,
      'screenshot': shot == null
          ? null
          : {'width': shot['width'], 'height': shot['height']},
      'logsSince': [for (var line in logs) (line as Map)['text']],
    },
    'refusal': {
      'error': refusal['error'],
      'failure': refusal['failure'],
      'bundleTexts': refusal['texts'] != null,
    },
    'navigate': {'error': navigate['error']},
    'enterValue': _valueText(enter),
    'backSettled': ((back['step'] as Map?)?['settle'] as Map?)?['settled'],
  };
}

/// The host glue: a held [DriveSession] over the same app, two transactions
/// on one connection.
Future<void> _suiteSession(String wsUri) async {
  await call({'cmd': 'home'});
  await call({'cmd': 'reset'});
  var session = DriveSession(
    RunHandle(
      worktree: '/spike',
      worktreeName: 'spike',
      device: 'macos',
      entrypoint: 'tool/drive_spike.dart',
      launcherPid: pid,
      startedAt: DateTime.now(),
      vmService: wsUri,
    ),
  );
  try {
    var first = Stopwatch()..start();
    var observe = await session.act({
      'verb': 'observe',
      'screenshot': 'false',
      'tree': 'false',
    });
    first.stop();
    var second = Stopwatch()..start();
    var tap = await session.act({
      'verb': 'tap',
      'target': 'Increment',
      'screenshot': 'false',
      'tree': 'false',
    });
    second.stop();
    report['session'] = {
      'observeOk': observe['error'] == null,
      'tapOk': tap['error'] == null && (tap['step'] as Map?) != null,
      'firstCallMs': first.elapsedMilliseconds,
      'heldSecondCallMs': second.elapsedMilliseconds,
    };
  } finally {
    await session.close();
  }
}

Map<String, Object?> _settleView(Map<String, dynamic> result) => {
  'error': result['error'],
  'settled': result['settled'],
  'elapsedMs': result['elapsedMs'],
  'frames': result['frames'],
  'forcedFrames': result['forcedFrames'],
  'framesEnabled': result['framesEnabled'],
};

Future<void> _shot(Directory outDir, String name) async {
  var shot = await call({'cmd': 'screenshot'});
  if (shot['png'] != null) {
    File(
      p.join(outDir.path, name),
    ).writeAsBytesSync(base64Decode(shot['png'] as String));
  }
}
