/// A package in the project, declared once in `tool/flutterware.dart` and
/// referenced by every plugin that operates on it.
///
/// Declaring it as a value rather than repeating a path string per plugin means
/// the path is written once, and a typo is a compile error instead of a silent
/// no-op.
class Pkg {
  const Pkg(this.path);

  /// Directory relative to the repo root — `packages/admin`, or `.` for a
  /// single-package project.
  final String path;

  /// The last path segment, as a default display name.
  String get name =>
      path == '.' ? '.' : path.split('/').where((s) => s.isNotEmpty).last;

  static Pkg fromJson(Map<String, Object?> json) =>
      Pkg(json['path']! as String);

  @override
  bool operator ==(Object other) => other is Pkg && other.path == path;

  @override
  int get hashCode => path.hashCode;

  @override
  String toString() => 'Pkg($path)';
}

/// Base for a plugin's per-package entry.
///
/// Plugins subclass this to carry their own options — a catalog needs an
/// entrypoint, a server needs a start command — because per-package
/// configuration is plugin-specific. The framework requires exactly one thing,
/// [path], which is the join key for validating declarations. Everything else is
/// the plugin's business and travels through [Plugin.config] as ordinary JSON.
abstract class PluginPackage {
  const PluginPackage(this.pkg);

  final Pkg pkg;

  String get path => pkg.path;

  /// Must include `path`; the rest is whatever the plugin needs.
  Map<String, Object?> toJson() => {'path': path};
}
