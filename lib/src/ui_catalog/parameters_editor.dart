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
    return switch (parameter) {
      StringParameter() => _StringEditor(parameter),
      BoolParameter() => _BoolEditor(parameter),
      NumParameter<num>() => _NumEditor(parameter),
      PickerParameter() => _PickerEditor(parameter),
      DateTimeParameter() => _DateTimeEditor(parameter),
    };
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

class _DateTimeEditor extends StatelessWidget {
  final DateTimeParameter parameter;

  const _DateTimeEditor(this.parameter);

  @override
  Widget build(BuildContext context) {
    var value = parameter.requiredValue;

    String pad(int value) => '$value'.padLeft(2, '0');

    String formatted;
    if (value == null) {
      formatted = '<null>';
    } else {
      formatted = '${value.year}-${pad(value.month)}-${pad(value.day)}';
      if (!parameter.dateOnly) {
        formatted += ' ${pad(value.hour)}:${pad(value.minute)}';
      }
    }

    return Row(
      children: [
        TextButton(
          onPressed: () async {
            var previousValue = value;
            var pickedDate = await showDatePicker(
                context: context,
                firstDate: DateTime(0),
                lastDate: DateTime(2100),
                initialDate: value);
            if (pickedDate != null) {
              var pickedTime = TimeOfDay(hour: 0, minute: 0);
              if (!parameter.dateOnly && context.mounted) {
                pickedTime = await showTimePicker(
                        context: context,
                        initialTime: value != null
                            ? TimeOfDay(hour: value.hour, minute: value.minute)
                            : pickedTime) ??
                    pickedTime;
              }
              var newValue = parameter.value = pickedDate.copyWith(
                  hour: pickedTime.hour, minute: pickedTime.minute);

              if (previousValue != null && previousValue.isUtc) {
                switchUtc(true, newValue);
              }
            }
          },
          child: Text(formatted),
        ),
        if (parameter.isNullable && value != null)
          Padding(
            padding: const EdgeInsets.only(left: 10),
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(minimumSize: Size.zero),
              onPressed: () {
                parameter.value = null;
              },
              child: Text('Clear'),
            ),
          ),
        if (value != null)
          InkWell(
            onTap: () {
              switchUtc(!value.isUtc, value);
            },
            child: Row(
              children: [
                Checkbox(
                  value: value.isUtc,
                  onChanged: (v) => switchUtc(v!, value),
                ),
                Text('utc'),
              ],
            ),
          ),
      ],
    );
  }

  void switchUtc(bool isUtc, DateTime value) {
    parameter.value = isUtc
        ? DateTime.utc(
            value.year,
            value.month,
            value.day,
            value.hour,
            value.minute,
          )
        : DateTime(
            value.year,
            value.month,
            value.day,
            value.hour,
            value.minute,
          );
  }
}
