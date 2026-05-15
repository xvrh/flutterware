import 'dart:io';

import 'package:flutterware_app/src/embedder/compiler.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('compiles hello.dart to a non-empty kernel blob', () async {
    var packageRoot = Directory.current.path; // `dart test` runs from <app>
    var outDir = Directory.systemTemp.createTempSync('embedder_compile_test');
    addTearDown(() => outDir.deleteSync(recursive: true));
    var outputDill = p.join(outDir.path, 'kernel_blob.bin');

    // This is a pub workspace: the single package_config.json lives at the
    // repo root (the parent of the app package), not per-member.
    var repoRoot = p.dirname(packageRoot);
    var dill = await compileToKernel(
      entrypoint: p.join(packageRoot, 'tool', 'embedder', 'hello.dart'),
      outputDill: outputDill,
      packageConfig:
          p.join(repoRoot, '.dart_tool', 'package_config.json'),
    );

    expect(dill.existsSync(), isTrue);
    expect(dill.lengthSync(), greaterThan(0));
  }, timeout: const Timeout(Duration(minutes: 2)));
}
