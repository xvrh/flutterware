/// Something a plugin can do, offered identically to a button, `fw run`, and
/// an agent.
///
/// The callback lives with the plugin's runtime; this is only the description,
/// so it can be listed without running any plugin code.
class PluginAction {
  const PluginAction(
    this.id,
    this.label, {
    this.description,
    this.danger = false,
    this.confirm = false,
  });

  /// Stable within a plugin — what `fw` and an agent name to invoke it.
  final String id;

  final String label;
  final String? description;

  /// Destroys data. Renderers should make it visually distinct.
  final bool danger;

  /// The GUI asks before running it.
  final bool confirm;

  Map<String, Object?> toJson() => {
    'id': id,
    'label': label,
    if (description != null) 'description': description,
    if (danger) 'danger': true,
    if (confirm) 'confirm': true,
  };

  static PluginAction fromJson(Map<String, Object?> json) => PluginAction(
    json['id']! as String,
    json['label']! as String,
    description: json['description'] as String?,
    danger: json['danger'] == true,
    confirm: json['confirm'] == true,
  );
}
