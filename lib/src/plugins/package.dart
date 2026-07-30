/// A package in the project, declared once in `tool/flutterware.dart` and
/// referenced by every plugin that operates on it.
///
/// Declaring it as a value rather than repeating a path string per plugin means
/// the path is written once, tags are written once, and a typo is a compile
/// error instead of a silent no-op.
class Pkg {
  const Pkg(this.path, {this.tags = const []});

  /// Directory relative to the repo root — `packages/admin`, or `.` for a
  /// single-package project.
  final String path;

  /// Free-form labels used to group packages. The syntax ships now so config
  /// files do not need rewriting; filtering by tag is a later, host-side
  /// addition that no plugin has to know about.
  final List<String> tags;

  /// The last path segment, as a default display name.
  String get name =>
      path == '.' ? '.' : path.split('/').where((s) => s.isNotEmpty).last;

  Map<String, Object?> toJson() => {
    'path': path,
    if (tags.isNotEmpty) 'tags': tags,
  };

  static Pkg fromJson(Map<String, Object?> json) => Pkg(
    json['path']! as String,
    tags: (json['tags'] as List?)?.cast<String>() ?? const [],
  );

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
/// [path], which is the join key for validating declarations and for the later
/// tag filter. Everything else is the plugin's business and travels through
/// [Plugin.config] as ordinary JSON.
abstract class PluginPackage {
  const PluginPackage(this.pkg);

  final Pkg pkg;

  String get path => pkg.path;

  /// Must include `path`; the rest is whatever the plugin needs.
  ///
  /// [Pkg.tags] rides along because this is now the only thing that crosses to
  /// the host — there is no separate package list for them to travel in. They
  /// repeat across plugins that name the same [Pkg], which costs a few bytes of
  /// JSON and keeps the host from reading an empty tag list as "untagged".
  Map<String, Object?> toJson() => {
    'path': path,
    if (pkg.tags.isNotEmpty) 'tags': pkg.tags,
  };
}
