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
