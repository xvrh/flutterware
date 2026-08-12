import 'package:vm_service/vm_service_io.dart';

/// Reads whether an app's *engine* has semantics on, without turning it on.
/// Usage: `semantics_state.dart <ws-uri>`
Future<void> main(List<String> args) async {
  var service = await vmServiceConnectUri(args[0]);
  var vm = await service.getVM();
  var id = vm.isolates!.first.id!;
  var reply = await service.callServiceExtension(
    'ext.flutter.debugDumpSemanticsTreeInTraversalOrder',
    isolateId: id,
  );
  var data = '${reply.json?['data']}';
  print('semantics tree: ${data.length} chars');
  print(data.length > 200 ? data.substring(0, 200) : data);
  await service.dispose();
}
