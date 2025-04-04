import 'dart:async';
import 'dart:io';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import '../../../utils/value_stream.dart';
import '../../devbar.dart';
import 'file_store.dart';
import 'store.dart';
import 'ui.dart';

/// A plugin for the Devbar to manage variables.
class VariablesPlugin implements DevbarPlugin {
  final DevbarState devbar;
  final _variables = ValueStream<List<DevbarVariable>>([]);
  final Map<String, dynamic> overrides;
  final VariablesStore store;

  VariablesPlugin._(this.devbar,
      {Map<String, dynamic>? overrides, VariablesStore? store, String? title})
      : overrides = overrides ?? {},
        store = store ?? InMemoryVariablesStore() {
    devbar.ui.addTab(Tab(text: title ?? 'Settings'), VariablesPanel(this));
  }

  static Future<VariablesPlugin> Function(DevbarState) init({
    Map<String, dynamic>? values,
    VariablesStore? store,
    Future<VariablesStore> Function()? storeFactory,
    FutureOr<String> Function()? filePath,
    String? title,
  }) {
    return (devbar) async {
      if (store == null) {
        if (storeFactory != null) {
          store = await storeFactory();
        } else if (filePath != null) {
          store = await FileVariableStore.load(File(await filePath()));
        }
      }
      return VariablesPlugin._(devbar,
          overrides: values, store: store, title: title);
    };
  }

  DevbarVariable<bool> checkbox(String key,
      {String? description, bool defaultValue = false}) {
    return add(DevbarVariableDefinition<bool>(key,
        defaultValue: defaultValue, description: description));
  }

  DevbarVariable<String> text(String key,
      {String? description, String defaultValue = ''}) {
    return add(DevbarVariableDefinition(key,
        defaultValue: defaultValue, description: description));
  }

  DevbarVariable<T> slider<T extends num>(String key,
      {String? description,
      required T defaultValue,
      required T min,
      required T max,
      required T step}) {
    return add(DevbarSliderVariableDefinition<T>(
      key,
      defaultValue: defaultValue,
      description: description,
      min: min,
      max: max,
      step: step,
    ));
  }

  DevbarVariable<T> picker<T>(
    String key, {
    String? description,
    required T defaultValue,
    required Map<T, String> options,
    T? Function(Object)? fromJson,
  }) {
    return add(DevbarPickerVariableDefinition<T>(key,
        defaultValue: defaultValue,
        description: description,
        fromJson: fromJson,
        options: options));
  }

  DevbarVariable<T> add<T>(DevbarVariableDefinition<T> definition) {
    var variable = DevbarVariable<T>(this, definition);
    _variables.add([..._variables.value, variable]);
    return variable;
  }

  void addVariable<T>(DevbarVariable<T> variable) {
    _variables.add([..._variables.value, variable]);
  }

  void remove(DevbarVariable variable) {
    variable._value.dispose();
    _variables.add(_variables.value.whereNot((s) => s == variable).toList());
  }

  Stream<List<DevbarVariable>> get variables => _variables.stream;
  List<DevbarVariable> get currentVariables => _variables.value;

  void _storeValue(DevbarVariable devbarVariable, Object? editorValue) {
    store[devbarVariable.definition.key] = editorValue;
  }

  @override
  void dispose() {
    for (var variable in _variables.value) {
      variable._value.dispose();
    }
    _variables.dispose();
  }
}

class DevbarVariable<T> {
  final VariablesPlugin service;
  late final ValueStream<T> _value;
  final DevbarVariableDefinition<T> definition;

  DevbarVariable(this.service, this.definition) {
    assert(T != dynamic);
    _value = ValueStream<T>(_computedValue);
  }

  String get key => definition.key;

  String? get description => definition.description;

  T get defaultValue => definition.defaultValue;

  T? get storeValue {
    var value = service.store[definition.key];
    if (value is T) {
      return value;
    } else if (definition.fromJson case var fromJson? when value != null) {
      try {
        return fromJson(value);
      } catch (e) {
        print('Fail to read value for ${definition.key}: $e');
        return null;
      }
    }
    return null;
  }

  set storeValue(T? value) {
    service._storeValue(this, value);
    _update();
  }

  T? get overrideValue {
    var value = service.overrides[definition.key];
    if (value == null) return null;
    if (value is! T) {
      throw Exception(
          'Devbar initial value for ${definition.key} is not of type $T');
    }
    return value;
  }

  T get _computedValue =>
      storeValue ?? overrideValue ?? definition.defaultValue;

  void _update() {
    var computed = _computedValue;

    if (computed != _value.value) {
      _value.add(computed);
    }
  }

  void remove() {
    service.remove(this);
  }

  Stream<T> get value => _value.stream;

  T get currentValue => _value.value;

  static DevbarVariableDefinition<T> picker<T>(
    String key, {
    String? description,
    required T defaultValue,
    required Map<T, String> options,
    T? Function(Object)? fromJson,
  }) {
    return DevbarPickerVariableDefinition<T>(key,
        defaultValue: defaultValue, description: description, options: options);
  }

  static DevbarVariableDefinition<String> text(String key,
      {String? description, String defaultValue = ''}) {
    return DevbarVariableDefinition<String>(key,
        defaultValue: defaultValue, description: description);
  }

  static DevbarVariableDefinition<bool> checkbox(String key,
      {String? description, bool defaultValue = false}) {
    return DevbarVariableDefinition<bool>(key,
        defaultValue: defaultValue, description: description);
  }

  static DevbarVariableDefinition<T> slider<T extends num>(String key,
      {String? description,
      required T defaultValue,
      required T min,
      required T max,
      required T step}) {
    return DevbarSliderVariableDefinition<T>(key,
        defaultValue: defaultValue,
        description: description,
        min: min,
        max: max,
        step: step);
  }
}

class DevbarVariableDefinition<T> {
  final String key;
  final String? description;
  final T defaultValue;
  final T? Function(Object)? fromJson;

  DevbarVariableDefinition(this.key,
      {required this.description, required this.defaultValue, this.fromJson});

  DevbarVariable<T> addVariable(VariablesPlugin plugin) => plugin.add<T>(this);
}

class DevbarSliderVariableDefinition<T extends num>
    extends DevbarVariableDefinition<T> {
  final T min;
  final T max;
  final T step;

  DevbarSliderVariableDefinition(
    super.key, {
    required super.defaultValue,
    required super.description,
    super.fromJson,
    required this.min,
    required this.max,
    required this.step,
  });

  bool get isInt => T == int;
}

class DevbarPickerVariableDefinition<T> extends DevbarVariableDefinition<T> {
  final Map<T, String> options;

  DevbarPickerVariableDefinition(
    super.key, {
    required super.defaultValue,
    required super.description,
    super.fromJson,
    required this.options,
  });
}

extension VariablesPluginDevbarExtension on DevbarState {
  VariablesPlugin get variables => plugin<VariablesPlugin>();
}
