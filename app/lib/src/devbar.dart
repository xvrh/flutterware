import 'package:flutter/material.dart';
import 'package:flutterware/devbar.dart';
import 'package:flutterware/devbar_plugins/device_frame.dart';
import 'package:flutterware/devbar_plugins/log_network.dart';
import 'package:flutterware/devbar_plugins/logger.dart';
import 'package:flutterware/devbar_plugins/variables.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class AppDevbar extends StatelessWidget {
  final Widget child;
  final List<FeatureFlagValue> flags;

  const AppDevbar({super.key, required this.child, required this.flags});

  @override
  Widget build(BuildContext context) {
    return Devbar(
      plugins: [
        LoggerPlugin.init(),
        LogNetworkPlugin.init(),
        VariablesPlugin.init(
          filePath: () async => p.join(
              (await getApplicationSupportDirectory()).path, 'variables.json'),
        ),
        DeviceFramePlugin.init(),
      ],
      flags: flags,
      child: child,
    );
  }
}
