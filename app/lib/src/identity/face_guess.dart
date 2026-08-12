import 'dart:io';

import 'package:path/path.dart' as p;

import '../launcher_icon/model/scan.dart';
import 'stock_icons.dart';

/// Which package a repository would probably call its face, before anyone has
/// said.
///
/// **This runs once, at `init`, and its answer is written into
/// `tool/flutterware.dart` where it can be read and corrected.** That is the
/// whole reason a guess is acceptable here: a monorepo genuinely has no obvious
/// answer — one real repository holds a web app, an admin app, a macOS utility
/// and two plugin examples — and which of them *is* the repository is a claim
/// only its author can make. A guess that lands in a file somebody reads is a
/// starting point; the same guess made silently at every launch would be a rule
/// nobody could see or change.
///
/// **The signal is not "is this an app" but "how many platforms have an icon
/// that is not the template's".** Platform count alone picks the wrong package:
/// in testing, a five-platform app whose iOS and Android icons were still stock
/// beat a two-platform one that had really been dressed. Somebody who bothered
/// to draw an icon for three platforms has told you which app they care about.
///
/// Measured against three real repositories — a 19-package monorepo, a
/// 9-package one and a single-package project — and correct on all three, in
/// about a second. That is a demonstration of feasibility, not a validated
/// weighting: they are also the repositories it was tuned on.
String? guessFacePackage(String root) {
  var candidates = <_Candidate>[];
  for (var pubspec in _pubspecs(root)) {
    var packageRoot = pubspec.parent.path;
    var relative = p.relative(packageRoot, from: root);
    var platforms = platformDirectories
        .where((d) => Directory(p.join(packageRoot, d)).existsSync())
        .length;
    // No platform directory means nothing to launch, so nothing to show.
    if (platforms == 0) continue;

    var scan = scanIcons(packageRoot: packageRoot, packagePath: relative);
    var dressed = 0;
    for (var role in faceRoles) {
      for (var found in scan.roles) {
        if (found.role != role || found.files.isEmpty) continue;
        var file = File(found.files.last.absolutePath);
        if (file.existsSync() && !isStockIcon(file)) dressed++;
        break;
      }
    }
    if (dressed == 0) continue;

    candidates.add(
      _Candidate(
        path: relative == '.' ? '.' : relative,
        dressed: dressed,
        platforms: platforms,
        // A demo inside a package is never the repository's app, however well
        // dressed — both monorepos tested had one that would otherwise rank.
        demo: p
            .split(relative)
            .any((s) => s == 'example' || s == 'examples' || s == 'demo'),
      ),
    );
  }
  if (candidates.isEmpty) return null;

  candidates.sort((a, b) {
    if (a.demo != b.demo) return a.demo ? 1 : -1;
    if (a.dressed != b.dressed) return b.dressed.compareTo(a.dressed);
    if (a.platforms != b.platforms) return b.platforms.compareTo(a.platforms);
    // Shallower wins: `packages/web_app` over `packages/sdk/plugin/example`.
    return p.split(a.path).length.compareTo(p.split(b.path).length);
  });
  return candidates.first.path;
}

/// Directories never worth descending into: build output, caches, and the
/// places other people's packages get copied to.
const _pruned = {
  'build',
  '.dart_tool',
  '.git',
  '.fvm',
  '.symlinks',
  'ephemeral',
  'Pods',
  'node_modules',
  'DerivedData',
};

/// Every `pubspec.yaml` under [root].
///
/// Walks and **prunes** rather than listing recursively and filtering. The
/// filtering version still descends into every `build/` on the way to
/// discarding it, which took 2.8s on a 19-package monorepo and would grow with
/// whatever is in there; pruning the same repo costs a fraction of that. This
/// runs inside `init`, where the budget is a user waiting at a prompt.
Iterable<File> _pubspecs(String root) sync* {
  var queue = <Directory>[Directory(root)];
  while (queue.isNotEmpty) {
    var directory = queue.removeLast();
    List<FileSystemEntity> entries;
    try {
      entries = directory.listSync(followLinks: false);
    } on FileSystemException {
      continue; // unreadable, which is not this feature's problem
    }
    for (var entity in entries) {
      var name = p.basename(entity.path);
      if (entity is Directory) {
        if (!_pruned.contains(name)) queue.add(entity);
      } else if (entity is File && name == 'pubspec.yaml') {
        yield entity;
      }
    }
  }
}

class _Candidate {
  _Candidate({
    required this.path,
    required this.dressed,
    required this.platforms,
    required this.demo,
  });

  final String path;
  final int dressed;
  final int platforms;
  final bool demo;
}
