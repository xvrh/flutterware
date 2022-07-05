import 'package:flutterware/internals/test_runner.dart';
import 'package:flutter/material.dart';

import 'phone_status_bar.dart';

class DeviceFrame extends StatelessWidget {
  final ScenarioRun run;
  final Widget child;

  const DeviceFrame({Key? key, required this.run, required this.child})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    var device = run.args.device;
    var devicePadding = EdgeInsets.fromLTRB(device.safeArea.left,
        device.safeArea.top, device.safeArea.right, device.safeArea.bottom);
    return MediaQuery(
      data: MediaQueryData(
        padding: devicePadding,
        viewPadding: devicePadding,
        size: Size(device.width, device.height),
      ),
      child: PhoneStatusBar(
        leftText: '09:42',
        brightness: Brightness.dark,
        viewPadding: run.args.device.safeArea.toEdgeInsets(),
        child: child,
      ),
    );
  }
}
