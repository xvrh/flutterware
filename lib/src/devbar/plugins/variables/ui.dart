import 'package:flutter/material.dart';
import '../../../utils/value_stream.dart';
import 'plugin.dart';

class VariablesPanel extends StatelessWidget {
  final VariablesPlugin plugin;

  const VariablesPanel(this.plugin, {super.key});

  @override
  Widget build(BuildContext context) {
    return ValueStreamBuilder<List<EditableVariable>>(
      stream: plugin.variables,
      builder: (context, snapshot) {
        return ListView(
          children: [
            for (var variable in snapshot) _VariableEditor(variable),
          ],
        );
      },
    );
  }
}

class _VariableEditor extends StatelessWidget {
  final EditableVariable variable;

  const _VariableEditor(this.variable, {Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: variable.variable.value,
      initialData: variable.variable.currentValue,
      builder: (context, snapshot) {
        var variable = this.variable;
        if (variable is BoolVariable) {
          return _BoolEditor(variable);
        } else if (variable is TextVariable) {
          return _TextEditor(variable);
        } else if (variable is PickerVariable) {
          return _PickerEditor(variable);
        } else {
          return ErrorWidget('Unknown variable ${variable.runtimeType}');
        }
      },
    );
  }
}

class _BoolEditor extends StatelessWidget {
  final BoolVariable variable;

  const _BoolEditor(this.variable, {Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      title: Text(variable.variable.key),
      subtitle: Text(variable.variable.description ?? ''),
      trailing: Switch.adaptive(
        value: variable.variable.currentValue,
        onChanged: (newValue) {
          variable.variable.editorValue = newValue;
        },
      ),
    );
  }
}

class _TextEditor extends StatelessWidget {
  final TextVariable variable;

  const _TextEditor(this.variable, {Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      title: Text(variable.variable.key),
      subtitle: Text(variable.variable.description ?? ''),
      trailing: FractionallySizedBox(
        widthFactor: 0.5,
        child: TextField(
          decoration: InputDecoration(
            hintText: variable.variable.currentValue,
            isDense: true,
          ),
          onChanged: (newValue) {
            variable.variable.editorValue = newValue;
          },
        ),
      ),
    );
  }
}

class _PickerEditor extends StatelessWidget {
  final PickerVariable variable;

  const _PickerEditor(this.variable, {Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      title: Text(variable.variable.key),
      subtitle: Text(variable.variable.description ?? ''),
      trailing: FractionallySizedBox(
        widthFactor: 0.5,
        child: DropdownButton(
          isDense: true,
          value: variable.variable.currentValue,
          onChanged: (newValue) {
            variable.variable.editorValue = newValue;
          },
          isExpanded: true,
          items: [
            for (var option in variable.options.entries)
              DropdownMenuItem(value: option.key, child: Text(option.value)),
          ],
        ),
      ),
    );
  }
}
