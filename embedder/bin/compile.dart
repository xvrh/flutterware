import 'dart:io';

import 'package:flutterware_embedder/compiler.dart';
import 'package:path/path.dart' as p;

/// Usage: `dart run flutterware_embedder:compile <entrypoint.dart> <output.dill>`
Future<void> main(List<String> args) async {
  if (args.length != 2) {
    stderr.writeln('usage: compile <entrypoint.dart> <output_dill>');
    exit(2);
  }
  var entrypoint = p.absolute(args[0]);
  var outputDill = p.absolute(args[1]);
  // This is a pub workspace: package_config.json lives at the repo root.
  // Platform.script -> <repo>/embedder/bin/compile.dart, so go up three dirs.
  var packageConfig = p.join(
      p.dirname(p.dirname(p.dirname(Platform.script.toFilePath()))),
      '.dart_tool',
      'package_config.json');

  var dill = await compileToKernel(
    entrypoint: entrypoint,
    outputDill: outputDill,
    packageConfig: packageConfig,
  );
  stdout.writeln('Wrote ${dill.lengthSync()} bytes to ${dill.path}');
}
