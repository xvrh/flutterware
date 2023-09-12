import 'dart:core' as core;
import 'dart:core';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';

class Parameters {
  String string(String name, String defaultValue) {
    return defaultValue;
  }

  core.num num(String name, core.num defaultValue,
      {core.num? min, core.num? max}) {
    return defaultValue;
  }

  core.int int(String name, core.int defaultValue,
      {core.int? min, core.int? max}) {
    return defaultValue;
  }

  core.double double(String name, core.double defaultValue,
      {core.double? min, core.double? max}) {
    return defaultValue;
  }

  core.bool bool(String name, core.bool defaultValue) {
    return defaultValue;
  }

  T picker<T>(String name, Map<String, T> values, T defaultValue) {
    return defaultValue;
  }
}

class EditableParameters implements Parameters {
  final void Function() onRefresh;
  final void Function() onAdded;
  final parameters = <String, Parameter>{};

  EditableParameters({required this.onRefresh, required this.onAdded});

  T _addParameter<T extends Parameter>(String name, T Function() putIfAbsent) {
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
  core.num num(String name, core.num defaultValue,
      {core.num? min, core.num? max}) {
    var parameter = _addParameter(name, () => NumParameter<core.num>(0))
      ..defaultValue = defaultValue
      ..min = min
      ..max = max;

    return parameter.requiredValue;
  }

  @override
  core.int int(String name, core.int defaultValue,
      {core.int? min, core.int? max}) {
    var parameter = _addParameter(name, () => NumParameter<core.int>(0))
      ..defaultValue = defaultValue
      ..min = min
      ..max = max;

    return parameter.requiredValue;
  }

  @override
  core.double double(String name, core.double defaultValue,
      {core.double? min, core.double? max}) {
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
  T picker<T>(String name, Map<String, T> options, T defaultValue) {
    var parameter =
        _addParameter(name, () => PickerParameter<T>(options: options))
          ..defaultValue = defaultValue
          ..options = options;

    return parameter.requiredValue;
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

class PickerParameter<T> extends Parameter<T> {
  Map<String, T> options;

  PickerParameter({required this.options}) : super(options.values.first);
}
