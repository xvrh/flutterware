import 'dart:io';
import 'package:path/path.dart' as p;

import 'shim_template.dart';

/// Builds the per-project SDK mirror facade at `<projectRoot>/flutterware/sdk/`.
///
/// Every entry of [sharedSdk] is symlinked into the mirror, except `bin/`,
/// which is a real directory whose `flutter`/`dart` are generated shims and
/// whose other entries are symlinks. The mirror is rebuilt from scratch on
/// every call (idempotent). Returns the mirror directory.
Directory installMirror({
  required Directory sharedSdk,
  required Directory projectRoot,
  required String wrapExe,
}) {
  final mirror = Directory(p.join(projectRoot.path, 'flutterware', 'sdk'));
  if (mirror.existsSync()) mirror.deleteSync(recursive: true);
  mirror.createSync(recursive: true);

  final mirrorBin = Directory(p.join(mirror.path, 'bin'))..createSync();

  // Top-level SDK entries (skip `bin`) -> symlinks.
  for (final entry in sharedSdk.listSync()) {
    final name = p.basename(entry.path);
    if (name == 'bin') continue;
    Link(p.join(mirror.path, name)).createSync(entry.path);
  }

  // bin/ entries (skip the two wrapped binaries) -> symlinks.
  final sharedBin = Directory(p.join(sharedSdk.path, 'bin'));
  for (final entry in sharedBin.listSync()) {
    final name = p.basename(entry.path);
    if (name == 'flutter' || name == 'dart') continue;
    Link(p.join(mirrorBin.path, name)).createSync(entry.path);
  }

  // The two shims.
  _writeShim(
    file: File(p.join(mirrorBin.path, 'flutter')),
    realBinary: p.join(sharedBin.path, 'flutter'),
    kind: 'flutter',
    wrapExe: wrapExe,
  );
  _writeShim(
    file: File(p.join(mirrorBin.path, 'dart')),
    realBinary: p.join(sharedBin.path, 'dart'),
    kind: 'dart',
    wrapExe: wrapExe,
  );

  return mirror;
}

void _writeShim({
  required File file,
  required String realBinary,
  required String kind,
  required String wrapExe,
}) {
  file.writeAsStringSync(renderShim(
    realBinary: realBinary,
    kind: kind,
    wrapExe: wrapExe,
  ));
  // chmod +x.
  Process.runSync('chmod', ['+x', file.path]);
}
