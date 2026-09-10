import 'dart:io';

import 'package:flutterware_app/src/utils/flutter_sdk.dart';
import 'package:path/path.dart' as p;

/// Builds the studio's web demo: `lib/main_demo_web.dart` compiled for the
/// web, with the recording copied beside it.
///
/// ```sh
/// cd app && fvm dart run tool/demo/build_web.dart [--base-href /flutterware/]
/// ```
///
/// The page reads its recording from `demo/fixture/` relative to the
/// document, so the recording must sit next to `index.html` — and it is not
/// an asset of the app, on purpose: see `lib/src/demo/recording.dart`. This
/// is the one place that knows both halves, which is why CI and
/// `integration_test/web_demo_test.dart` call it rather than
/// `flutter build web` directly.
///
/// The SDK is the one running this script, the same way every command in the
/// repository names its SDK.
Future<void> main(List<String> args) async {
  var baseHref = '/';
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--base-href' && i + 1 < args.length) {
      baseHref = args[++i];
    } else {
      stderr.writeln(
        'usage: dart run tool/demo/build_web.dart [--base-href /path/]',
      );
      exit(64);
    }
  }
  var packageRoot = p.dirname(p.dirname(p.dirname(p.fromUri(Platform.script))));
  var out = p.join(packageRoot, 'build', 'web');
  var sdk = await FlutterSdkPath.findSdk();
  if (sdk == null) {
    stderr.writeln(
      "Run this through a Flutter SDK's dart: fvm dart run tool/demo/build_web.dart",
    );
    exit(1);
  }
  var result = await Process.start(
    sdk.flutter,
    [
      'build',
      'web',
      '-t',
      'lib/main_demo_web.dart',
      '--base-href',
      baseHref,
      // Leaves out the service worker Flutter is retiring, which only ever
      // showed up as a console error on this page.
      '--pwa-strategy=none',
    ],
    workingDirectory: packageRoot,
    mode: ProcessStartMode.inheritStdio,
  );
  var code = await result.exitCode;
  if (code != 0) exit(code);

  var fixture = Directory(p.join(packageRoot, 'demo', 'fixture'));
  var target = Directory(p.join(out, 'demo', 'fixture'));
  if (target.existsSync()) target.deleteSync(recursive: true);
  var copied = 0;
  for (var entity in fixture.listSync(recursive: true)) {
    if (entity is! File) continue;
    var relative = p.relative(entity.path, from: fixture.path);
    File(p.join(target.path, relative))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(entity.readAsBytesSync());
    copied++;
  }
  print(
    'Copied $copied recording files to ${p.relative(target.path, from: packageRoot)}',
  );
}
