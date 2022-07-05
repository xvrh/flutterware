import 'dart:io';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;

final _logger = Logger('resource_cleaner');

class ResourceCleanerService {
  final _basePath = 'build/flutterware/process_to_kill';

  Future<void> initialize() async {
    var directory = Directory(_basePath);
    if (await directory.exists()) {
      await for (var file in directory.list()) {
        var pid = int.tryParse(p.basenameWithoutExtension(file.path));
        if (pid != null) {
          Process.killPid(pid);
          _logger.fine('Kill process $pid after Hot restart');
        }
        await file.delete();
      }
    }
  }

  Future<void> killProcessOnNextLaunch(int pid) async {
    File(p.join(_basePath, '$pid')).createSync(recursive: true);
  }
}
