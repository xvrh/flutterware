import 'dart:io';
import 'package:path/path.dart' as p;

/// A resolved flutterware project and the worktree the invocation is in.
class ProjectContext {
  final Directory projectRoot;
  final String worktreeName;
  ProjectContext(this.projectRoot, this.worktreeName);
}

/// Walks up from [start] looking for a `flutter_version` marker file.
/// Returns the directory that contains it, or null if none is found.
Directory? findProjectRoot(Directory start) {
  var dir = start.absolute;
  while (true) {
    if (File(p.join(dir.path, 'flutter_version')).existsSync()) return dir;
    final parent = dir.parent;
    if (parent.path == dir.path) return null;
    dir = parent;
  }
}

/// Resolves the worktree name for [projectRoot]. A linked worktree has a
/// `.git` *file* with a `gitdir:` pointer; the last path segment of that
/// pointer is the worktree name. A main checkout has a `.git` *directory*.
String resolveWorktreeName(Directory projectRoot) {
  final gitPath = p.join(projectRoot.path, '.git');
  if (FileSystemEntity.isDirectorySync(gitPath)) {
    return p.basename(projectRoot.path);
  }
  final gitFile = File(gitPath);
  if (gitFile.existsSync()) {
    final content = gitFile.readAsStringSync().trim();
    const prefix = 'gitdir:';
    if (content.startsWith(prefix)) {
      return p.basename(content.substring(prefix.length).trim());
    }
  }
  return p.basename(projectRoot.path);
}

/// Resolves the [ProjectContext] for an invocation made from [start],
/// or null if [start] is not inside a flutterware project.
ProjectContext? resolveProject(Directory start) {
  final root = findProjectRoot(start);
  if (root == null) return null;
  return ProjectContext(root, resolveWorktreeName(root));
}
