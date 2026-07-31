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
        const TextField(
          autofocus: true,
          decoration: InputDecoration(labelText: 'Single line'),
        ),
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
