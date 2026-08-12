import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware_app/src/run/connection.dart';
import 'package:flutterware_app/src/run/network_tracker.dart';
import 'package:vm_service/vm_service.dart';

/// A VM whose `ext.dart.io.*` answers are scripted per test — the profile is
/// the VM's own data structure, so unlike the channel tests there is no real
/// guest half to run; what is under test is the tracker's read of the
/// protocol's semantics (upsert, cursor, restart wipe).
class _FakeVm {
  _FakeVm() {
    service = VmService(_toClient.stream, _onRequest);
  }

  late final VmService service;
  final _toClient = StreamController<String>();

  var isolateId = 'isolates/1';

  /// The next `getHttpProfile` answers, consumed front to back; empty when
  /// exhausted.
  final profiles = <Map<String, Object?>>[];
  var profileCalls = 0;
  final updatedSinceSeen = <int?>[];

  /// Detail JSON by request id.
  final details = <String, Map<String, Object?>>{};
  var detailCalls = 0;

  var enableCalls = 0;
  var clearCalls = 0;

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
              {
                'type': '@Isolate',
                'id': isolateId,
                'number': '1',
                'name': 'main',
                'isSystemIsolate': false,
              },
            ],
            'isolateGroups': <Object?>[],
            'systemIsolates': <Object?>[],
            'systemIsolateGroups': <Object?>[],
          },
        });
      case 'getIsolate':
        // The typed extension asserts availability by reading extensionRPCs.
        _reply({
          'id': id,
          'result': {
            'type': 'Isolate',
            'id': isolateId,
            'number': '1',
            'name': 'main',
            'isSystemIsolate': false,
            'isolateFlags': <Object?>[],
            'startTime': 0,
            'runnable': true,
            'livePorts': 1,
            'pauseOnExit': false,
            'breakpoints': <Object?>[],
            'exceptionPauseMode': 'None',
            'libraries': <Object?>[],
            'extensionRPCs': [
              'ext.dart.io.httpEnableTimelineLogging',
              'ext.dart.io.getHttpProfile',
              'ext.dart.io.getHttpProfileRequest',
              'ext.dart.io.clearHttpProfile',
            ],
          },
        });
      case 'ext.dart.io.getVersion':
        _reply({
          'id': id,
          'result': {'type': 'Version', 'major': 1, 'minor': 6},
        });
      case 'ext.dart.io.httpEnableTimelineLogging':
        enableCalls++;
        _reply({
          'id': id,
          'result': {'type': 'HttpTimelineLoggingState', 'enabled': true},
        });
      case 'ext.dart.io.getHttpProfile':
        updatedSinceSeen.add(params['updatedSince'] as int?);
        var profile = profiles.isEmpty
            ? {'type': 'HttpProfile', 'timestamp': 0, 'requests': <Object?>[]}
            : profiles.removeAt(0);
        profileCalls++;
        _reply({'id': id, 'result': profile});
      case 'ext.dart.io.getHttpProfileRequest':
        detailCalls++;
        var detail = details[params['id']];
        if (detail == null) {
          _reply({
            'id': id,
            'error': {'code': -32602, 'message': 'no request', 'data': {}},
          });
        } else {
          _reply({'id': id, 'result': detail});
        }
      case 'ext.dart.io.clearHttpProfile':
        clearCalls++;
        _reply({
          'id': id,
          'result': {'type': 'Success'},
        });
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

Map<String, Object?> _request(
  String id, {
  String method = 'GET',
  String path = '/hello',
  int? statusCode,
  int startTime = 1000,
}) => {
  'type': 'HttpProfileRequest',
  'isolateId': 'isolates/1',
  'id': id,
  'method': method,
  'uri': 'http://localhost:1234$path',
  'startTime': startTime,
  'events': <Object?>[],
  if (statusCode != null) 'endTime': startTime + 500,
  if (statusCode != null)
    'response': {
      'startTime': startTime + 200,
      'endTime': startTime + 1500,
      'statusCode': statusCode,
      'redirects': <Object?>[],
    },
};

Map<String, Object?> _profile(
  int timestamp,
  List<Map<String, Object?>> requests,
) => {'type': 'HttpProfile', 'timestamp': timestamp, 'requests': requests};

void main() {
  late _FakeVm vm;
  late RunNetworkTracker tracker;

  setUp(() async {
    vm = _FakeVm();
    var connection = await RunConnection.forTesting(vm.service, 'isolates/1');
    tracker = RunNetworkTracker(connection);
  });

  tearDown(() async {
    tracker.dispose();
    await vm.dispose();
  });

  test(
    'an in-flight request is one row, updated in place on completion',
    () async {
      vm.profiles.add(_profile(10, [_request('r1')]));
      await tracker.poll();
      expect(tracker.requests, hasLength(1));
      expect(tracker.requests.single.response, isNull);

      vm.profiles.add(_profile(20, [_request('r1', statusCode: 200)]));
      await tracker.poll();
      expect(tracker.requests, hasLength(1));
      expect(tracker.requests.single.response?.statusCode, 200);
    },
  );

  test("the cursor is the previous reply's timestamp", () async {
    vm.profiles.add(_profile(10, [_request('r1', statusCode: 200)]));
    await tracker.poll();
    await tracker.poll();
    expect(vm.updatedSinceSeen, [null, 10]);
  });

  test('a hot restart wipes the session and re-arms capture', () async {
    vm.profiles.add(_profile(10, [_request('r1', statusCode: 200)]));
    await tracker.poll();
    expect(tracker.requests, hasLength(1));
    expect(vm.enableCalls, 1);

    vm.isolateId = 'isolates/2';
    vm.profiles.add(_profile(5, <Map<String, Object?>>[]));
    await tracker.poll();
    expect(tracker.requests, isEmpty);
    expect(vm.enableCalls, 2);
    // A fresh isolate means a fresh clock — the old cursor must not filter
    // the new session's rows.
    expect(vm.updatedSinceSeen.last, isNull);
  });

  test(
    'details are cached, and a completed row drops the in-flight copy',
    () async {
      vm.profiles.add(_profile(10, [_request('r1')]));
      await tracker.poll();
      vm.details['r1'] = _request('r1');
      await tracker.detailsFor('r1');
      await tracker.detailsFor('r1');
      expect(vm.detailCalls, 1);

      vm.profiles.add(_profile(20, [_request('r1', statusCode: 200)]));
      await tracker.poll();
      vm.details['r1'] = _request('r1', statusCode: 200);
      var detail = await tracker.detailsFor('r1');
      expect(vm.detailCalls, 2);
      expect(detail?.response?.statusCode, 200);
    },
  );

  test('the detail cache is bounded by body bytes', () async {
    var connection = await RunConnection.forTesting(vm.service, 'isolates/1');
    tracker.dispose();
    tracker = RunNetworkTracker(connection, detailByteCap: 10);
    vm.profiles.add(
      _profile(10, [
        _request('r1', statusCode: 200),
        _request('r2', statusCode: 200),
      ]),
    );
    await tracker.poll();
    vm.details['r1'] = {
      ..._request('r1', statusCode: 200),
      'responseBody': List.filled(8, 65),
    };
    vm.details['r2'] = {
      ..._request('r2', statusCode: 200),
      'responseBody': List.filled(8, 66),
    };
    await tracker.detailsFor('r1');
    await tracker.detailsFor('r2');
    // r1 was evicted to stay under the cap; asking again refetches.
    await tracker.detailsFor('r1');
    expect(vm.detailCalls, 3);
  });

  test('a vanished request answers null rather than throwing', () async {
    vm.profiles.add(_profile(10, [_request('r1', statusCode: 200)]));
    await tracker.poll();
    expect(await tracker.detailsFor('gone'), isNull);
  });

  test('clear drops both sides', () async {
    vm.profiles.add(_profile(10, [_request('r1', statusCode: 200)]));
    await tracker.poll();
    await tracker.clear();
    expect(vm.clearCalls, 1);
    expect(tracker.requests, isEmpty);
  });
}
