import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'utils/list_files.dart';

/// The mirror of a pub-cache flutterware in a writable tree: where it goes,
/// what it is made of, and when it has stopped being current.
///
/// The one place that knows what the copy is a **function of**. Getting that
/// wrong does not look like a stale copy — it looks like a compile error a
/// minute into a GUI build, in a package the project never asked for.

/// Where a pub-cache package is mirrored so there is a writable tree to resolve
/// and build in.
///
/// The hash is of the *flutterware package root*, which for a hosted dependency
/// already contains the version — so this is one copy per flutterware version
/// per machine, shared across every project that uses it, not one per project.
///
/// Split from the copy itself because the plan has to be decided before
/// anything runs, and deciding it means knowing this path first: whether the
/// CLI and the GUI need building are questions about files inside it.
String workingCopyPath(String packageRoot) =>
    p.join(userHomePath(), '.flutterware', hashOf(packageRoot));

/// Where [copyPackageInto] records the stamp of the copy it made.
File workingCopyStampFile(String root) => File(p.join(root, '.source_stamp'));

/// The files the copy is made of: everything the walk finds except
/// `pubspec.lock`.
///
/// **A lock is a resolution, and a resolution is a fact about one SDK.**
/// flutterware resolves its own workspace against the SDK it is developed on;
/// the copy is resolved and built by whichever SDK the consumer's project
/// names. Carrying the lock across that boundary hands them package versions
/// picked for a Dart they are not running, and `pub get` — lock-preserving by
/// design — honours it for as long as the file exists. A consumer on a newer
/// Flutter than this repository's pin gets a resolution that predates their
/// SDK, and the way that surfaces is a package in the middle of the graph
/// failing to *parse*. The copy resolves where it is built.
///
/// The same list backs [copyPackageInto] and [workingCopyStamp], so a file the
/// copy skips cannot invalidate it.
Iterable<File> packageFiles(String packageRoot) => listFilesInDirectory(
  packageRoot,
  ignoreRoot: packageRoot,
).where((file) => p.basename(file.path) != 'pubspec.lock');

/// Identifies everything the copy is built from, so one that is no longer
/// current is noticed without being declared.
///
/// **The SDK is an input, not a constant.** The tree is resolved by the Dart
/// running the launcher and built by the Flutter beside it, so the same sources
/// under a different SDK are a different copy: the versions that satisfied the
/// old one are not the versions the new one would pick, and the binaries are
/// the old one's output. Fingerprinting the sources alone made the copy "once
/// per flutterware version" exactly as the panel says — and left a project that
/// upgraded its SDK holding a resolution nothing would ever revisit.
///
/// [sdk] defaults to the running one; it is a parameter so a test can change
/// SDKs without changing Dart.
String workingCopyStamp(String packageRoot, {String? sdk}) {
  var files = <String>[];
  for (var file in packageFiles(packageRoot)) {
    var stat = file.statSync();
    files.add(
      '${p.relative(file.path, from: packageRoot)}'
      '|${stat.size}|${stat.modified.millisecondsSinceEpoch}',
    );
  }
  files.sort();
  return sha1
      .convert(utf8.encode([sdk ?? Platform.version, ...files].join('\n')))
      .toString();
}

/// [packageRoot] is its own ignore root, here and in [workingCopyStamp] and in
/// the launcher's freshness test: this package sits in the pub cache, and a
/// rule from some unrelated repository above it — `$HOME` kept as a dotfiles
/// repository is the way that happens — would drop files the copy has to carry.
void copyPackageInto(String packageRoot, String destination, String stamp) {
  for (var file in packageFiles(packageRoot)) {
    var target = p.join(destination, p.relative(file.path, from: packageRoot));
    File(target).createSync(recursive: true);
    file.copySync(target);
  }

  // Deleted rather than merely not copied: a copy an older flutterware made
  // brought one, and `pub get` would go on honouring it for as long as it sat
  // there. Removing it is what turns the next resolve into the consumer's own.
  var lock = File(p.join(destination, 'pubspec.lock'));
  if (lock.existsSync()) lock.deleteSync();

  // Last, so an interrupted copy is not recorded as a complete one.
  workingCopyStampFile(destination).writeAsStringSync(stamp);
}

String userHomePath() {
  var envKey = Platform.isWindows ? 'APPDATA' : 'HOME';
  return Platform.environment[envKey] ?? '.';
}

String hashOf(String input) => sha1
    .convert(utf8.encode(input))
    .bytes
    .map((b) => b.toRadixString(16).padLeft(2, '0'))
    .join();
