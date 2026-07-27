import 'package:flutter/material.dart';
import 'package:flutterware/ui_catalog.dart';

import 'shell.dart';

/// A single demo in its own file, so it gets no group and sits at the top
/// level of the catalog — the counterpart to `home_page.dart`.
@Demo(name: 'Buttons', wrapper: wrapInApp)
Widget buttons() => Scaffold(
  appBar: AppBar(title: const Text('Buttons')),
  body: Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      spacing: 12,
      children: [
        ElevatedButton(onPressed: () {}, child: const Text('Elevated')),
        FilledButton(onPressed: () {}, child: const Text('Filled')),
        OutlinedButton(onPressed: () {}, child: const Text('Outlined')),
        TextButton(onPressed: () {}, child: const Text('Text')),
        const ElevatedButton(onPressed: null, child: Text('Disabled')),
      ],
    ),
  ),
);
