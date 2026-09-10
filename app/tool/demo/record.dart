import 'dart:convert';
import 'dart:io';

import 'package:flutterware_app/src/demo/recording_paths.dart';
import 'package:flutterware_app/src/launcher_icon/model/scan.dart';
import 'package:path/path.dart' as p;

/// Writes the recording the studio's demos open: `app/demo/fixture/`.
///
/// Runs the real readers on a real project and keeps what they produced, with
/// every file they name copied in beside it. Nothing here is written by hand,
/// so the recording is only ever an output of the shipped formats and cannot
/// drift from the code that reads it — a recording that stops loading is a
/// format change, found at the right time.
///
/// ```sh
/// cd app && fvm dart run tool/demo/record.dart [project-dir]
/// ```
///
/// The project defaults to `examples/example`, recorded **as if it were the
/// root of its own repository**: its package path in the recording is `.`.
/// That is what a reader's project usually looks like, and it keeps the
/// recorded project's workspace to one package nothing on disk has to
/// confirm.
void main(List<String> arguments) {
  var appRoot = p.dirname(p.dirname(p.dirname(p.fromUri(Platform.script))));
  var project = arguments.isEmpty
      ? p.join(p.dirname(appRoot), 'examples', 'example')
      : p.normalize(p.absolute(arguments.first));
  var out = p.join(appRoot, 'demo', 'fixture');

  if (!File(p.join(project, 'pubspec.yaml')).existsSync()) {
    stderr.writeln('Not a package: $project');
    exit(1);
  }

  var written = _recordLauncherIcons(project: project, out: out);
  print(
    'Recorded ${p.relative(project, from: p.dirname(appRoot))} into '
    '${p.relative(out, from: appRoot)}: $written',
  );
}

/// The default scan and one per flavor, with the files copied flat.
String _recordLauncherIcons({required String project, required String out}) {
  const packagePath = '.';
  var dir = Directory(p.join(out, 'launcher_icon'));
  // Generated wholesale: a flavor that no longer exists would otherwise leave
  // its scan behind, and the recording would claim it.
  if (dir.existsSync()) dir.deleteSync(recursive: true);

  var flavors = <String?>[
    null,
    for (var flavor in discoverIconFlavors(project)) flavor.name,
  ];
  var copied = <String, int>{};
  for (var flavor in flavors) {
    var scan = scanIcons(
      packageRoot: project,
      packagePath: packagePath,
      flavor: flavor,
    );
    var json = scan.toJson();
    for (var role in json['roles']! as List) {
      for (var file in ((role as Map)['files'] as List? ?? const [])) {
        var entry = file as Map;
        var source = File(entry['absolutePath']! as String);
        var destination = recordedIconFilePath(
          packagePath,
          entry['path']! as String,
        );
        if (!copied.containsKey(destination)) {
          var target = File(p.join(out, destination))
            ..parent.createSync(recursive: true);
          source.copySync(target.path);
          copied[destination] = source.lengthSync();
        }
        entry['absolutePath'] = destination;
      }
    }
    File(p.join(out, recordedIconScanPath(packagePath, flavor: flavor)))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert(json)}\n',
      );
  }

  var bytes = copied.values.fold(0, (sum, length) => sum + length);
  return '${flavors.length} launcher icon scans '
      '(${flavors.skip(1).join(', ')}), ${copied.length} files, '
      '${(bytes / 1024).toStringAsFixed(0)} KB';
}
