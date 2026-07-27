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
    this.parameters = const [],
  });

  /// Stable within a plugin — what `fw` and an agent name to invoke it.
  final String id;

  final String label;
  final String? description;

  /// Destroys data. Renderers should make it visually distinct.
  final bool danger;

  /// The GUI asks before running it.
  final bool confirm;

  /// What the action needs to be told, if anything.
  ///
  /// An action without parameters is a button. With them it is still **one**
  /// action — a form to the GUI, flags to `fw`, an argument map to an agent —
  /// rather than one action per possible target, which is what encoding the
  /// argument into [id] degenerates into once the targets number in the
  /// hundreds.
  final List<ActionParameter> parameters;

  Map<String, Object?> toJson() => {
    'id': id,
    'label': label,
    if (description != null) 'description': description,
    if (danger) 'danger': true,
    if (confirm) 'confirm': true,
    if (parameters.isNotEmpty)
      'parameters': [for (var p in parameters) p.toJson()],
  };

  static PluginAction fromJson(Map<String, Object?> json) => PluginAction(
    json['id']! as String,
    json['label']! as String,
    description: json['description'] as String?,
    danger: json['danger'] == true,
    confirm: json['confirm'] == true,
    parameters: [
      for (var p in (json['parameters'] as List? ?? const []))
        ActionParameter.fromJson((p as Map).cast<String, Object?>()),
    ],
  );
}

/// What a parameter accepts — the smallest vocabulary that lets a renderer
/// build an input and an agent know what is legal.
enum ActionParameterKind {
  string,
  boolean,
  integer,

  /// One of the parameter's options.
  choice;

  static ActionParameterKind byName(String name) =>
      values.firstWhere((v) => v.name == name, orElse: () => string);
}

/// One argument of a [PluginAction].
class ActionParameter {
  const ActionParameter(
    this.id,
    this.label, {
    this.kind = ActionParameterKind.string,
    this.required = true,
    this.description,
    this.defaultValue,
    this.options = const [],
    this.optionsFrom,
  });

  /// Stable within the action — the key in the argument map, and the flag name
  /// `fw` exposes.
  final String id;

  final String label;
  final ActionParameterKind kind;
  final bool required;
  final String? description;

  /// Used when the caller omits the argument. Always in string form; the
  /// plugin parses it according to [kind].
  final String? defaultValue;

  /// The legal values when [kind] is [ActionParameterKind.choice] and the set
  /// is small enough to spell out.
  final List<ActionOption> options;

  /// Where the legal values live when there are too many to inline, or they
  /// change as the plugin works — a path into the report, such as
  /// `children` or `view`.
  ///
  /// This is what keeps a 300-entry catalog from serialising its entry list a
  /// second time: the values are already in the report, and this says where.
  final String? optionsFrom;

  Map<String, Object?> toJson() => {
    'id': id,
    'label': label,
    'kind': kind.name,
    if (!required) 'required': false,
    if (description != null) 'description': description,
    if (defaultValue != null) 'default': defaultValue,
    if (options.isNotEmpty) 'options': [for (var o in options) o.toJson()],
    if (optionsFrom != null) 'optionsFrom': optionsFrom,
  };

  static ActionParameter fromJson(Map<String, Object?> json) => ActionParameter(
    json['id']! as String,
    json['label']! as String,
    kind: ActionParameterKind.byName(json['kind'] as String? ?? 'string'),
    required: json['required'] != false,
    description: json['description'] as String?,
    defaultValue: json['default'] as String?,
    options: [
      for (var o in (json['options'] as List? ?? const []))
        ActionOption.fromJson((o as Map).cast<String, Object?>()),
    ],
    optionsFrom: json['optionsFrom'] as String?,
  );
}

/// One legal value of a [ActionParameterKind.choice] parameter.
class ActionOption {
  const ActionOption(this.value, {this.label});

  final String value;

  /// What a human sees; [value] when absent.
  final String? label;

  Map<String, Object?> toJson() => {
    'value': value,
    if (label != null) 'label': label,
  };

  static ActionOption fromJson(Map<String, Object?> json) =>
      ActionOption(json['value']! as String, label: json['label'] as String?);
}
