import 'dart:convert';

import 'address.dart';
import 'changes_config.dart';
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
    this.version = manifestVersion,
    this.changes,
  });

  final int version;
  final List<PluginDeclaration> plugins;

  /// What the project says about ranking its own changes, or null when it says
  /// nothing.
  ///
  /// **Not a plugin**, for the same reason the screen it feeds is not one: it
  /// has to be readable for a worktree with no session, which is precisely a
  /// worktree whose plugins have not been resolved.
  final ChangesConfig? changes;

  /// Every package any plugin names, in declaration order, deduplicated.
  ///
  /// Derived rather than declared. It used to be its own `fw.packages([...])`
  /// call, which meant a package a plugin was configured with but the list
  /// forgot was *silently dropped* from that plugin — the one failure mode a
  /// declaration list exists to prevent. Reading it off the plugins cannot
  /// disagree with them.
  List<Pkg> get packages {
    var byPath = <String, Pkg>{};
    for (var plugin in plugins) {
      for (var entry in (plugin.config['packages'] as List? ?? const [])) {
        if (entry is! Map) continue;
        if (entry['path'] case String path) {
          // First mention wins, so the order is the order they are read in. The
          // plugin's own keys in this entry — `entrypoint`, `directory` — are
          // not this decoder's business and are ignored.
          byPath.putIfAbsent(
            path,
            () => Pkg.fromJson(entry.cast<String, Object?>()),
          );
        }
      }
    }
    return byPath.values.toList();
  }

  Map<String, Object?> toJson() => {
    'version': version,
    'plugins': [for (var p in plugins) p.toJson()],
    'changes': ?changes?.toJson(),
  };

  static PluginManifest fromJson(Map<String, Object?> json) {
    var version = json['version']! as int;
    if (version != manifestVersion) {
      throw FormatException(
        'Unsupported flutterware manifest version $version '
        '(this build understands $manifestVersion).',
      );
    }
    var plugins = [
      for (var p in (json['plugins']! as List).cast<Map<String, Object?>>())
        PluginDeclaration.fromJson(p),
    ];

    // Checked on the way *in*, not only on the way out. `FlutterwareConfig.use`
    // refuses both of these, but a manifest does not have to have come from
    // `Flutterware.configure` — and a reservation enforced on one side only is
    // a convention, which is not what [Address.shellConfig] claims to be. The
    // failure without this is silent either way: a duplicate id resolves one
    // plugin and drops another, and an id of `config` is shadowed by the
    // shell's own screen with the plugin simply unreachable.
    var seen = <String>{};
    for (var plugin in plugins) {
      if (!seen.add(plugin.id)) {
        throw FormatException('Plugin id "${plugin.id}" is declared twice.');
      }
      if (Address.shellOwned.contains(plugin.id)) {
        throw FormatException(
          'Plugin id "${plugin.id}" is reserved for one of the shell\'s own '
          'screens.',
        );
      }
    }

    return PluginManifest(
      plugins,
      version: version,
      changes: switch (json['changes']) {
        Map<Object?, Object?> it => ChangesConfig.fromJson(
          it.cast<String, Object?>(),
        ),
        _ => null,
      },
    );
  }

  static PluginManifest parse(String source) =>
      fromJson(jsonDecode(source) as Map<String, Object?>);
}

/// The object a project's `tool/flutterware.dart` configures.
class FlutterwareConfig {
  final _plugins = <Plugin>[];

  ChangesConfig? _changes;

  /// Declares how this project's changes should be ranked. See [ChangesConfig].
  ///
  /// **Refused twice rather than merged or overwritten.** Two calls would be a
  /// config with two answers, and either resolution loses one of them silently
  /// — which is the failure mode that killed the standalone package list.
  void changes(ChangesConfig config) {
    if (_changes != null) {
      throw StateError(
        'fw.changes was called twice. Declare one ChangesConfig with every '
        'pattern in it.',
      );
    }
    _changes = config;
  }

  /// Registers a plugin. The same class may be used more than once as long as
  /// the instances have distinct ids.
  void use(Plugin plugin) {
    if (_plugins.any((p) => p.id == plugin.id)) {
      throw StateError(
        'Duplicate plugin id "${plugin.id}". Give one of them a distinct id.',
      );
    }
    // Refused rather than merely discouraged: `fw:///worktrees/<x>/config` and
    // `…/changes` are the shell's own screens, and a plugin able to take one of
    // those addresses could hide the one place that explains why this file did
    // not load.
    if (Address.shellOwned.contains(plugin.id)) {
      throw StateError(
        'Plugin id "${plugin.id}" is reserved for one of the shell\'s own '
        'screens. Give the plugin a dotted, globally unique id.',
      );
    }
    _plugins.add(plugin);
  }

  PluginManifest toManifest() => PluginManifest([
    for (var p in _plugins)
      PluginDeclaration(id: p.id, label: p.label, config: p.config),
  ], changes: _changes);
}

/// Entry point for a project's `tool/flutterware.dart`:
///
/// ```dart
/// import 'package:flutterware/plugins.dart';
///
/// void main() => Flutterware.configure((fw) {
///   fw.use(Scenarios());
///   fw.use(Previews());
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
