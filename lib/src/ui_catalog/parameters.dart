import 'dart:core' as core;
import 'dart:core';

import 'package:flutter/widgets.dart';

class Parameters {
  String string(String name, String defaultValue) {
    return defaultValue;
  }

  core.num num(
    String name,
    core.num defaultValue, {
    core.num? min,
    core.num? max,
  }) {
    return defaultValue;
  }

  core.int int(
    String name,
    core.int defaultValue, {
    core.int? min,
    core.int? max,
  }) {
    return defaultValue;
  }

  core.double double(
    String name,
    core.double defaultValue, {
    core.double? min,
    core.double? max,
  }) {
    return defaultValue;
  }

  core.bool bool(String name, core.bool defaultValue) {
    return defaultValue;
  }

  T picker<T>(
    String name,
    Map<String, T> values,
    T defaultValue, {
    Color Function(T value)? swatch,
    IconData Function(T value)? icon,
  }) {
    return defaultValue;
  }

  DateTime? nullableDateTime(
    String name,
    DateTime? defaultValue, {
    core.bool dateOnly = false,
  }) {
    return defaultValue;
  }

  DateTime dateTime(
    String name,
    DateTime defaultValue, {
    core.bool dateOnly = false,
  }) {
    return defaultValue;
  }

  void button(String name, String text, VoidCallback onTap) {}
}

class EditableParameters implements Parameters {
  final void Function() onRefresh;
  final void Function() onAdded;
  final parameters = <String, Parameter>{};

  EditableParameters({required this.onRefresh, required this.onAdded});

  /// The names declared since [beginPass], or null when no pass is open.
  ///
  /// A knob exists because a build asked for it, which makes a build the only
  /// thing that can retire one: a knob renamed or deleted in the source is
  /// simply never asked for again, and without a pass to notice that, it
  /// lingers in [parameters] as a control that reads nothing.
  Set<String>? _pass;

  /// Starts recording which knobs a build declares.
  ///
  /// Between this and [endPass], [parameters] is the *union* of the last build
  /// and this one — a knob is only known to be gone once the pass closes.
  void beginPass() => _pass = <String>{};

  /// Drops every knob the pass did not declare, and answers how many went.
  core.int endPass() {
    var declared = _pass;
    _pass = null;
    if (declared == null) return 0;
    var retired = [
      for (var name in parameters.keys)
        if (!declared.contains(name)) name,
    ];
    for (var name in retired) {
      var parameter = parameters.remove(name);
      parameter?.removeListener(_onRefresh);
      parameter?.dispose();
    }
    // Re-ordered to match the build, not the order things were first seen: a
    // knob belongs in the panel where the demo asks for it, so one inserted
    // halfway through a build appears halfway down rather than at the bottom.
    // Without this a rename reads as a knob that moved as well as changed.
    var ordered = {for (var name in declared) name: ?parameters[name]};
    parameters
      ..clear()
      ..addAll(ordered);
    return retired.length;
  }

  T _addParameter<T extends Parameter>(String name, T Function() putIfAbsent) {
    _pass?.add(name);
    var existingParameter = parameters[name];
    T parameter;
    if (existingParameter is T) {
      parameter = existingParameter;
    } else {
      if (existingParameter != null) {
        existingParameter.dispose();
        existingParameter = null;
      }

      parameter = putIfAbsent();
      parameter.addListener(_onRefresh);
      parameters[name] = parameter;

      onAdded();
    }
    return parameter;
  }

  void _onRefresh() {
    onRefresh();
  }

  @override
  String string(String name, String defaultValue) {
    var parameter = _addParameter(name, () => StringParameter())
      ..defaultValue = defaultValue;

    return parameter.requiredValue;
  }

  @override
  core.num num(
    String name,
    core.num defaultValue, {
    core.num? min,
    core.num? max,
  }) {
    var parameter = _addParameter(name, () => NumParameter<core.num>(0))
      ..defaultValue = defaultValue
      ..min = min
      ..max = max;

    return parameter.requiredValue;
  }

  @override
  core.int int(
    String name,
    core.int defaultValue, {
    core.int? min,
    core.int? max,
  }) {
    var parameter = _addParameter(name, () => NumParameter<core.int>(0))
      ..defaultValue = defaultValue
      ..min = min
      ..max = max;

    return parameter.requiredValue;
  }

  @override
  core.double double(
    String name,
    core.double defaultValue, {
    core.double? min,
    core.double? max,
  }) {
    var parameter = _addParameter(name, () => NumParameter<core.double>(0))
      ..defaultValue = defaultValue
      ..min = min
      ..max = max;

    return parameter.requiredValue;
  }

  @override
  core.bool bool(String name, core.bool defaultValue) {
    var parameter = _addParameter(name, () => BoolParameter())
      ..defaultValue = defaultValue;
    return parameter.requiredValue;
  }

  @override
  T picker<T>(
    String name,
    Map<String, T> options,
    T defaultValue, {
    Color Function(T value)? swatch,
    IconData Function(T value)? icon,
  }) {
    var parameter =
        _addParameter(name, () => PickerParameter<T>(options: options))
          ..defaultValue = defaultValue
          ..options = options
          ..swatch = swatch
          ..icon = icon;

    return parameter.requiredValue;
  }

  @override
  DateTime? nullableDateTime(
    String name,
    DateTime? defaultValue, {
    core.bool dateOnly = false,
  }) {
    var parameter = _addParameter(
      name,
      () => DateTimeParameter(isNullable: true, dateOnly: dateOnly),
    )..defaultValue = defaultValue;
    return parameter.requiredValue;
  }

  @override
  DateTime dateTime(
    String name,
    DateTime defaultValue, {
    core.bool dateOnly = false,
  }) {
    var parameter = _addParameter(
      name,
      () => DateTimeParameter(isNullable: false, dateOnly: dateOnly),
    )..defaultValue = defaultValue;
    return parameter.requiredValue!;
  }

  @override
  void button(String name, String text, VoidCallback onPressed) {
    _addParameter(
        name,
        () => ActionButtonParameter(text: text, onPressed: onPressed),
      )
      ..text = text
      ..onPressed = onPressed;
  }

  void dispose() {
    for (var parameter in parameters.values) {
      parameter.dispose();
    }
  }
}

sealed class Parameter<T> with ChangeNotifier {
  Parameter(this.defaultValue);

  T defaultValue;

  T? _value;

  T? get value => _value;
  set value(T? value) {
    _value = value;
    notifyListeners();
  }

  T get requiredValue => _value ?? defaultValue;
}

class StringParameter extends Parameter<String> {
  StringParameter() : super('');
}

class BoolParameter extends Parameter<bool> {
  BoolParameter() : super(false);
}

class NumParameter<T extends num> extends Parameter<T> {
  T? min, max;

  NumParameter(super.defaultValue);

  bool get isInt => T == int;
}

/// How a [PickerParameter] renders in the toolbar.
enum PickerStyle {
  /// A compact button that opens a modal dialog listing the options. Best when
  /// there are many options or little horizontal room for the list.
  dialog,

  /// An inline segmented control — every option visible at once. Best for two
  /// or three options.
  segmented,

  /// A compact chip that opens an anchored popover menu under it. Less invasive
  /// than [dialog]; best for a medium handful of options.
  popover,
}

class PickerParameter<T> extends Parameter<T> {
  Map<String, T> options;
  Color Function(T value)? swatch;
  IconData Function(T value)? icon;

  /// How this picker renders in the toolbar.
  PickerStyle style;

  PickerParameter({
    required this.options,
    this.swatch,
    this.icon,
    this.style = PickerStyle.popover,
  }) : super(options.values.first);

  // Resolved here, inside the class, so the call runs with the reified [T] —
  // calling [swatch]/[icon] through the raw `PickerParameter` type would fail
  // the function cast.
  Color? swatchFor(Object? value) => swatch?.call(value as T);

  IconData? iconFor(Object? value) => icon?.call(value as T);
}

/// Renders a picker option: its [PickerParameter.swatch] colour dot or
/// [PickerParameter.icon] (if set) before the [label]. Shared by the top bar
/// and the knobs panel so a picker looks the same in both.
Widget pickerOptionWidget(
  PickerParameter parameter,
  String label,
  Object? value,
) {
  var swatch = parameter.swatchFor(value);
  var icon = parameter.iconFor(value);
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (swatch != null) ...[
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: swatch, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
      ],
      if (icon != null) ...[Icon(icon, size: 16), const SizedBox(width: 8)],
      Text(label),
    ],
  );
}

class DateTimeParameter extends Parameter<DateTime?> {
  final bool isNullable;
  final bool dateOnly;
  DateTimeParameter({required this.isNullable, required this.dateOnly})
    : super(null);
}

class ActionButtonParameter extends Parameter {
  String text;
  VoidCallback onPressed;

  ActionButtonParameter({required this.text, required this.onPressed})
    : super(null);
}
