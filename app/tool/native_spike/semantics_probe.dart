import 'package:vm_service/vm_service_io.dart';

/// Asks a running guest for its semantics tree, and turns it on first.
/// Usage: `semantics_probe.dart <ws-uri> [on|off]`
Future<void> main(List<String> args) async {
  var service = await vmServiceConnectUri(args[0]);
  var vm = await service.getVM();
  var id = vm.isolates!.first.id!;
  var reply = await service.callServiceExtension(
    'ext.flutterware.semantics',
    isolateId: id,
    args: {'on': args.length > 1 ? args[1] : 'true'},
  );
  var text = '${reply.json}';
  print('semantics tree: ${text.length} chars');
  if (text.length > 120) print(text.substring(0, 260));
  await service.dispose();
}
