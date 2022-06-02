import 'package:flutter_test/flutter_test.dart';

class ScenarioBinding extends AutomatedTestWidgetsFlutterBinding {
  final void Function()? onReloaded;

  ScenarioBinding({this.onReloaded});

  @override
  bool get overrideHttpClient => false;

  @override
  Future<void> performReassemble() {
    onReloaded?.call();
    return super.performReassemble();
  }

  @override
  void scheduleWarmUpFrame() {
    if (inTest) {
      super.scheduleWarmUpFrame();
    } else {
      // A hot reload schedule a frame, if we are not running a test, this
      // will create an error.
    }
  }
}
