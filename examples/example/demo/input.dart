import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

import 'shell.dart';

/// Exercises what the preview forwards into the guest: typing needs the
/// guest's own text input (there is no platform IME on the other side), and
/// scrolling needs wheel and trackpad events on the wire.

/// A field per keyboard the platform can be asked for — which is what makes
/// this the entry to look at when the fake keyboard changes: tapping between
/// them morphs one keyboard into another, and on a phone the digits one is
/// measurably shorter.
@Preview(name: 'Keyboards', group: 'Input', wrapper: wrapInApp)
Widget keyboards() => Scaffold(
  appBar: AppBar(title: const Text('Keyboards')),
  body: Padding(
    padding: const EdgeInsets.all(24),
    child: Column(
      spacing: 16,
      children: [
        const TextField(
          autofocus: true,
          keyboardType: TextInputType.phone,
          decoration: InputDecoration(labelText: 'Phone — a digit pad'),
        ),
        const TextField(
          keyboardType: TextInputType.emailAddress,
          decoration: InputDecoration(labelText: 'Email — an @ and a dot'),
        ),
        const TextField(
          keyboardType: TextInputType.url,
          decoration: InputDecoration(labelText: 'URL — a slash and a .com'),
        ),
        const TextField(
          decoration: InputDecoration(labelText: 'Text — the letters'),
        ),
        const TextField(
          keyboardType: TextInputType.none,
          decoration: InputDecoration(labelText: 'None — brings its own pad'),
        ),
      ],
    ),
  ),
);

@Preview(name: 'Text fields', group: 'Input', wrapper: wrapInApp)
Widget textFields() => Scaffold(
  appBar: AppBar(title: const Text('Text fields')),
  body: Padding(
    padding: const EdgeInsets.all(24),
    child: Column(
      spacing: 16,
      children: [
        const _EchoField(),
        const TextField(
          maxLines: 4,
          decoration: InputDecoration(labelText: 'Multiline'),
        ),
        Builder(
          builder: (context) => TextField(
            decoration: const InputDecoration(labelText: 'Submit me'),
            onSubmitted: (value) => ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text('Submitted: $value'))),
          ),
        ),
      ],
    ),
  ),
);

/// A field beside a `Text` of what it holds.
///
/// The echo is not decoration: a field's content lives in `EditableText`'s
/// render object, where an inspecting tool cannot read it, while a `Text` is
/// right there in the widget tree. It is what lets a headless check assert
/// that typing landed — see `app/tool/embedder/input_probe.dart`.
class _EchoField extends StatefulWidget {
  const _EchoField();

  @override
  State<_EchoField> createState() => _EchoFieldState();
}

class _EchoFieldState extends State<_EchoField> {
  final _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    // The controller, not `onChanged`: that one fires on text only, so a caret
    // that moved without typing would leave the readout showing where the
    // caret used to be — which reads exactly like an arrow key doing nothing.
    _controller.addListener(_onChanged);
  }

  void _onChanged() => setState(() {});

  @override
  void dispose() {
    _controller.removeListener(_onChanged);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    spacing: 8,
    children: [
      TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Single line'),
      ),
      Text('echo: ${_controller.text}'),
      Text('sel: ${_controller.selection.start},${_controller.selection.end}'),
    ],
  );
}

@Preview(name: 'Scrolling', group: 'Input', wrapper: wrapInApp)
Widget scrolling() => Scaffold(
  appBar: AppBar(title: const Text('Scrolling')),
  body: ListView.builder(
    itemCount: 100,
    itemBuilder: (context, index) => ListTile(
      leading: CircleAvatar(child: Text('$index')),
      title: Text('Row $index'),
      subtitle: const Text('Wheel and trackpad should both move this'),
    ),
  ),
);
