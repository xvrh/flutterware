import 'dart:convert';

import 'package:flutterware_app/src/run/logs.dart';
import 'package:flutterware_app/src/run/native/native_logs.dart';
import 'package:test/test.dart';

/// One `log show --style ndjson` record, with the fields this reads.
String record({
  required String message,
  required String sender,
  String process = '$_bundle/Runner',
  String type = 'Default',
}) => jsonEncode({
  'eventType': 'logEvent',
  'eventMessage': message,
  'messageType': type,
  'processImagePath': process,
  'senderImagePath': sender,
  'timestamp': '2026-08-17 14:20:38.069618+0200',
});

/// A real simulator's bundle path, which is a container UUID rather than
/// anything derivable from the project — the reason the bundle is discovered
/// rather than guessed.
const _bundle =
    '/Users/dev/Library/Developer/CoreSimulator/Devices/'
    '575104B7-6AB9-42BA-82B6-351FC0DA2921/data/Containers/Bundle/'
    'Application/8580A27E-75DA-4658-87FF-8F4912A180C7/Runner.app';

void main() {
  group('the Apple log store', () {
    test('names the framework that spoke, and lets the app speak plainly', () {
      // The shape the whole feature exists for: a plugin's own framework, next
      // to the engine, next to the app's main executable.
      var output = [
        record(
          message: 'Device Registered with Apple: 80c01106',
          sender: '$_bundle/Frameworks/PushKit.framework/PushKit',
        ),
        record(
          message: 'Using the Impeller rendering backend (Metal).',
          sender: '$_bundle/Frameworks/Flutter.framework/Flutter',
        ),
        record(
          message: 'something the app itself said',
          sender: '$_bundle/Runner',
        ),
      ].join('\n');

      expect(
        AppleLogSource.parseAppleLog(
          output,
          bundle: _bundle,
        ).map((l) => l.text),
        [
          '(PushKit) Device Registered with Apple: 80c01106',
          '(Flutter) Using the Impeller rendering backend (Metal).',
          'something the app itself said',
        ],
      );
    });

    test('every line is native, whoever sent it', () {
      var output = record(message: 'hi', sender: '$_bundle/Runner');
      expect(
        AppleLogSource.parseAppleLog(output).single.source,
        RunLogSource.native,
      );
    });

    test("errors are Apple's word for it, not ours", () {
      var output = [
        record(message: 'no error here', sender: '$_bundle/Runner'),
        record(message: 'it broke', sender: '$_bundle/Runner', type: 'Error'),
        record(
          message: 'it broke badly',
          sender: '$_bundle/Runner',
          type: 'Fault',
        ),
        record(
          message: 'just talking',
          sender: '$_bundle/Runner',
          type: 'Info',
        ),
      ].join('\n');

      expect(AppleLogSource.parseAppleLog(output).map((l) => l.error), [
        false,
        true,
        true,
        false,
      ]);
    });

    test('the header and a half-written record are skipped, not fatal', () {
      // `log show` prints a header line, and a read taken while the store is
      // being written can end mid-record.
      var output = [
        'Filtering the log data using "eventType == 1"',
        'Timestamp               Ty Process[PID:TID]',
        record(message: 'kept', sender: '$_bundle/Runner'),
        '{"eventMessage":"truncat',
      ].join('\n');

      expect(
        AppleLogSource.parseAppleLog(
          output,
          bundle: _bundle,
        ).map((l) => l.text),
        ['kept'],
      );
    });

    test('the predicate pins the process and excludes the OS as sender', () {
      // The difference between 1889 lines and 141. The sender is excluded by
      // what it is not, because a sender path may name a container the process
      // is not running from — see the constant below.
      var predicate = AppleLogSource.bundlePredicate('/apps/Runner.app');

      expect(
        predicate,
        contains('processImagePath BEGINSWITH "/apps/Runner.app/"'),
      );
      expect(predicate, contains('NOT(senderImagePath BEGINSWITH "/System/")'));
      expect(
        predicate,
        contains('NOT(senderImagePath BEGINSWITH "/usr/lib/")'),
      );
      // A Swift crash reports itself from an OS image and is still the app's.
      expect(predicate, contains('libswiftCore.dylib'));
      // Never the bundle: the clause that named it matched nothing at all.
      expect(
        predicate,
        isNot(contains('senderImagePath BEGINSWITH "/apps/Runner.app/"')),
      );
    });

    test('a framework naming a stale container is still the app talking', () {
      // Verbatim shape from a real simulator: the process runs from one
      // install container and its frameworks report the previous one, because
      // the log store resolves an image path by Mach-O UUID and answers with
      // whichever path it indexed first. A reader that matched senders against
      // the process's own bundle would have dropped every one of these.
      const stale =
          '/Users/dev/Library/Developer/CoreSimulator/Devices/575104B7/data/'
          'Containers/Bundle/Application/8580A27E-OLD/Runner.app/Frameworks/'
          'PushKit.framework/PushKit';
      var output = record(message: 'Device Registered', sender: stale);

      expect(
        AppleLogSource.parseAppleLog(output, bundle: _bundle).single.text,
        '(PushKit) Device Registered',
      );
    });

    test('the window is a local wall clock to the second', () {
      expect(
        AppleLogSource.startArgument(DateTime(2026, 8, 17, 9, 4, 5)),
        '2026-08-17 09:04:05',
      );
    });
  });

  group('logcat', () {
    test('keeps the tag and drops the frame around it', () {
      var output = [
        '--------- beginning of main',
        '08-17 14:20:38.069 I/flutter ( 4271): a Dart print',
        '08-17 14:20:38.104 D/PushSdk( 4271): setAppId called',
        '08-17 14:20:39.900 E/AndroidRuntime( 4271): FATAL EXCEPTION: main',
      ].join('\n');

      var lines = AndroidLogSource.parseLogcat(output);
      expect(lines.map((l) => l.text), [
        '(flutter) a Dart print',
        '(PushSdk) setAppId called',
        '(AndroidRuntime) FATAL EXCEPTION: main',
      ]);
      expect(lines.map((l) => l.error), [false, false, true]);
      expect(lines.every((l) => l.source == RunLogSource.native), isTrue);
    });

    test('a line in no known format still carries its words', () {
      var lines = AndroidLogSource.parseLogcat('a continuation line');
      expect(lines.single.text, 'a continuation line');
    });

    test('the pid comes off the newest engine line', () {
      // A device that has run this app twice holds both pids; the live one is
      // the later.
      var output = [
        'I/flutter ( 4271): from the run before',
        'I/flutter ( 8123): from this one',
      ].join('\n');

      expect(AndroidLogSource.newestPid(output), 8123);
    });

    test('no engine line is no pid, rather than a wrong one', () {
      expect(AndroidLogSource.newestPid('--------- beginning of main'), isNull);
    });
  });
}
