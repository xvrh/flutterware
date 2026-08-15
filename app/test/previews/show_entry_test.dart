import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware_app/src/embedder/guest_vm_service.dart';
import 'package:flutterware_app/src/previews/inspect_client.dart';
import 'package:vm_service/vm_service.dart';

/// A guest that answers `showEntry` with whatever it is *actually* showing.
///
/// Against the real [VmService] client rather than a stub of [InspectClient],
/// for the reason `guest_vm_service_test` gives: what is under test is how an
/// answer is read, and a stub that returned the decision would be testing the
/// test.
class _FakeGuest {
  _FakeGuest({required this.holds, required this.showing}) {
    service = VmService(_toClient.stream, _onRequest);
  }

  /// The entries this guest's program was compiled with. Anything else it can
  /// only refuse — a demo the compiler quarantined, or one that appeared on
  /// disk after it started.
  final Set<String> holds;

  /// What is on screen, which the call moves when it can.
  String showing;

  /// Null makes every call a JSON-RPC 32601 — a guest from before the
  /// extension existed.
  var registered = true;

  late final VmService service;
  final _toClient = StreamController<String>();

  void _onRequest(String message) {
    var request = jsonDecode(message) as Map<String, Object?>;
    var id = request['id'];
    if (!registered) {
      _reply({
        'id': id,
        'error': {'code': -32601, 'message': 'method not found', 'data': {}},
      });
      return;
    }
    var params = (request['params'] as Map?)?.cast<String, Object?>() ?? {};
    var wanted = params['id'] as String?;
    if (wanted != null && holds.contains(wanted)) showing = wanted;
    // What the guest's own extension answers with: whatever is on screen after
    // the call, which is how a refusal tells itself from a switch.
    _reply({
      'id': id,
      'result': {'type': 'Response', 'entry': showing},
    });
  }

  void _reply(Map<String, Object?> response) =>
      _toClient.add(jsonEncode({'jsonrpc': '2.0', ...response}));

  Future<void> close() => _toClient.close();
}

void main() {
  InspectClient clientOf(_FakeGuest guest) => InspectClient(
    GuestVmService.forTesting(guest.service, 'isolates/1'),
    patience: InspectPatience.live,
  );

  test('an entry the program holds is shown, with nothing compiled', () async {
    // The whole point: the generated entrypoint imports every entry, so moving
    // between two of them is a message and a frame rather than a compile, a
    // hot reload and a reassemble to change which entry one getter names.
    var guest = _FakeGuest(
      holds: {'demo/a.dart#alpha', 'demo/b.dart#beta'},
      showing: 'demo/a.dart#alpha',
    );
    addTearDown(guest.close);

    expect(await clientOf(guest).showEntry('demo/b.dart#beta'), isTrue);
    expect(guest.showing, 'demo/b.dart#beta');
  });

  test('an entry it does not hold is a refusal, not a throw', () async {
    // A quarantined demo is not in the program at all. The host's recovery is
    // the compile and the reload it would have done anyway, so this has to be
    // a value it can branch on rather than an exception path on both sides.
    var guest = _FakeGuest(
      holds: {'demo/a.dart#alpha'},
      showing: 'demo/a.dart#alpha',
    );
    addTearDown(guest.close);

    expect(await clientOf(guest).showEntry('demo/b.dart#beta'), isFalse);
    expect(guest.showing, 'demo/a.dart#alpha', reason: 'and nothing moved');
  });

  test('a guest from before the extension refuses the same way', () async {
    var guest = _FakeGuest(holds: {'demo/a.dart#alpha'}, showing: 'x')
      ..registered = false;
    addTearDown(guest.close);

    expect(await clientOf(guest).showEntry('demo/a.dart#alpha'), isFalse);
  });
}
