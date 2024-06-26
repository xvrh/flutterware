import 'dart:math';
import 'package:flutter/material.dart';
import 'runtime.dart';
import 'ui/toolbar.dart';

class ToolbarParameters {
  final SerializableLocale? locale;
  final DeviceInfo device;
  final AccessibilityConfig accessibility;

  ToolbarParameters({
    required this.locale,
    required this.device,
    required this.accessibility,
  });

  bool requiresFullRun(ToolbarParameters newConfig) {
    return newConfig.locale != locale ||
        newConfig.device != device ||
        newConfig.accessibility != accessibility;
  }
}

class ToolBarScope extends StatefulWidget {
  final Widget child;
  const ToolBarScope({super.key, required this.child});

  @override
  ToolBarScopeState createState() => ToolBarScopeState();

  static ToolBarScopeState of(BuildContext context) {
    return context.findAncestorStateOfType<ToolBarScopeState>()!;
  }
}

class ToolBarScopeState extends State<ToolBarScope> {
  late ToolbarParameters parameters = ToolbarParameters(
    locale: null,
    device: DeviceInfo.iPhoneX,
    accessibility: AccessibilityConfig.defaultValue,
  );

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

class RunToolbar extends StatefulWidget {
  final List<Widget>? leadingActions;
  final List<Widget>? trailingActions;
  final Widget child;
  final ToolbarParameters initialParameters;
  final void Function(ToolbarParameters) onChanged;
  final Set<SerializableLocale>? supportedLocales;

  const RunToolbar({
    super.key,
    required this.child,
    required this.initialParameters,
    required this.onChanged,
    this.leadingActions,
    this.trailingActions,
    required this.supportedLocales,
  });

  @override
  State<RunToolbar> createState() => _RunToolbarState();
}

class _RunToolbarState extends State<RunToolbar> {
  late SerializableLocale? _language = widget.initialParameters.locale;
  late DeviceInfo _device = widget.initialParameters.device;
  late AccessibilityConfig _accessibility =
      widget.initialParameters.accessibility;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Toolbar(
          children: [
            ...?widget.leadingActions,
            ToolbarDropdown<SerializableLocale>(
              value: _language,
              hint: Text('Locale'),
              onChanged: (v) {
                setState(() {
                  _language = v;
                });
                _onChanged();
              },
              items: {
                for (var language
                    in widget.supportedLocales ?? const <SerializableLocale>[])
                  language: Text(language.displayString)
              },
            ),
            ToolbarDropdown<DeviceInfo>(
              value: _device,
              onChanged: (v) {
                setState(() {
                  _device = v;
                });
                _onChanged();
              },
              items: {
                for (var value in DeviceInfo.devices) value: Text(value.name)
              },
            ),
            ToolbarPanel(
              button: Row(
                children: [
                  Icon(
                    Icons.text_fields,
                    color: Colors.black54,
                  ),
                  const SizedBox(width: 5),
                  Text(_describeAccessibility(_accessibility))
                ],
              ),
              panel: _AccessibilityPanel(
                initialValue: _accessibility,
                onChanged: (v) {
                  setState(() {
                    _accessibility = v;
                  });
                  _onChanged();
                },
              ),
            ),
            Expanded(
              child: const SizedBox(),
            ),
            ...?widget.trailingActions,
            // User preferences?
          ],
        ),
        Expanded(
          child: widget.child,
        ),
      ],
    );
  }

  void _onChanged() {
    widget.onChanged(ToolbarParameters(
      locale: _language,
      device: _device,
      accessibility: _accessibility,
    ));
  }
}

String _describeAccessibility(AccessibilityConfig config) {
  var features = <String>[
    if (config.boldText) 'bold',
    if (config.highContrast) 'high contrast',
    if (config.invertColors) 'invert colors',
  ];
  if (config.textScale == 1.0 && features.isEmpty) return 'Default';

  var buffer = StringBuffer();
  buffer.write('Text ${(config.textScale * 100).round()}%');

  if (features.isNotEmpty) {
    buffer.write(' (${features.join(', ')})');
  }

  return '$buffer';
}

class _AccessibilityPanel extends StatefulWidget {
  final AccessibilityConfig initialValue;
  final void Function(AccessibilityConfig) onChanged;

  const _AccessibilityPanel({
    required this.initialValue,
    required this.onChanged,
  });

  @override
  State<_AccessibilityPanel> createState() => _AccessibilityPanelState();
}

class _AccessibilityPanelState extends State<_AccessibilityPanel> {
  late AccessibilityConfig _value = widget.initialValue;

  @override
  Widget build(BuildContext context) {
    return ElevatedButtonTheme(
      data: _buttonTheme(),
      child: Container(
        width: 300,
        padding: EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 40,
              child: _title(),
            ),
            _scaleEditor(),
            _boldEditor(),
            _highContrastEditor(),
            _invertColorsEditor(),
            ElevatedButton(
              onPressed: () {
                widget.onChanged(_value);
                ToolbarPanel.of(context).hideMenu();
              },
              child: Text('Apply'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _title() {
    return Row(
      children: [
        Expanded(
          child: Text(
            'Accessibility features',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
          ),
        ),
        if (_value != AccessibilityConfig.defaultValue &&
            widget.initialValue != AccessibilityConfig.defaultValue)
          TextButton(
            onPressed: () {
              setState(() {
                _value = AccessibilityConfig.defaultValue;
              });
              widget.onChanged(_value);
              ToolbarPanel.of(context).hideMenu();
            },
            child: Text(
              'Reset',
              style: const TextStyle(
                decoration: TextDecoration.underline,
                color: Colors.black87,
                fontSize: 11,
              ),
            ),
          ),
      ],
    );
  }

  Widget _scaleEditor() {
    return Row(
      children: [
        SizedBox(width: 100, child: Text('Text scale')),
        Expanded(
          child: Row(
            children: [
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _value = _value.rebuild(
                        (b) => b.textScale = max(0.1, _value.textScale - 0.1));
                  });
                },
                child: Text('-'),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3.0),
                child: Text('${(_value.textScale * 100).round()}%'),
              ),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _value = _value.rebuild(
                        (b) => b.textScale = min(3, _value.textScale + 0.1));
                  });
                },
                child: Text('+'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _boldEditor() {
    return Row(
      children: [
        SizedBox(width: 100, child: Text('Bold text')),
        Checkbox(
          value: _value.boldText,
          onChanged: (v) {
            setState(() {
              _value = _value.rebuild((b) => b.boldText = v);
            });
          },
        ),
      ],
    );
  }

  Widget _highContrastEditor() {
    return Row(
      children: [
        SizedBox(width: 100, child: Text('High contrast')),
        Checkbox(
          value: _value.highContrast,
          onChanged: (v) {
            setState(() {
              _value = _value.rebuild((b) => b.highContrast = v);
            });
          },
        ),
      ],
    );
  }

  Widget _invertColorsEditor() {
    return Row(
      children: [
        SizedBox(width: 100, child: Text('Invert colors')),
        Checkbox(
          value: _value.invertColors,
          onChanged: (v) {
            setState(() {
              _value = _value.rebuild((b) => b.invertColors = v);
            });
          },
        ),
      ],
    );
  }

  static const _buttonBackground = Colors.black12;
  static const _buttonBorderColor = Color(0xffC4C4C4);
  static const _textStyle = TextStyle(fontSize: 13, color: Colors.black87);
  ElevatedButtonThemeData _buttonTheme() {
    return ElevatedButtonThemeData(
      style: ButtonStyle(
        elevation: WidgetStateProperty.all(0),
        shape: WidgetStateProperty.all(
          RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(3),
              side: BorderSide(color: _buttonBorderColor)),
        ),
        backgroundColor: WidgetStateProperty.all(_buttonBackground),
        foregroundColor: WidgetStateProperty.all(Colors.black87),
        visualDensity: VisualDensity.compact,
        textStyle: WidgetStateProperty.all(_textStyle),
      ),
    );
  }
}
