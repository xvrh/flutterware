import 'package:flutter/material.dart';

import '../plugins/native/run_results.dart';
import '../ui/design/spacing.dart';
import '../ui/design/tokens.dart';

/// One knob, drawn for the kind its parameter declares.
///
/// **One widget, two hosts** — the New run page fills these in before a launch,
/// and the running app's Knobs tab edits the same knobs afterwards. A knob that
/// looked like a text field in one place and a dropdown in the other would be
/// two controls for one value.
///
/// The control follows the *signature's* type, never the value's: a `bool`
/// parameter is a switch even when nobody has set it, and an enum is a dropdown
/// of its own constants rather than a field you can misspell into.
///
/// **A kind that is not a picker can still have options**, and drawing them is
/// not optional. `Knob('apiHost', from: ValueSource.hostAddresses)` is a
/// `String` parameter — kind `string`, so a text field — and its whole reason
/// for existing is the list underneath it: this machine's LAN addresses, so
/// "point the app at my dev machine" is a click rather than a trip to
/// `ifconfig`. Chips rather than a dropdown, because unlike an enum's constants
/// these are suggestions and typing something else is allowed.
class KnobField extends StatefulWidget {
  const KnobField({
    super.key,
    required this.knob,
    required this.value,
    required this.onChanged,
    this.interfaceOf,
  });

  final RunKnobEntry knob;

  /// What is set now, or null for "left alone" — which is not the same as
  /// empty, and is why the default is a hint rather than a filled-in value.
  final String? value;

  final ValueChanged<String?> onChanged;

  /// The interface an offered value was found on — `en0` — when it is one of
  /// this machine's addresses. Five bare IPv4s say nothing about which one the
  /// phone can reach; `en0` next to one of them does.
  final String? Function(String)? interfaceOf;

  @override
  State<KnobField> createState() => _KnobFieldState();
}

class _KnobFieldState extends State<KnobField> {
  /// Held here rather than left to `initialValue`, because a chip changes the
  /// value from outside the field and `initialValue` is read once. Without it a
  /// tap updated the form's state and left the text box showing the old value.
  late final _text = TextEditingController(text: widget.value ?? '');

  @override
  void didUpdateWidget(KnobField old) {
    super.didUpdateWidget(old);
    var value = widget.value ?? '';
    if (value != _text.text) _text.text = value;
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  RunKnobEntry get _knob => widget.knob;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(_knob.label ?? _knob.name, style: context.type.fieldLabel),
            if (_knob.kind case var kind?) ...[
              const Gap(FwSpacing.sm),
              Text(
                kind,
                style: context.type.caption.copyWith(
                  color: context.colors.mut3,
                ),
              ),
            ],
          ],
        ),
        if (_knob.description case var description?)
          Text(description, style: context.type.caption),
        const Gap(FwSpacing.xxs),
        _control(context),
        if (_knob.problem case var problem?) ...[
          const Gap(FwSpacing.xxs),
          Text(
            problem,
            style: context.type.caption.copyWith(color: context.colors.amber),
          ),
        ],
        // Not under a picker: its options are already the only thing it can be,
        // so a second copy of them below the dropdown would be the same list
        // twice.
        if (_knob.kind != 'picker' &&
            _knob.kind != 'boolean' &&
            _knob.options.isNotEmpty) ...[
          const Gap(FwSpacing.xs),
          Wrap(
            spacing: FwSpacing.xs,
            runSpacing: FwSpacing.xxs,
            children: [
              for (var option in _knob.options)
                ActionChip(
                  label: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(option, style: context.type.micro),
                      if (widget.interfaceOf?.call(option)
                          case var interface?) ...[
                        const Gap(FwSpacing.xxs),
                        Text(
                          interface,
                          style: context.type.micro.copyWith(
                            color: context.colors.mut3,
                          ),
                        ),
                      ],
                    ],
                  ),
                  onPressed: () => widget.onChanged(option),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _control(BuildContext context) => switch (_knob.kind) {
    'boolean' => Row(
      children: [
        Switch(
          value: (widget.value ?? _knob.defaultValue) == 'true',
          onChanged: (on) => widget.onChanged('$on'),
        ),
        const Gap(FwSpacing.sm),
        Text(
          (widget.value ?? _knob.defaultValue) == 'true' ? 'true' : 'false',
          style: context.type.caption,
        ),
      ],
    ),
    'picker' => DropdownButtonFormField<String>(
      // Only a value the list actually holds. A script source can compute one
      // for an enum knob that is not among its constants, and a dropdown asked
      // to show a value it has no item for asserts rather than degrading.
      initialValue: _knob.options.contains(widget.value ?? _knob.defaultValue)
          ? widget.value ?? _knob.defaultValue
          : null,
      // Only what the enum declares. There is no "other" to type, because
      // there is no other constant to name.
      items: [
        for (var option in _knob.options)
          DropdownMenuItem(value: option, child: Text(option)),
      ],
      onChanged: widget.onChanged,
    ),
    _ => TextFormField(
      controller: _text,
      // The default is shown rather than filled in, so leaving the field alone
      // and leaving it at its default are the same thing — the rule the define
      // form already followed.
      decoration: InputDecoration(hintText: _knob.defaultValue),
      keyboardType: switch (_knob.kind) {
        'integer' || 'number' => TextInputType.number,
        _ => TextInputType.text,
      },
      onChanged: (text) => widget.onChanged(text.isEmpty ? null : text),
    ),
  };
}
