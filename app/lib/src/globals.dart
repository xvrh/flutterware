import 'utils/resource_cleaner.dart';

class Globals {
  final resourceCleaner = ResourceCleanerService();
}

//TODO(xha): allow to override in test
final globals = Globals();
