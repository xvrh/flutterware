import 'dart:async';

import 'package:flutter/widgets.dart';
import '../../devbar.dart';
import 'plugin.dart';

class AddDevbarVariable {
  static Widget text(
          {required String name,
          required Widget Function(BuildContext, String) builder,
          String? defaultValue,
          Key? key}) =>
      _TextWidget(
          name: name, builder: builder, defaultValue: defaultValue, key: key);

  static Widget checkbox(
          {required String name,
          required Widget Function(BuildContext, bool) builder,
          bool? defaultValue,
          Key? key}) =>
      _BoolWidget(
          name: name, builder: builder, defaultValue: defaultValue, key: key);

  static Widget slider<T extends num>({
    required String name,
    required Widget Function(BuildContext, T) builder,
    required T defaultValue,
    Key? key,
    required T min,
    required T max,
    required T step,
  }) =>
      _NumWidget<T>(
          name: name,
          builder: builder,
          defaultValue: defaultValue,
          key: key,
          min: min,
          max: max,
          step: step);

  static Widget picker<T extends Object>(
          {required String name,
          String? description,
          required Widget Function(BuildContext, T) builder,
          required Map<T, String> options,
          required T defaultValue,
          T? Function(Object)? fromJson,
          Key? key}) =>
      _PickerWidget<T>(
          name: name,
          description: description,
          builder: builder,
          options: options,
          defaultValue: defaultValue,
          fromJson: fromJson,
          key: key);

  static Widget group2<T1, T2>(
      DevbarVariableDefinition<T1> v1, DevbarVariableDefinition<T2> v2,
      {required Widget Function(BuildContext, T1, T2) builder}) {
    return _AddDevbarVariables(
      variables: [v1, v2],
      builder: (context, values) =>
          builder(context, values[0] as T1, values[1] as T2),
    );
  }

  static Widget group3<T1, T2, T3>(DevbarVariableDefinition<T1> v1,
      DevbarVariableDefinition<T2> v2, DevbarVariableDefinition<T3> v3,
      {required Widget Function(BuildContext, T1, T2, T3) builder}) {
    return _AddDevbarVariables(
      variables: [v1, v2, v3],
      builder: (context, values) =>
          builder(context, values[0] as T1, values[1] as T2, values[2] as T3),
    );
  }

  static Widget group4<T1, T2, T3, T4>(
      DevbarVariableDefinition<T1> v1,
      DevbarVariableDefinition<T2> v2,
      DevbarVariableDefinition<T3> v3,
      DevbarVariableDefinition<T4> v4,
      {required Widget Function(BuildContext, T1, T2, T3, T4) builder}) {
    return _AddDevbarVariables(
      variables: [v1, v2, v3, v4],
      builder: (context, values) => builder(context, values[0] as T1,
          values[1] as T2, values[2] as T3, values[3] as T4),
    );
  }

  static Widget group5<T1, T2, T3, T4, T5>(
      DevbarVariableDefinition<T1> v1,
      DevbarVariableDefinition<T2> v2,
      DevbarVariableDefinition<T3> v3,
      DevbarVariableDefinition<T4> v4,
      DevbarVariableDefinition<T5> v5,
      {required Widget Function(BuildContext, T1, T2, T3, T4, T5) builder}) {
    return _AddDevbarVariables(
      variables: [v1, v2, v3, v4, v5],
      builder: (context, values) => builder(context, values[0] as T1,
          values[1] as T2, values[2] as T3, values[3] as T4, values[4] as T5),
    );
  }

  static Widget group6<T1, T2, T3, T4, T5, T6>(
      DevbarVariableDefinition<T1> v1,
      DevbarVariableDefinition<T2> v2,
      DevbarVariableDefinition<T3> v3,
      DevbarVariableDefinition<T4> v4,
      DevbarVariableDefinition<T5> v5,
      DevbarVariableDefinition<T6> v6,
      {required Widget Function(BuildContext, T1, T2, T3, T4, T5, T6)
          builder}) {
    return _AddDevbarVariables(
      variables: [v1, v2, v3, v4, v5, v6],
      builder: (context, values) => builder(
          context,
          values[0] as T1,
          values[1] as T2,
          values[2] as T3,
          values[3] as T4,
          values[4] as T5,
          values[5] as T6),
    );
  }
}

class _PickerWidget<T> extends StatefulWidget {
  final String name;
  final String? description;
  final Widget Function(BuildContext, T) builder;
  final Map<T, String> options;
  final T defaultValue;
  final T? Function(Object)? fromJson;

  _PickerWidget({
    required this.name,
    required this.description,
    required this.builder,
    required this.options,
    required this.defaultValue,
    this.fromJson,
    super.key,
  });

  @override
  __PickerWidgetState<T> createState() => __PickerWidgetState<T>();
}

class __PickerWidgetState<T> extends State<_PickerWidget<T>> {
  late DevbarVariable<T> _variable;

  @override
  void initState() {
    super.initState();

    var devbar = DevbarState.of(context);
    _variable = devbar.variables.picker(widget.name,
        defaultValue: widget.defaultValue,
        options: widget.options,
        fromJson: widget.fromJson);
  }

  @override
  void dispose() {
    _variable.remove();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<T>(
      stream: _variable.value,
      initialData: _variable.currentValue,
      builder: (context, snapshot) {
        return widget.builder(context, snapshot.requireData);
      },
    );
  }
}

class _TextWidget extends StatefulWidget {
  final String name;
  final String? defaultValue;
  final Widget Function(BuildContext, String) builder;

  const _TextWidget({
    super.key,
    required this.name,
    required this.builder,
    this.defaultValue,
  });

  @override
  State<_TextWidget> createState() => __TextWidgetState();
}

class __TextWidgetState extends State<_TextWidget> {
  late DevbarVariable<String> _variable;

  @override
  void initState() {
    super.initState();

    var devbar = DevbarState.of(context);
    _variable = devbar.variables
        .text(widget.name, defaultValue: widget.defaultValue ?? '');
  }

  @override
  void dispose() {
    _variable.remove();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<String>(
      stream: _variable.value,
      initialData: _variable.currentValue,
      builder: (context, snapshot) {
        return widget.builder(context, snapshot.requireData);
      },
    );
  }
}

class _BoolWidget extends StatefulWidget {
  final String name;
  final bool? defaultValue;
  final Widget Function(BuildContext, bool) builder;

  const _BoolWidget(
      {super.key,
      required this.name,
      this.defaultValue,
      required this.builder});

  @override
  State<_BoolWidget> createState() => __BoolWidgetState();
}

class __BoolWidgetState extends State<_BoolWidget> {
  late DevbarVariable<bool> _variable;

  @override
  void initState() {
    super.initState();

    var devbar = DevbarState.of(context);
    _variable = devbar.variables
        .checkbox(widget.name, defaultValue: widget.defaultValue ?? false);
  }

  @override
  void dispose() {
    _variable.remove();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<bool>(
      stream: _variable.value,
      initialData: _variable.currentValue,
      builder: (context, snapshot) {
        return widget.builder(context, snapshot.requireData);
      },
    );
  }
}

class _NumWidget<T extends num> extends StatefulWidget {
  final String name;
  final T defaultValue;
  final Widget Function(BuildContext, T) builder;
  final T min;
  final T max;
  final T step;

  const _NumWidget({
    super.key,
    required this.name,
    required this.defaultValue,
    required this.builder,
    required this.min,
    required this.max,
    required this.step,
  });

  @override
  State<_NumWidget<T>> createState() => __NumWidgetState<T>();
}

class __NumWidgetState<T extends num> extends State<_NumWidget<T>> {
  late DevbarVariable<T> _variable;

  @override
  void initState() {
    super.initState();

    var devbar = DevbarState.of(context);
    _variable = devbar.variables.slider<T>(widget.name,
        defaultValue: widget.defaultValue,
        min: widget.min,
        max: widget.max,
        step: widget.step);
  }

  @override
  void dispose() {
    _variable.remove();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<T>(
      stream: _variable.value,
      initialData: _variable.currentValue,
      builder: (context, snapshot) {
        return widget.builder(context, snapshot.requireData);
      },
    );
  }
}

typedef DevbarVariableCreator = DevbarVariable Function(
    VariablesPlugin, DevbarVariableDefinition);

class _AddDevbarVariables extends StatefulWidget {
  final List<DevbarVariableDefinition> variables;
  final Widget Function(BuildContext, List) builder;

  _AddDevbarVariables({
    required this.variables,
    required this.builder,
  });
  @override
  State<_AddDevbarVariables> createState() => _AddDevbarVariablesState();
}

class _AddDevbarVariablesState extends State<_AddDevbarVariables> {
  final _variables = <DevbarVariable>[];
  final _streamController = StreamController<List>.broadcast();

  @override
  void initState() {
    super.initState();

    var devbar = DevbarState.of(context);
    for (var definition in widget.variables) {
      var variable = definition.addVariable(devbar.variables);
      _variables.add(variable);

      variable.value.listen((e) {
        _streamController.add(_currentValues);
      });
    }
  }

  List get _currentValues => _variables.map((d) => d.currentValue).toList();

  @override
  void dispose() {
    for (var variable in _variables) {
      variable.remove();
    }
    _streamController.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List>(
      stream: _streamController.stream,
      initialData: _currentValues,
      builder: (context, snapshot) {
        var values = snapshot.requireData;
        return widget.builder(context, values);
      },
    );
  }
}
