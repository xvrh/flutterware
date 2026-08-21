import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware_app/src/run/connection.dart';
import 'package:flutterware_app/src/run/drive_session.dart';
import 'package:flutterware_app/src/run/handle.dart';
import 'package:vm_service/vm_service.dart';

/// Which isolate the drive transaction is addressed to.
///
/// An app is one isolate right up until it is not. A sync engine, a
/// database worker or a plugin running Dart on a second engine puts another
/// one in `getVM()`, and the guest is in exactly one of them. Measured against
/// a live app: asking the wrong isolate for `ext.flutterware.act` answers
/// `RPCError -32601 Unknown method`, which is the same answer an app with no
/// guest at all gives — so a guess here does not fail loudly, it fails as a
/// sentence telling somebody to relaunch an app that was launched correctly.
void main() {
  group('choosing the isolate', () {
    test('one isolate is the isolate', () {
      expect(
        RunConnection.rootIsolateOf([_ref('isolates/9', 'worker')]),
        'isolates/9',
      );
    });

    test('among several it is the one named main, wherever it sits', () {
      expect(
        RunConnection.rootIsolateOf([
          _ref('isolates/1', 'worker'),
          _ref('isolates/2', 'main'),
        ]),
        'isolates/2',
      );
    });

    test('nothing to choose from is not a choice', () {
      expect(RunConnection.rootIsolateOf([]), isNull);
      expect(RunConnection.rootIsolateOf(null), isNull);
    });
  });

  group('an act against the wrong isolate', () {
    late _FakeVm vm;

    setUp(() => vm = _FakeVm());
    tearDown(() => vm.dispose());

    test('is repaired against the one that has the guest', () async {
      vm.isolates = {'worker': false, 'main': true};
      var connection = await RunConnection.forTesting(vm.service, 'worker');
      var session = DriveSession.forTesting(_handle(), connection);

      var reply = await session.act({'verb': 'observe'});

      expect(reply['texts'], ['Pay']);
      expect(
        connection.isolateId,
        'main',
        reason:
            'the connection keeps the isolate it was repaired onto — the '
            'next act must not guess the same wrong way again',
      );
      expect(vm.actCalls, ['worker', 'main']);
    });

    test('is only a missing guest once the VM has been asked', () async {
      vm.isolates = {'main': false, 'worker': false};
      var session = DriveSession.forTesting(
        _handle(),
        await RunConnection.forTesting(vm.service, 'main'),
      );

      await expectLater(
        session.act({'verb': 'observe'}),
        throwsA(
          isA<DriveNoGuest>().having(
            (e) => '$e',
            'message',
            allOf(
              contains('running without the drive guest'),
              // The claim, and what it is made on.
              contains('none does'),
              contains('main, worker'),
            ),
          ),
        ),
      );
    });

    test('the sentence is the same one every other surface says', () {
      expect(
        DriveNoGuest.describe(),
        startsWith('This app is running without the drive guest'),
      );
      expect(DriveNoGuest.describe(), isNot(contains('Asked the VM')));
    });
  });
}

RunHandle _handle() => RunHandle(
  worktree: '/w',
  worktreeName: '~',
  device: 'macos',
  entrypoint: 'lib/main.dart',
  launcherPid: 1,
  startedAt: DateTime.now(),
  handlePath: '/w/run/handle.json',
  vmService: 'ws://127.0.0.1:1/ws',
);

IsolateRef _ref(String id, String name) =>
    IsolateRef(id: id, name: name, number: '1', isSystemIsolate: false);

/// A VM with a scripted isolate list, each isolate either holding the drive
/// extension or not.
class _FakeVm {
  _FakeVm() {
    service = VmService(_toClient.stream, _onRequest);
  }

  late final VmService service;
  final _toClient = StreamController<String>();

  /// Isolate id → whether `ext.flutterware.act` is registered in it. Insertion
  /// order is the order `getVM` reports.
  var isolates = <String, bool>{'main': true};

  /// Which isolates the act was addressed to, in order.
  final actCalls = <String>[];

  void _onRequest(String message) {
    var request = jsonDecode(message) as Map<String, Object?>;
    var id = request['id'];
    var method = request['method']! as String;
    var params = (request['params'] as Map?)?.cast<String, Object?>() ?? {};

    switch (method) {
      case 'getVM':
        _reply({
          'id': id,
          'result': {
            'type': 'VM',
            'name': 'vm',
            'architectureBits': 64,
            'hostCPU': 'test',
            'operatingSystem': 'test',
            'targetCPU': 'test',
            'version': '3',
            'pid': 1,
            'startTime': 0,
            'isolates': [
              for (var isolate in isolates.keys)
                {
                  'type': '@Isolate',
                  'id': isolate,
                  'number': '1',
                  'name': isolate,
                  'isSystemIsolate': false,
                },
            ],
            'isolateGroups': <Object?>[],
            'systemIsolates': <Object?>[],
            'systemIsolateGroups': <Object?>[],
          },
        });
      case 'getIsolate':
        var isolate = params['isolateId']! as String;
        _reply({
          'id': id,
          'result': {
            'type': 'Isolate',
            'id': isolate,
            'number': '1',
            'name': isolate,
            'isSystemIsolate': false,
            'isolateFlags': <Object?>[],
            'startTime': 0,
            'runnable': true,
            'livePorts': 1,
            'pauseOnExit': false,
            'breakpoints': <Object?>[],
            'exceptionPauseMode': 'None',
            'libraries': <Object?>[],
            'extensionRPCs': [if (isolates[isolate] ?? false) driveExtension],
          },
        });
      case driveExtension:
        var isolate = params['isolateId']! as String;
        actCalls.add(isolate);
        if (isolates[isolate] ?? false) {
          _reply({
            'id': id,
            'result': {
              'type': 'Success',
              'texts': ['Pay'],
            },
          });
        } else {
          _reply({
            'id': id,
            'error': {
              'code': -32601,
              'message': 'Unknown method "$driveExtension".',
              'data': <String, Object?>{},
            },
          });
        }
      default:
        _reply({
          'id': id,
          'error': {'code': -32601, 'message': 'no $method', 'data': {}},
        });
    }
  }

  void _reply(Map<String, Object?> message) {
    if (_toClient.isClosed) return;
    _toClient.add(jsonEncode(message));
  }

  Future<void> dispose() async {
    await _toClient.close();
    await service.dispose();
  }
}
