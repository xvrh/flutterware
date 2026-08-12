/// What a project says about which of its packages *is* the project.
///
/// Declared in `tool/flutterware.dart` like everything else:
///
/// ```dart
/// const webApp = Pkg('packages/web_app');
///
/// void main() => Flutterware.configure((fw) {
///   fw.identity(const ProjectIdentity(package: webApp));
///   fw.use(Previews());
/// });
/// ```
///
/// **Why a repository has to be asked.** A user runs one flutterware window per
/// repository and several at once, and every window looks the same: the same
/// name, the same icon. What tells them apart has to come from the project, and
/// a monorepo has no obvious answer to give — `rimbaud` holds a web app, an
/// admin app, a macOS utility and two plugin examples, all of them real. Which
/// one *is* the repository is a claim only the person who works there can make.
///
/// So this is a declaration and not an inference. `fw init` may scaffold a
/// guess, because a first launch has to show something, but the guess lands in
/// this file where it can be read and corrected rather than staying a rule
/// nobody can see.
///
/// **Deliberately not part of the launcher-icon plugin**, which reads no config
/// and runs no generator on purpose — see `LauncherIconCore`. That plugin
/// reports what an operating system shows; this says what a window is. Hanging
/// one off the other would couple two things that answer different questions.
library;

import 'package.dart';

/// The package that stands for the whole repository.
class ProjectIdentity {
  const ProjectIdentity({required this.package});

  /// Whose launcher icon and name represent this project.
  ///
  /// A [Pkg] rather than a path string, so it is the same value the plugins
  /// below it are configured with and a rename moves one constant.
  final Pkg package;

  Map<String, Object?> toJson() => {'package': package.path};

  /// **Tolerant of everything except a wrong shape**, like every other decoder
  /// that reads a manifest a previous version of flutterware wrote.
  ///
  /// A missing or non-string package is *no identity* rather than a throw: the
  /// worst this costs is a window that looks like every other window, which is
  /// exactly where the project started. Refusing to open it would be worse.
  static ProjectIdentity? fromJson(Map<String, Object?> json) =>
      switch (json['package']) {
        String path when path.isNotEmpty => ProjectIdentity(package: Pkg(path)),
        _ => null,
      };
}
