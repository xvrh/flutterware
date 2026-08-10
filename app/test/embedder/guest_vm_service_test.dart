import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware_app/src/embedder/guest_vm_service.dart';
import 'package:vm_service/vm_service.dart';

/// A VM service that answers by hand, so a test can decide when an extension
/// starts existing.
///
/// Against the real [VmService] client rather than a stub of [GuestVmService]:
/// what is under test is how a JSON-RPC 32601 is read, and a stub that returned
/// a Dart exception instead would be testing the test.
class _FakeGuest {
  _FakeGuest({required this.registerAfter}) {
    service = VmService(_toClient.stream, _onRequest);
  }

  /// How many calls answer "no such method" before the extension appears. The
  /// guest's `main` registering while the host is already asking.
  final int registerAfter;

  late final VmService service;
  final _toClient = StreamController<String>();

  /// Every extension call the client made, missing ones included.
  var calls = 0;

  void _onRequest(String message) {
    var request = jsonDecode(message) as Map<String, Object?>;
    var id = request['id'];
    var method = request['method']! as String;

    if (method == 'getIsolate') {
      _reply({
        'id': id,
        'result': {
          'type': 'Isolate',
          'id': 'isolates/1',
          'number': '1',
          'name': 'main',
          'isSystemIsolate': false,
          'isolateFlags': <Object?>[],
          'startTime': 0,
          'runnable': true,
          'livePorts': 0,
          'pauseOnExit': false,
          'pauseEvent': {'type': 'Event', 'kind': 'Resume', 'timestamp': 0},
          'libraries': <Object?>[],
          'breakpoints': <Object?>[],
          'exceptionPauseMode': 'None',
          'extensionRPCs': ['ext.flutterware.tree'],
        },
      });
      return;
    }

    calls++;
    if (calls <= registerAfter) {
      _reply({
        'id': id,
        'error': {'code': -32601, 'message': 'method not found', 'data': {}},
      });
    } else {
      _reply({
        'id': id,
        'result': {'watching': true, 'method': method},
      });
    }
  }

  void _reply(Map<String, Object?> response) =>
      _toClient.add(jsonEncode({'jsonrpc': '2.0', ...response}));

  Future<void> close() => _toClient.close();
}

void main() {
  group('requireExtension', () {
    test('waits out a guest that has not registered yet', () async {
      // The startup race: the VM service is listening, and this client has
      // connected, before the guest's `main` has run a single
      // `registerExtension`. Three misses is the panel mounting during it.
      var guest = _FakeGuest(registerAfter: 3);
      addTearDown(guest.close);
      var vm = GuestVmService.forTesting(guest.service, 'isolates/1');

      var json = await vm.requireExtension('ext.flutterware.watch');

      expect(json?['watching'], true);
      expect(guest.calls, 4, reason: 'three misses, then the one that landed');
    });

    test('still throws for an extension the guest never registers', () async {
      // The bug this strictness exists for — a write whose extension was
      // renamed — must survive the wait, or `setParameter` silently applying
      // nothing comes straight back.
      var guest = _FakeGuest(registerAfter: 1000);
      addTearDown(guest.close);
      var vm = GuestVmService.forTesting(
        guest.service,
        'isolates/1',
        registrationWindow: const Duration(milliseconds: 150),
      );

      await expectLater(
        vm.requireExtension('ext.flutterware.setParameter'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('the guest has no ext.flutterware.setParameter'),
              // And what it does register, which is how you spot the rename.
              contains('ext.flutterware.tree'),
            ),
          ),
        ),
      );
    });

    test('does not retry an error that is not "no such method"', () async {
      // A guest that is up and refusing is answering, not starting. Waiting on
      // it would turn every real failure into a five-second one.
      var guest = _FakeGuest(registerAfter: 0);
      addTearDown(guest.close);
      var vm = GuestVmService.forTesting(guest.service, 'isolates/1');

      unawaited(guest.service.dispose());

      await expectLater(
        vm.requireExtension('ext.flutterware.watch'),
        throwsA(anything),
      );
    });
  });

  test('callExtension stays tolerant, and answers immediately', () async {
    // The other half of the pair. A read of a guest too old to have the
    // extension is answered with null on the first try — the wait belongs to
    // writes, and a reader that waited would stall every cold start it is
    // meant to shrug off.
    var guest = _FakeGuest(registerAfter: 1000);
    addTearDown(guest.close);
    var vm = GuestVmService.forTesting(guest.service, 'isolates/1');

    expect(await vm.callExtension('ext.flutterware.knobs'), isNull);
    expect(guest.calls, 1);
  });
}
