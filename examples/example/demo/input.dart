import 'package:flutter/material.dart';
import 'package:flutterware/ui_catalog.dart';

import 'shell.dart';

/// Exercises what the preview forwards into the guest: typing needs the
/// guest's own text input (there is no platform IME on the other side), and
/// scrolling needs wheel and trackpad events on the wire.

@Demo(name: 'Text fields', wrapper: wrapInApp)
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
/// that typing landed — see `app/tool/embedder/typing_probe.dart`.
class _EchoField extends StatefulWidget {
  const _EchoField();

  @override
  State<_EchoField> createState() => _EchoFieldState();
}

class _EchoFieldState extends State<_EchoField> {
  final _controller = TextEditingController();

  @override
  void dispose() {
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
        onChanged: (_) => setState(() {}),
      ),
      Text('echo: ${_controller.text}'),
    ],
  );
}

@Demo(name: 'Scrolling', wrapper: wrapInApp)
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
