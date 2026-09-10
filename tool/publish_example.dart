/// Publishes `examples/brewline/` to its own repository.
///
/// ```sh
/// fvm dart tool/publish_example.dart            # push
/// fvm dart tool/publish_example.dart --dry-run  # stage and diff, push nothing
/// ```
///
/// **This repository stays the source of truth.** The demo is developed here,
/// beside the tool it demonstrates, so a change to a plugin and the change to
/// the project that shows it off land in one commit and one review. The public
/// repository is a projection of `examples/brewline/`, rebuilt by this script
/// and never edited directly — anything committed over there is lost on the
/// next run, which is what `--delete` below means.
///
/// The alternative was curating `examples/example` on the way out. It was
/// rejected: that package is flutterware's fixture, and most of its previews
/// are engine probes (`gpu_smoke`, `fox_probe`, `model_probe`) that would give
/// a stranger a debug harness as their first impression. A demo is a different
/// artifact from a fixture, so it is a different directory.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

/// Where the demo lives here, and where it goes.
const source = 'examples/brewline';
const remote = 'https://github.com/flutterware/flutterware_example.git';

/// **What gets published is what `git` tracks, and that is the whole rule.**
///
/// The first version of this kept a list of things to leave out. A list is
/// always one leak behind: it had `.dart_tool`, `build` and
/// `pubspec_overrides.yaml` on it and still would have published
/// `ios/Flutter/flutter_export_environment.sh`, which `flutter create` fills
/// with absolute paths to the machine that ran it, and `.idea/workspace.xml`,
/// which is local IDE state.
///
/// Asking git instead inverts the default: a file reaches the public
/// repository only by being deliberately added to this one, and every
/// `.gitignore` already written — this repo's, and Flutter's own conventions
/// inside it — is enforced for free. `pubspec_overrides.yaml` is excluded
/// because it is ignored here, not because a list remembered it.

Future<void> main(List<String> args) async {
  var dryRun = args.contains('--dry-run');
  var root = _repoRoot();
  var src = p.join(root, source);
  if (!Directory(src).existsSync()) {
    _fail('no $source in $root');
  }

  var work = p.join(root, 'build', 'flutterware_example');
  Directory(p.dirname(work)).createSync(recursive: true);
  if (!Directory(p.join(work, '.git')).existsSync()) {
    if (Directory(work).existsSync()) {
      Directory(work).deleteSync(recursive: true);
    }
    stdout.writeln('Cloning $remote');
    await _run('git', ['clone', remote, work], cwd: root);
  } else {
    // The remote can move — the repository was transferred to an organisation
    // once already. A clone left pointing at the old path keeps working on
    // GitHub's redirect, which is exactly the kind of working-by-accident that
    // stops working later.
    await _run('git', ['remote', 'set-url', 'origin', remote], cwd: work);
    await _run('git', ['fetch', 'origin'], cwd: work);
    // The remote is a projection; anything on it that did not come from here
    // is not something to merge with.
    await _run(
      'git',
      ['reset', '--hard', 'origin/HEAD'],
      cwd: work,
      allowFail: true,
    );
  }

  var tracked = (await _capture('git', [
    'ls-files',
    '-z',
    '--',
    source,
  ], cwd: root)).split('\u0000').where((f) => f.isNotEmpty).toList();
  if (tracked.isEmpty) {
    _fail(
      'git tracks no files under $source.\n'
      'Commit the demo here first — this script publishes the tracked tree, '
      'not the working directory.',
    );
  }

  stdout.writeln(
    'Copying ${tracked.length} tracked files -> '
    '${p.relative(work, from: root)}',
  );
  // Everything the projection had, minus its own history: what is not tracked
  // here has to disappear over there too, or a deleted file lives on forever.
  //
  // **Except the clone's own working state.** `tool/screenshots.dart` takes
  // every picture against this checkout — it is the only way the shell will
  // address the demo — so it keeps a resolution and an override here. Deleting
  // those made publishing and photographing mutually destructive: a publish
  // wiped `.dart_tool/`, and the next screenshot run failed on a clone that
  // was no longer resolved. None of these are tracked over there anyway; the
  // published `.gitignore` names every one.
  const keep = {'.git', '.dart_tool', 'build', 'pubspec_overrides.yaml'};
  for (var entity in Directory(work).listSync()) {
    if (keep.contains(p.basename(entity.path))) continue;
    entity.deleteSync(recursive: true);
  }
  for (var file in tracked) {
    var target = p.join(work, p.relative(file, from: source));
    Directory(p.dirname(target)).createSync(recursive: true);
    File(p.join(root, file)).copySync(target);
  }

  File(p.join(work, '.gitignore')).writeAsStringSync(_gitignore);

  var sha = (await _capture('git', [
    'rev-parse',
    '--short',
    'HEAD',
  ], cwd: root)).trim();
  await _run('git', ['add', '-A'], cwd: work);
  var status = await _capture('git', ['status', '--porcelain'], cwd: work);
  if (status.trim().isEmpty) {
    stdout.writeln('Nothing changed. The published copy is already current.');
    return;
  }
  stdout.writeln(status);

  if (dryRun) {
    stdout.writeln('--dry-run: staged in $work, nothing committed or pushed.');
    return;
  }
  await _run('git', ['commit', '-m', 'Sync from flutterware@$sha'], cwd: work);
  await _run('git', ['push', 'origin', 'HEAD'], cwd: work);
  stdout.writeln('\nPushed. ${remote.replaceFirst(RegExp(r'\.git$'), '')}');
}

/// The published repository's own root ignore file.
///
/// Written rather than copied: this repo's `.gitignore` covers a monorepo and
/// most of it means nothing over there. The per-platform ones Flutter
/// generates (`android/.gitignore`, `ios/.gitignore`) are tracked files, so
/// they come across on their own — and they are what keeps
/// `flutter_export_environment.sh` and `Flutter/ephemeral/`, both full of
/// absolute paths, out of a clone.
const _gitignore = '''
# Generated by flutterware's tool/publish_example.dart. Edit it there.
.DS_Store
.dart_tool/
.idea/
.metadata
build/
*.iml

# Resolved per machine; a demo should resolve fresh on the one that clones it.
pubspec.lock

# Only meaningful inside the flutterware checkout this is developed in.
pubspec_overrides.yaml
''';

/// Git is spawned with `GIT_DIR` **absent** rather than empty.
///
/// A worktree sets it, and an inherited one points every command below at the
/// wrong repository; an empty one is fatal rather than ignored, so it has to be
/// removed from the map and not blanked.
Map<String, String> get _env {
  var env = Map.of(Platform.environment)
    ..remove('GIT_DIR')
    ..remove('GIT_WORK_TREE')
    ..remove('GIT_INDEX_FILE');
  return env;
}

Future<void> _run(
  String exe,
  List<String> args, {
  required String cwd,
  bool allowFail = false,
}) async {
  var result = await Process.run(
    exe,
    args,
    workingDirectory: cwd,
    environment: _env,
  );
  if (result.exitCode != 0 && !allowFail) {
    _fail('$exe ${args.join(' ')}\n${result.stdout}${result.stderr}');
  }
}

Future<String> _capture(
  String exe,
  List<String> args, {
  required String cwd,
}) async {
  var result = await Process.run(
    exe,
    args,
    workingDirectory: cwd,
    environment: _env,
  );
  if (result.exitCode != 0) {
    _fail('$exe ${args.join(' ')}\n${result.stderr}');
  }
  return result.stdout as String;
}

/// Anchored on this script rather than on cwd: run from a subdirectory it must
/// still find the same repository.
String _repoRoot() {
  var dir = File.fromUri(Platform.script).parent;
  while (true) {
    if (File(p.join(dir.path, 'pubspec.yaml')).existsSync()) return dir.path;
    var parent = dir.parent;
    if (parent.path == dir.path) throw StateError('no pubspec.yaml above');
    dir = parent;
  }
}

Never _fail(String message) {
  stderr.writeln('publish_example: $message');
  exit(1);
}
