import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import 'src/catalog/catalog_dev_screen.dart';
import 'src/utils/flutter_sdk.dart';

/// IDE dev entrypoint for the UI catalog loop.
///
/// A macOS app launched by `flutter run` has a stripped environment and a
/// working directory of `/`, so the package and SDK roots are passed in:
///
/// ```sh
/// cd app && flutter run -t lib/main_catalog_dev.dart -d macos \
///   --dart-define=FLUTTERWARE_APP_ROOT="$(pwd)" \
///   --dart-define=FLUTTER_SDK_ROOT="$(cd "$(dirname "$(which flutter)")/.." && pwd)"
/// ```
const _appRootDefine = String.fromEnvironment('FLUTTERWARE_APP_ROOT');
const _sdkRootDefine = String.fromEnvironment('FLUTTER_SDK_ROOT');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  var flutterSdkRoot = _sdkRootDefine;
  if (flutterSdkRoot.isEmpty) {
    var sdks = await FlutterSdkPath.findSdks();
    if (sdks.isNotEmpty) flutterSdkRoot = sdks.first.root;
  }

  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: const Color(0xff3366ff)),
      home: (_appRootDefine.isEmpty || flutterSdkRoot.isEmpty)
          ? const _MissingDefines()
          : CatalogDevScreen(
              appPackageRoot: _appRootDefine,
              flutterSdkRoot: flutterSdkRoot,
              // The demos live under `app/tool/catalog/`, so the app package
              // is both the scan root and the entrypoint's package.
              projectRoot: _appRootDefine,
              roots: const ['tool/catalog'],
            ),
    ),
  );
}

class _MissingDefines extends StatelessWidget {
  const _MissingDefines();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'The catalog harness needs the app and SDK paths.\n\n'
            'Run it with --dart-define FLUTTERWARE_APP_ROOT and '
            'FLUTTER_SDK_ROOT set — see the doc comment in '
            'app/lib/main_catalog_dev.dart.',
            style: TextStyle(color: Colors.red),
          ),
        ),
      ),
    );
  }
}
