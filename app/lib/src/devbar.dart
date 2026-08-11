import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
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
            (await getApplicationSupportDirectory()).path,
            'variables-${_checkoutKey()}.json',
          ),
        ),
        DeviceFramePlugin.init(),
      ],
      flags: flags,
      child: child,
    );
  }
}

/// One overrides file per checkout, not one per bundle id.
///
/// Every worktree's dev Studio builds as `com.example.app`, so the support
/// directory this file lives in is one directory machine-wide — an
/// unqualified `variables.json` let a flag flipped in one worktree's Studio
/// surface in every other's on next launch. The executable of a dev build
/// sits under the checkout's own `build/` directory, which makes its path the
/// cheapest per-worktree identity the process already carries.
String _checkoutKey() => sha1
    .convert(utf8.encode(p.canonicalize(Platform.resolvedExecutable)))
    .toString()
    .substring(0, 12);
