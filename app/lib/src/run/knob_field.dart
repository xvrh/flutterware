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
class KnobField extends StatelessWidget {
  const KnobField({
    super.key,
    required this.knob,
    required this.value,
    required this.onChanged,
  });

  final RunKnobEntry knob;

  /// What is set now, or null for "left alone" — which is not the same as
  /// empty, and is why the default is a hint rather than a filled-in value.
  final String? value;

  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(knob.label ?? knob.name, style: context.type.fieldLabel),
            if (knob.kind case var kind?) ...[
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
        if (knob.description case var description?)
          Text(description, style: context.type.caption),
        const Gap(FwSpacing.xxs),
        _control(context),
        if (knob.problem case var problem?) ...[
          const Gap(FwSpacing.xxs),
          Text(
            problem,
            style: context.type.caption.copyWith(color: context.colors.amber),
          ),
        ],
      ],
    );
  }

  Widget _control(BuildContext context) => switch (knob.kind) {
    'boolean' => Row(
      children: [
        Switch(
          value: (value ?? knob.defaultValue) == 'true',
          onChanged: (on) => onChanged('$on'),
        ),
        const Gap(FwSpacing.sm),
        Text(
          (value ?? knob.defaultValue) == 'true' ? 'true' : 'false',
          style: context.type.caption,
        ),
      ],
    ),
    'picker' => DropdownButtonFormField<String>(
      initialValue: value ?? knob.defaultValue,
      // Only what the enum declares. There is no "other" to type, because
      // there is no other constant to name.
      items: [
        for (var option in knob.options)
          DropdownMenuItem(value: option, child: Text(option)),
      ],
      onChanged: onChanged,
    ),
    _ => TextFormField(
      initialValue: value,
      // The default is shown rather than filled in, so leaving the field alone
      // and leaving it at its default are the same thing — the rule the define
      // form already follows.
      decoration: InputDecoration(hintText: knob.defaultValue),
      keyboardType: switch (knob.kind) {
        'integer' || 'number' => TextInputType.number,
        _ => TextInputType.text,
      },
      onChanged: (text) => onChanged(text.isEmpty ? null : text),
    ),
  };
}
