import 'dart:io';

/// One-time setup: point git at the version-controlled `hooks/` directory.
/// Run once per clone (or worktree checkout):
///
///   dart tool/install_hooks.dart
void main() {
  final result = Process.runSync('git', ['config', 'core.hooksPath', 'hooks']);
  if (result.exitCode != 0) {
    stderr.writeln('Failed to set core.hooksPath: ${result.stderr}');
    exit(1);
  }
  print('Git hooks enabled — commits now run ./hooks/pre-commit '
      '(core.hooksPath=hooks).');
}
