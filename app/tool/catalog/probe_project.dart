import 'dart:io';

import 'package:flutterware_app/src/catalog/compiler_daemon_client.dart';
import 'package:flutterware_app/src/catalog/package_config_locator.dart';
import 'package:flutterware_app/src/catalog/protocol.dart';
import 'package:flutterware_app/src/embedder/flutter_cache.dart';
import 'package:path/path.dart' as p;

/// Brings a catalog up against **someone else's project** and reports what it
/// found, without the GUI.
///
/// `headless_check.dart` points the daemon at the app package itself, so
/// `appPackageRoot` and `projectRoot` are the same directory there and every
/// path that conflates the two still works. This is the case that separates
/// them: the GUI owns `native/` and the build directory, the project owns the
/// demos, the package config and the assets.
///
/// ```sh
/// cd app && dart run tool/catalog/probe_project.dart ../examples/example
/// ```
Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('usage: probe_project.dart <projectRoot> [scanRoot]');
    exit(64);
  }

  var appPackageRoot = p.dirname(
    p.dirname(p.dirname(p.fromUri(Platform.script))),
  );
  var projectRoot = p.canonicalize(args.first);
  var scanRoot = args.length > 1 ? args[1] : 'demo';
  var cache = FlutterCache.fromRunningSdk();

  stdout.writeln('[probe] app     $appPackageRoot');
  stdout.writeln('[probe] project $projectRoot');
  stdout.writeln('[probe] config  ${requirePackageConfig(projectRoot)}');

  var watch = Stopwatch()..start();
  var (daemon, ready) = await CompilerDaemonClient.connect(
    dartExecutable: p.join(cache.flutterRoot, 'bin', 'dart'),
    config: DaemonConfig(
      appPackageRoot: appPackageRoot,
      projectRoot: projectRoot,
      packageConfig: requirePackageConfig(projectRoot),
      flutterSdkRoot: cache.flutterRoot,
      roots: [scanRoot],
    ),
    onLog: (line) => stdout.writeln('  [daemon] $line'),
  );

  try {
    stdout.writeln(
      '[probe] ready in ${watch.elapsedMilliseconds}ms '
      '(${ready.reused ? 'attached' : 'started'}), '
      'cold compile ${ready.coldCompile.inMilliseconds}ms',
    );
    for (var entry in ready.entries) {
      stdout.writeln(
        '  ${entry.group == null ? '' : '${entry.group} / '}${entry.name}'
        '  ${entry.id}',
      );
    }
    for (var broken in ready.quarantined) {
      stdout.writeln('  QUARANTINED ${broken.entry.id}');
      stdout.writeln('    ${broken.error.split('\n').first}');
    }
    if (ready.entries.isEmpty) {
      stderr.writeln('[probe] no entries under $scanRoot/');
      exit(1);
    }

    // Compiling one proves the resolution actually works — discovery is
    // syntactic and would happily list entries that cannot be built.
    var compiled = await daemon.select(ready.entries.last.id);
    stdout.writeln(
      compiled.ok
          ? '[probe] compiled ${ready.entries.last.name} in '
                '${compiled.compile.inMilliseconds}ms'
          : '[probe] FAILED to compile ${ready.entries.last.name}:\n'
                '${compiled.error}',
    );
    exit(compiled.ok ? 0 : 1);
  } finally {
    await daemon.close();
  }
}
