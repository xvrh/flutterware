import 'dart:async';
import 'dart:convert';

import 'package:flutterware/src/inspect/node.dart';
import 'package:flutterware_app/src/run/connection.dart';
import 'package:flutterware_app/src/run/inspect.dart';
import 'package:test/test.dart';
import 'package:vm_service/vm_service.dart';

/// Which of the cockpit's two readers answers the Screen tab.
///
/// The service extension works against any Flutter app and carries structure
/// and creation locations only; the guest walks the app's own elements and
/// carries the boxes, the properties and the resolved text style with them.
/// A run launched through flutterware has both, and the detail pane is only
/// worth reading when the second one answered — so what is under test is the
/// preference, and every way it can fall back.
void main() {
  late _FakeVm vm;

  setUp(() => vm = _FakeVm());
  tearDown(() => vm.dispose());

  Future<RunInspector> inspector({String isolate = 'main'}) async =>
      RunInspector(await RunConnection.forTesting(vm.service, isolate));

  test('a run with a guest is read through it, boxes and all', () async {
    var read = await (await inspector()).read(tree: true, preferGuest: true);

    expect(read.fromGuest, isTrue);
    var root = read.tree!.root!;
    expect(root.type, 'MyApp');
    var text = root.children.single;
    expect(text.layout!.width, 120);
    expect(text.textStyle, {'size': '14.0', 'color': '#15181D'});
    expect(
      vm.calls,
      isNot(contains('ext.flutter.inspector.getRootWidgetTree')),
      reason:
          'a tree nobody is going to show is a tree nobody should pay for — '
          'the service call is only owed when a picture needs its id',
    );
  });

  test('a picture costs an id, not a second tree', () async {
    var read = await (await inspector()).read(
      tree: true,
      screenshot: true,
      preferGuest: true,
    );

    expect(read.fromGuest, isTrue);
    expect(read.tree!.root!.children.single.layout!.width, 120);
    expect(read.image, isNotNull);
    expect(
      vm.calls,
      contains('ext.flutter.inspector.getRootWidget'),
      reason:
          'the screenshot RPC takes an inspector id and the guest mints none '
          '— but the root node alone answers that, at 2.7ms against 122ms '
          'for the summary tree it would otherwise be read out of',
    );
    expect(
      vm.calls,
      isNot(contains('ext.flutter.inspector.getRootWidgetTree')),
    );
  });

  test('an app with no guest is read the way every app used to be', () async {
    vm.guest = null;

    var read = await (await inspector()).read(tree: true, preferGuest: true);

    expect(read.fromGuest, isFalse);
    expect(read.tree!.root!.type, 'MyApp');
    // The pane's sentence about boxes is drawn off `fromGuest`, so this is
    // the state it has to be false in.
    expect(read.tree!.root!.children.single.layout, isNull);
  });

  test('a guest in another isolate is found rather than concluded', () async {
    vm.isolates = ['worker', 'main'];
    vm.guestIsolate = 'main';

    var inspect = await inspector(isolate: 'worker');
    var read = await inspect.read(tree: true, preferGuest: true);

    expect(read.fromGuest, isTrue);
    expect(
      inspect.connection.isolateId,
      'main',
      reason:
          'the repair has to stick: the screenshot in this same read goes to '
          'the same connection, and so does the next one',
    );
  });

  test('a guest that has not built a frame is not preferred', () async {
    vm.guest = const InspectTree(entryId: null);

    var read = await (await inspector()).read(tree: true, preferGuest: true);

    expect(read.fromGuest, isFalse);
    expect(
      vm.calls,
      contains('ext.flutter.inspector.getRootWidgetTree'),
      reason: 'nothing to prefer means the service tree answers, as before',
    );
  });

  test('the full tree is a question the guest cannot answer', () async {
    var read = await (await inspector()).read(
      tree: true,
      summary: false,
      preferGuest: true,
    );

    expect(read.fromGuest, isFalse);
    expect(vm.calls, isNot(contains(guestTreeExtension)));
  });

  test('nobody is asked for a tree unless the caller wants one', () async {
    var read = await (await inspector()).read(preferGuest: true);

    expect(read.tree, isNull);
    expect(read.fromGuest, isFalse);
    expect(vm.calls, isNot(contains(guestTreeExtension)));
  });
}

/// The guest's tree: one text, with everything the service extension has no
/// way to hand out.
InspectTree _guestTree() => InspectTree(
  entryId: null,
  root: InspectNode(
    id: '',
    type: 'MyApp',
    children: [
      InspectNode(
        id: '0',
        type: 'Text',
        description: 'Text("Save")',
        layout: const InspectLayout(x: 8, y: 8, width: 120, height: 20),
        textStyle: const {'size': '14.0', 'color': '#15181D'},
      ),
    ],
  ),
);

/// A VM serving both readers, so a test can take either away.
class _FakeVm {
  _FakeVm() {
    service = VmService(_toClient.stream, _onRequest);
  }

  late final VmService service;
  final _toClient = StreamController<String>();

  /// What `ext.flutterware.tree` answers, or null for an app with no guest.
  InspectTree? guest = _guestTree();

  /// Which isolate holds it.
  String guestIsolate = 'main';

  var isolates = <String>['main'];

  /// Every extension called, in order.
  final calls = <String>[];

  void _onRequest(String message) {
    var request = jsonDecode(message) as Map<String, Object?>;
    var id = request['id'];
    var method = request['method']! as String;
    var params = (request['params'] as Map?)?.cast<String, Object?>() ?? {};
    calls.add(method);

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
              for (var isolate in isolates)
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
            'extensionRPCs': [
              if (guest != null && isolate == guestIsolate) guestTreeExtension,
            ],
          },
        });
      case guestTreeExtension:
        var isolate = params['isolateId']! as String;
        var tree = guest;
        if (tree == null || isolate != guestIsolate) {
          _error(id, -32601, 'Unknown method: $method');
        } else {
          _reply({
            'id': id,
            'result': {'type': 'Success', ...tree.toJson()},
          });
        }
      case 'ext.flutter.inspector.getRootWidgetTree':
        _reply({
          'id': id,
          'result': {
            'type': 'Success',
            'result': {
              'description': 'MyApp',
              'widgetRuntimeType': 'MyApp',
              'valueId': 'inspector-0',
              'children': [
                {
                  'description': 'Text',
                  'widgetRuntimeType': 'Text',
                  'textPreview': 'Save',
                },
              ],
            },
          },
        });
      case 'ext.flutter.inspector.getRootWidget':
        _reply({
          'id': id,
          'result': {
            'type': 'Success',
            'result': {'description': '[root]', 'valueId': 'inspector-0'},
          },
        });
      case 'ext.flutter.inspector.screenshot':
        _reply({
          'id': id,
          'result': {
            'type': 'Success',
            'result': base64Encode(const [1, 2, 3]),
          },
        });
      case 'ext.flutter.inspector.disposeGroup':
        _reply({
          'id': id,
          'result': {'type': 'Success'},
        });
      default:
        _error(id, -32601, 'Unknown method: $method');
    }
  }

  void _error(Object? id, int code, String message) => _reply({
    'id': id,
    'error': {'code': code, 'message': message},
  });

  void _reply(Map<String, Object?> response) =>
      _toClient.add(jsonEncode({'jsonrpc': '2.0', ...response}));

  void dispose() {
    service.dispose();
    unawaited(_toClient.close());
  }
}
