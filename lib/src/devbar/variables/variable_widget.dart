import 'package:flutter/widgets.dart';
import '../devbar.dart';
import '../plugins/variables/plugin.dart';

class VariableWidget {
  static Widget text(
          {String? name,
          Widget Function(BuildContext, String)? builder,
          Key? key}) =>
      throw UnimplementedError(
          'Not yet implemented. Wait for variable storage.');

  static Widget picker<T>(
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
    Key? key,
  }) : super(key: key);

  @override
  __PickerWidgetState<T> createState() => __PickerWidgetState<T>();
}

class __PickerWidgetState<T> extends State<_PickerWidget<T>> {
  late DevbarVariable<T> _variable;

  @override
  void initState() {
    super.initState();

    var devbar = DevbarState.of(context);
    // _variable = devbar.variables.picker(widget.name,
    //     defaultValue: widget.defaultValue,
    //     options: widget.options,
    //     fromJson: widget.fromJson);
  }

  @override
  void dispose() {
    _variable.dispose();
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
