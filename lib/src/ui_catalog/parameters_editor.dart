import 'package:flutter/material.dart';
import 'parameters.dart';

class ParametersEditor extends StatelessWidget {
  final EditableParameters parameters;

  const ParametersEditor(
    this.parameters, {
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
        ),
        sliderTheme: SliderThemeData(
          showValueIndicator: ShowValueIndicator.always,
        ),
      ),
      child: ListView(
        padding: const EdgeInsets.only(bottom: 50),
        children: [
          for (var parameter in parameters.parameters.entries)
            _KnobLine(
              name: parameter.key,
              editor: ListenableBuilder(
                listenable: parameter.value,
                builder: (context, _) => _editorFor(parameter.value),
              ),
            ),
        ],
      ),
    );
  }

  Widget _editorFor(Parameter parameter) {
    if (parameter is StringParameter) {
      return _StringEditor(parameter);
    } else if (parameter is BoolParameter) {
      return _BoolEditor(parameter);
    } else if (parameter is NumParameter) {
      return _NumEditor(parameter);
    } else if (parameter is PickerParameter) {
      return _PickerEditor(parameter);
    }
    throw Exception('Unknown parameter type: ${parameter.runtimeType}');
  }
}

class _KnobLine extends StatelessWidget {
  final String name;
  final Widget editor;

  const _KnobLine({required this.name, required this.editor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade300),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 150,
            child: Text(
              name,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: editor,
            ),
          ),
        ],
      ),
    );
  }
}

class _StringEditor extends StatefulWidget {
  final StringParameter parameter;

  const _StringEditor(this.parameter);

  @override
  State<_StringEditor> createState() => _StringEditorState();
}

class _StringEditorState extends State<_StringEditor> {
  final _globalKey = GlobalKey();
  late final _textController =
      TextEditingController(text: widget.parameter.value);

  @override
  void initState() {
    super.initState();

    _textController.addListener(() {
      String? text = _textController.text;
      if (text.isEmpty) {
        text = null;
      }
      widget.parameter.value = text;
    });
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      key: _globalKey,
      controller: _textController,
      maxLines: null,
      decoration: InputDecoration(
        isDense: true,
        hintText: widget.parameter.defaultValue,
      ),
    );
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }
}

class _BoolEditor extends StatelessWidget {
  final BoolParameter parameter;

  const _BoolEditor(this.parameter);

  @override
  Widget build(BuildContext context) {
    return Checkbox(
      value: parameter.value ?? parameter.defaultValue,
      onChanged: (v) {
        parameter.value = v;
      },
    );
  }
}

class _NumEditor extends StatelessWidget {
  final NumParameter parameter;

  const _NumEditor(this.parameter);

  @override
  Widget build(BuildContext context) {
    if (parameter.min != null && parameter.max != null) {
      return Slider(
        label: parameter.requiredValue.toString(),
        value: parameter.requiredValue.toDouble(),
        min: parameter.min!.toDouble(),
        max: parameter.max!.toDouble(),
        onChanged: (v) {
          var value = parameter.isInt ? v.toInt() : v;
          parameter.value = value;
        },
      );
    } else {
      return TextFormField(
        decoration: InputDecoration(
          hintText: parameter.defaultValue.toString(),
          isDense: true,
        ),
        initialValue:
            parameter.value?.toString() ?? parameter.defaultValue.toString(),
        onChanged: (e) {
          var value = parameter.isInt ? int.tryParse(e) : double.tryParse(e);
          parameter.value = value;
        },
      );
    }
  }
}

class _PickerEditor<T> extends StatelessWidget {
  final PickerParameter parameter;

  const _PickerEditor(this.parameter, {super.key});

  @override
  Widget build(BuildContext context) {
    return DropdownButton(
      value: parameter.requiredValue,
      items: [
        for (var v in parameter.options.entries)
          DropdownMenuItem(value: v.value, child: Text(v.key))
      ],
      onChanged: (v) {
        parameter.value = v;
      },
    );
  }
}
