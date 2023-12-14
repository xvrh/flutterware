import 'package:flutter/material.dart';
import '../../utils/context_menu_region.dart';
import 'plugin.dart';

class VariablesPanel extends StatelessWidget {
  final VariablesPlugin plugin;

  const VariablesPanel(this.plugin, {super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<DevbarVariable>>(
      stream: plugin.variables,
      initialData: plugin.currentVariables,
      builder: (context, snapshot) {
        return ListView(
          children: ListTile.divideTiles(tiles: [
            for (var variable in snapshot.requireData)
              _VariableEditor(variable),
          ], context: context)
              .toList(),
        );
      },
    );
  }
}

class _VariableEditor extends StatelessWidget {
  final DevbarVariable variable;

  const _VariableEditor(this.variable, {Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ContextMenuRegion(
      contextMenuBuilder: (context, offset) {
        return AdaptiveTextSelectionToolbar.buttonItems(
          anchors: TextSelectionToolbarAnchors(
            primaryAnchor: offset,
          ),
          buttonItems: <ContextMenuButtonItem>[
            ContextMenuButtonItem(
              onPressed: () {
                ContextMenuController.removeAny();
                variable.storeValue = null;
              },
              label: 'Clear override',
            ),
          ],
        );
      },
      child: StreamBuilder(
        stream: variable.value,
        initialData: variable.currentValue,
        builder: (context, snapshot) {
          var variable = this.variable;
          if (variable is DevbarVariable<bool>) {
            return _BoolEditor(variable);
          } else if (variable is DevbarPickerVariable) {
            return _PickerEditor(variable);
          } else if (variable is DevbarVariable<String>) {
            return _TextEditor(variable);
          } else {
            return ErrorWidget('Unknown variable ${variable.runtimeType}');
          }
        },
      ),
    );
  }
}

class _BoolEditor extends StatelessWidget {
  final DevbarVariable<bool> variable;

  const _BoolEditor(this.variable, {Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      title: Text(variable.key),
      subtitle: Text(variable.description ?? ''),
      trailing: Switch.adaptive(
        value: variable.currentValue,
        onChanged: (newValue) {
          variable.storeValue = newValue;
        },
      ),
    );
  }
}

class _TextEditor extends StatelessWidget {
  final DevbarVariable<String> variable;

  const _TextEditor(this.variable, {Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      title: Text(variable.key),
      subtitle: Text(variable.description ?? ''),
      trailing: FractionallySizedBox(
        widthFactor: 0.5,
        child: TextField(
          decoration: InputDecoration(
            hintText: variable.currentValue,
            isDense: true,
          ),
          onChanged: (newValue) {
            variable.storeValue = newValue;
          },
        ),
      ),
    );
  }
}

class _PickerEditor extends StatelessWidget {
  final DevbarPickerVariable variable;

  const _PickerEditor(this.variable, {Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      title: Text(variable.key),
      subtitle: Text(variable.description ?? ''),
      trailing: FractionallySizedBox(
        widthFactor: 0.5,
        child: DropdownButton(
          isDense: true,
          value: variable.currentValue,
          onChanged: (newValue) {
            variable.storeValue = newValue;
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
