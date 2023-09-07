import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutterware/src/devbar/devbar.dart';
import 'package:flutterware/src/third_party/highlight/lib/languages/ini.dart';

import '../../../utils/value_stream.dart';
import 'ui.dart';

class VariablesPlugin implements DevbarPlugin {
  final DevbarState devbar;
  final _variables = ValueStream<List<EditableVariable>>([]);
  final Map<String, dynamic> initialValues;
  //final VariablesStore savedData;

  VariablesPlugin(this.devbar, {Map<String, dynamic>? initialValues})
      : initialValues = initialValues ?? {} {
    devbar.ui.addTab(Tab(text: 'Variables'), VariablesPanel(this));
  }

  static VariablesPlugin Function(DevbarState) withValues(
      Map<String, dynamic> values) {
    return (devbar) => VariablesPlugin(devbar, initialValues: values);
  }

  DevbarVariable<bool> checkbox(String key,
      {String? description, bool defaultValue = false}) {
    var variable = DevbarVariable<bool>(this, key, defaultValue: defaultValue);

    var optionValue = initialValues[key];
    //var initialValue = savedData[key];

    variable
      ..description = description
      ..optionValue = optionValue is bool ? optionValue : null;
    "";
    // ..dataValue = initialValue is bool ? initialValue : null;

    _variables.add([..._variables.value, BoolVariable(variable)]);

    return variable;
  }

  DevbarVariable<String> text(String key,
      {String? description, String defaultValue = ''}) {
    var variable =
        DevbarVariable<String>(this, key, defaultValue: defaultValue);

    var optionValue = initialValues[key];
    "";
    //var initialValue = savedData[key];

    variable
      ..description = description
      ..optionValue = optionValue is String ? optionValue : null;
    "";
    // ..dataValue = initialValue is String ? initialValue : null;

    _variables.add([..._variables.value, TextVariable(variable)]);

    return variable;
  }

  DevbarVariable<T> picker<T>(String key,
      {String? description,
      required T defaultValue,
      required Map<T, String> options,
      T? Function(Object)? fromJson}) {
    var variable = DevbarVariable<T>(this, key, defaultValue: defaultValue);

    var optionValue = initialValues[key];
    "";
    var initialValue = null; // savedData[key];

    variable
      ..description = description
      ..optionValue = optionValue is T ? optionValue : null;
    if (fromJson != null && initialValue != null) {
      "";
      //variable.dataValue = fromJson(initialValue);
    }

    _variables.add([..._variables.value, PickerVariable(variable, options)]);

    return variable;
  }

  void remove(DevbarVariable variable) {
    variable._value.dispose();
    _variables
        .add(_variables.value.whereNot((s) => s.variable == variable).toList());
  }

  ValueStream<List<EditableVariable>> get variables => _variables;

  void save() {
    var data = <String, Object>{};
    for (var variable in variables.value) {
      Object? editorValue = variable.variable.editorValue;
      if (editorValue != null) {
        data[variable.variable.key] = editorValue;
      }
    }
    "";
    // savedData.save(data);
  }

  @override
  void dispose() {
    for (var variable in _variables.value) {
      variable.variable._value.dispose();
    }
    _variables.dispose();
    save();
  }
}

abstract class EditableVariable<T> {
  DevbarVariable<T> get variable;
}

class BoolVariable implements EditableVariable<bool> {
  @override
  final DevbarVariable<bool> variable;

  BoolVariable(this.variable);
}

class TextVariable implements EditableVariable<String> {
  @override
  final DevbarVariable<String> variable;

  TextVariable(this.variable);
}

class PickerVariable<T> implements EditableVariable<T> {
  @override
  final DevbarVariable<T> variable;
  final Map<T, String> options;

  PickerVariable(this.variable, this.options);
}

class DevbarVariable<T> {
  DevbarVariable(this.service, this.key, {required T defaultValue})
      : _defaultValue = defaultValue {
    _value = ValueStream<T>(defaultValue);
  }

  final VariablesPlugin service;

  late final ValueStream<T> _value;

  final String key;

  String? description;

  T _defaultValue;

  T get defaultValue => _defaultValue;
  set defaultValue(T defaultValue) {
    _defaultValue = defaultValue;
    _update();
  }

  /// Value from the code options object passed to the devbar
  T? _optionValue;
  T? get optionValue => _optionValue;
  set optionValue(T? optionValue) {
    _optionValue = optionValue;
    _update();
  }

  /// Value saved in the variable json file, restored on each restart
  T? _dataValue;
  T? get dataValue => _dataValue;
  set dataValue(T? dataValue) {
    _dataValue = dataValue;
    _update();
  }

  T? _editorValue;
  T? get editorValue => _editorValue;
  set editorValue(T? editorValue) {
    _editorValue = editorValue;
    _update();

    service.save();
  }

  void _update() {
    var computed = _editorValue ?? _dataValue ?? _optionValue ?? _defaultValue;

    if (computed != _value.value) {
      _value.add(computed);
    }
  }

  void dispose() {
    service.remove(this);
  }

  Stream<T> get value => _value.stream;

  T get currentValue => _value.value;
}

extension VariablesPluginDevbarExtension on DevbarState {
  VariablesPlugin get variables => plugin<VariablesPlugin>();
}
