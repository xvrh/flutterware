/// A plugin as a project *declares* it in `tool/flutterware.dart`.
///
/// In v1 this carries identity and configuration only — nothing executable.
/// Native plugins are compiled into the GUI binary, so the config file cannot
/// add behaviour; it selects, configures and orders what is already linked in.
/// That is what lets the config be a plain `dart run` that prints a manifest
/// and exits, with no resident compiler and no config process.
///
/// The behaviour for each [id] lives GUI-side and produces a `PluginReport`.
/// When the declarative tier lands (v2), third-party plugins will supply that
/// behaviour here too; this class is the seam that stays.
abstract class Plugin {
  Plugin(this.id, {String? label}) : label = label ?? id.split('.').last;

  /// Stable and globally unique — `flutterware.tests`, `acme.deploy`. The GUI
  /// resolves its native implementation by this string.
  final String id;

  /// What the sidebar row says. Defaults to the last dotted segment of [id].
  final String label;

  /// Per-instance configuration, handed to the GUI-side implementation. Must be
  /// JSON-encodable — it crosses a process boundary.
  Map<String, Object?> get config => const {};

  Map<String, Object?> toJson() => {
    'id': id,
    'label': label,
    if (config.isNotEmpty) 'config': config,
  };

  @override
  String toString() => 'Plugin($id)';
}
