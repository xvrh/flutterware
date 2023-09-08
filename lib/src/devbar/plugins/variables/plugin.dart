import 'dart:async';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutterware/src/devbar/devbar.dart';

import '../../../utils/value_stream.dart';
import 'file_store.dart';
import 'store.dart';
import 'ui.dart';

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
    var variable = DevbarVariable<bool>(this, key,
        defaultValue: defaultValue, description: description);

    _variables.add([..._variables.value, variable]);

    return variable;
  }

  DevbarVariable<String> text(String key,
      {String? description, String defaultValue = ''}) {
    var variable = DevbarVariable<String>(this, key,
        defaultValue: defaultValue, description: description);

    _variables.add([..._variables.value, variable]);

    return variable;
  }

  DevbarVariable<T> picker<T>(
    String key, {
    String? description,
    required T defaultValue,
    required Map<T, String> options,
    T? Function(Object)? fromJson,
  }) {
    var variable = DevbarPickerVariable<T>(this, key,
        defaultValue: defaultValue,
        description: description,
        fromJson: fromJson,
        options: options);

    _variables.add([..._variables.value, variable]);

    return variable;
  }

  void remove(DevbarVariable variable) {
    variable._value.dispose();
    _variables.add(_variables.value.whereNot((s) => s == variable).toList());
  }

  Stream<List<DevbarVariable>> get variables => _variables.stream;
  List<DevbarVariable> get currentVariables => _variables.value;

  void _storeValue(DevbarVariable devbarVariable, Object? editorValue) {
    store[devbarVariable.key] = editorValue;
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
  final String key;
  final String? description;
  final T defaultValue;
  final T? Function(Object)? fromJson;

  DevbarVariable(
    this.service,
    this.key, {
    required this.defaultValue,
    required this.description,
    this.fromJson,
  }) {
    _value = ValueStream<T>(_computedValue);
  }

  T? get storeValue {
    var value = service.store[key];
    if (value is T) {
      return value;
    } else if (fromJson case var fromJson? when value != null) {
      try {
        return fromJson(value);
      } catch (e) {
        print('Fail to read value for $key: $e');
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
    var value = service.overrides[key];
    if (value == null) return null;
    if (value is! T) {
      throw Exception('Devbar initial value for $key is not of type $T');
    }
    return value;
  }

  T get _computedValue => storeValue ?? overrideValue ?? defaultValue;

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
}

class DevbarPickerVariable<T> extends DevbarVariable<T> {
  final Map<T, String> options;

  DevbarPickerVariable(
    super.service,
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
