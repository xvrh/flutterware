import 'package:flutterware/internals/remote_log.dart';

import 'utils/resource_cleaner.dart';

class Globals {
  final resourceCleaner = ResourceCleanerService();
  LogClient logger = LogClient.print();
}

//TODO(xha): allow to override in test
final globals = Globals();
