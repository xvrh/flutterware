import 'dart:io';

import 'package:path/path.dart' as p;

import 'ignore.dart';

/// What a walk skips whatever `.gitignore` says, or fails to say.
///
/// Both names are reserved by tooling and never hold sources. `.git/` in
/// particular is *never* in a `.gitignore` — git has no need to ignore it — so
/// a gitignore-faithful walk that stopped here would still read every loose
/// object in the repository.
///
/// `build/` is deliberately not on this list: it is a legitimate directory name
/// below `lib/`, and every Flutter package template already ignores its own.
/// A package with no `.gitignore` anywhere above it and a populated `build/`
/// pays for it; that is the one case the floor does not cover.
const _hardFloor = '''
.git/
.dart_tool/
''';

/// Every file under [directory] that `git` would not consider ignored.
///
/// Ignores are read from [ignoreRoot] down, exactly as git reads them from
/// the repository root down — so listing a workspace member honours the
/// repository's own `.gitignore` even when the member has none. [ignoreRoot]
/// defaults to the enclosing git repository ([gitRootOf]), and to [directory]
/// itself when there is no repository above it.
///
/// Two departures from `git ls-files`, both deliberate: a file that has never
/// been added is listed (it is a source file that exists, which is what every
/// caller here means), and symlinks are dropped rather than followed.
///
/// Pass `ignoreRoot: directory` for a self-contained package that merely
/// happens to sit under a repository — anything in the pub cache, or a copy
/// being made of one. Inheritance is right for a directory inside the tree
/// somebody is working on and wrong for one that is not: a home directory kept
/// as a dotfiles repository ignoring `bin/` would otherwise silently drop
/// `bin/` from every package below it, which the empty-result guard below
/// cannot catch because the walk is not empty, only wrong.
Iterable<File> listFilesInDirectory(String directory, {String? ignoreRoot}) {
  var beneath = p.normalize(p.absolute(directory));
  var root = p.normalize(
    p.absolute(ignoreRoot ?? gitRootOf(beneath) ?? beneath),
  );
  // A root that does not contain the directory would put `..` in every path
  // below, which `Ignore.listFiles` rejects outright.
  if (!p.equals(root, beneath) && !p.isWithin(root, beneath)) root = beneath;

  var found = _walk(root, beneath);

  // **Inheriting ignores must never make the directory you asked for
  // invisible.** A rule above it that covers the directory itself empties the
  // walk outright, and the caller asked for that directory by name — the
  // dependencies plugin counting lines in `~/.pub-cache/hosted/…` under a home
  // directory that is itself a git repository ignoring `.pub-cache/` is the
  // real case, and it would silently report every package as zero bytes.
  //
  // Checked by result rather than up front: an empty walk is the only symptom,
  // and re-walking an empty tree costs nothing.
  if (found.isEmpty && !p.equals(root, beneath)) {
    return _walk(beneath, beneath);
  }
  return found;
}

List<File> _walk(String root, String beneath) {
  String resolve(String relative) => relative == '.' || relative.isEmpty
      ? root
      : p.joinAll([root, ...p.posix.split(relative)]);

  String relativize(String absolute) =>
      p.posix.joinAll(p.split(p.relative(absolute, from: root)));

  // Listing already learns each entity's type. Without carrying that over,
  // `isDir` stats every file a second time — which was most of the walk.
  var isDirectory = <String, bool>{};

  var found = Ignore.listFiles(
    beneath: p.equals(root, beneath) ? '' : relativize(beneath),
    listDir: (dir) {
      var names = <String>[];
      for (var entity in Directory(resolve(dir)).listSync(followLinks: false)) {
        // Symlinks are dropped, not followed. `.fvm/flutter_sdk` points at an
        // entire Flutter SDK — 15× this repository's own source in `.dart`
        // files alone — and a symlinked `node_modules` is the standard way to
        // make a recursive walk never finish.
        if (entity is Link) continue;
        var relative = relativize(entity.path);
        isDirectory[relative] = entity is Directory;
        names.add(relative);
      }
      return names;
    },
    ignoreForDir: (dir) =>
        _ignoreFor(resolve(dir), isRoot: dir == '.' || dir.isEmpty),
    isDir: (path) =>
        isDirectory[path] ??
        FileSystemEntity.typeSync(resolve(path), followLinks: false) ==
            FileSystemEntityType.directory,
  );
  return [for (var path in found) File(resolve(path))];
}

/// The rules that apply *in* [directory]: its `.gitignore`, and at the walk
/// root the hard floor and git's own exclude file as well.
///
/// `.git/info/exclude` is where a clone records ignores it does not share, so a
/// project relying on it looks like it has no ignores at all
/// from `.gitignore` alone. A worktree's `.git` is a file and has no `info/`,
/// which reads here as no exclude file rather than as an error.
///
/// Ordered as git orders them — the floor first, then the exclude file, then
/// the directory's own `.gitignore` — because a later rule wins.
///
/// Recompiled on every walk, deliberately. A cache keyed by the ignore files'
/// mtimes was written and measured against this: no difference at all. Compiling
/// the patterns is not what a walk spends its time on — a walk with *no rules*
/// over a larger tree costs the same as this one — so the cache was
/// invalidation logic for no gain.
Ignore? _ignoreFor(String directory, {required bool isRoot}) {
  var sources = [
    if (isRoot) File(p.join(directory, '.git', 'info', 'exclude')),
    File(p.join(directory, '.gitignore')),
  ];
  var patterns = [
    if (isRoot) _hardFloor,
    for (var source in sources)
      if (source.existsSync()) source.readAsStringSync(),
  ];
  return patterns.isEmpty ? null : Ignore(patterns);
}

/// The git repository [directory] belongs to, or `null` if it is not in one.
///
/// Matches a `.git` of either shape: a directory in a normal clone, a file
/// holding a `gitdir:` pointer in a worktree or a submodule.
String? gitRootOf(String directory) {
  var dir = p.normalize(p.absolute(directory));
  while (true) {
    if (FileSystemEntity.typeSync(p.join(dir, '.git')) !=
        FileSystemEntityType.notFound) {
      return dir;
    }
    var parent = p.dirname(dir);
    if (p.equals(parent, dir)) return null;
    dir = parent;
  }
}
