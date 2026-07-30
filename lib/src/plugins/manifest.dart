import 'dart:convert';

import 'package.dart';
import 'plugin.dart';

/// What `tool/flutterware.dart` prints: the project's plugin declarations.
///
/// Bumped only on a breaking shape change; the GUI refuses a version it does
/// not understand rather than guessing.
const manifestVersion = 1;

/// One declared plugin, as read back by the GUI.
class PluginDeclaration {
  const PluginDeclaration({
    required this.id,
    required this.label,
    this.config = const {},
  });

  final String id;
  final String label;
  final Map<String, Object?> config;

  Map<String, Object?> toJson() => {
    'id': id,
    'label': label,
    if (config.isNotEmpty) 'config': config,
  };

  static PluginDeclaration fromJson(Map<String, Object?> json) =>
      PluginDeclaration(
        id: json['id']! as String,
        label: json['label']! as String,
        config: (json['config'] as Map?)?.cast<String, Object?>() ?? const {},
      );
}

/// The decoded manifest.
class PluginManifest {
  const PluginManifest(
    this.plugins, {
    this.packages = const [],
    this.version = manifestVersion,
  });

  final int version;
  final List<PluginDeclaration> plugins;

  /// The project's declared packages. Reference data: the GUI validates plugin
  /// package paths against it and warns on a mismatch, but nothing here is
  /// active on its own.
  final List<Pkg> packages;

  Map<String, Object?> toJson() => {
    'version': version,
    if (packages.isNotEmpty) 'packages': [for (var p in packages) p.toJson()],
    'plugins': [for (var p in plugins) p.toJson()],
  };

  static PluginManifest fromJson(Map<String, Object?> json) {
    var version = json['version']! as int;
    if (version != manifestVersion) {
      throw FormatException(
        'Unsupported flutterware manifest version $version '
        '(this build understands $manifestVersion).',
      );
    }
    return PluginManifest(
      [
        for (var p in (json['plugins']! as List).cast<Map<String, Object?>>())
          PluginDeclaration.fromJson(p),
      ],
      packages: [
        for (var p
            in (json['packages'] as List? ?? const [])
                .cast<Map<String, Object?>>())
          Pkg.fromJson(p),
      ],
      version: version,
    );
  }

  static PluginManifest parse(String source) =>
      fromJson(jsonDecode(source) as Map<String, Object?>);
}

/// The object a project's `tool/flutterware.dart` configures.
class FlutterwareConfig {
  final _plugins = <Plugin>[];
  final _packages = <Pkg>[];

  /// Declares the project's packages. Optional for a single-package project;
  /// required for anything a plugin wants to name.
  void packages(List<Pkg> packages) {
    for (var pkg in packages) {
      if (_packages.contains(pkg)) {
        throw StateError('Duplicate package "${pkg.path}".');
      }
      _packages.add(pkg);
    }
  }

  /// Registers a plugin. The same class may be used more than once as long as
  /// the instances have distinct ids.
  void use(Plugin plugin) {
    if (_plugins.any((p) => p.id == plugin.id)) {
      throw StateError(
        'Duplicate plugin id "${plugin.id}". Give one of them a distinct id.',
      );
    }
    _plugins.add(plugin);
  }

  PluginManifest toManifest() => PluginManifest([
    for (var p in _plugins)
      PluginDeclaration(id: p.id, label: p.label, config: p.config),
  ], packages: List.of(_packages));
}

/// Entry point for a project's `tool/flutterware.dart`:
///
/// ```dart
/// import 'package:flutterware/plugins.dart';
///
/// void main() => Flutterware.configure((fw) {
///   fw.use(TestRunner());
///   fw.use(UiCatalog());
/// });
/// ```
///
/// v1 builds the declaration set, prints the manifest as JSON, and returns. The
/// GUI runs this with a plain `dart run` and reads stdout — no resident
/// compiler, no long-lived config process. When the declarative tier lands this
/// grows a long-lived mode; the config file itself does not change.
class Flutterware {
  static void configure(
    void Function(FlutterwareConfig fw) build, {
    void Function(String line) emit = print,
  }) {
    var config = FlutterwareConfig();
    build(config);
    emit(jsonEncode(config.toManifest().toJson()));
  }
}
