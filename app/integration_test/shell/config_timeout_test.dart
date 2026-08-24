import 'dart:io';

import 'package:flutterware_app/src/plugins/manifest_loader.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('a config that never exits is killed and reported', () async {
    var root = Directory.systemTemp.createTempSync('fw_hang');
    addTearDown(() => root.deleteSync(recursive: true));
    File(p.join(root.path, configFilePath))
      ..createSync(recursive: true)
      ..writeAsStringSync('void main() { while (true) {} }');
    File(p.join(root.path, '.dart_tool', 'package_config.json'))
      ..createSync(recursive: true)
      ..writeAsStringSync('{"configVersion":2,"packages":[]}');

    var loader = ManifestLoader(
      dartExecutable: Platform.resolvedExecutable,
      timeout: const Duration(seconds: 3),
    );

    var watch = Stopwatch()..start();
    var result = await loader.tryLoad(root.path);
    watch.stop();

    print(
      '  -> ${watch.elapsed.inSeconds}s: ${result.error?.split("\n").first}',
    );
    expect(result.error, contains('did not finish'));
    expect(
      watch.elapsed.inSeconds,
      lessThan(25),
      reason: 'it must not wait forever',
    );
  }, timeout: const Timeout(Duration(minutes: 2)));
}
