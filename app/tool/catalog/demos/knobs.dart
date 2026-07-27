import 'package:flutter/material.dart';

import 'package:flutterware/ui_catalog.dart';

import 'shell.dart';

/// Declares its controls by reading them while it builds, which is how the
/// catalog learns they exist — there is no list of knobs anywhere, only the
/// calls a demo makes.
@Demo(name: 'Knobs', wrapper: wrapInApp)
Widget knobs() => const _Knobs();

class _Knobs extends StatelessWidget {
  const _Knobs();

  @override
  Widget build(BuildContext context) {
    var parameters = context.uiCatalog.parameters;
    var label = parameters.string('label', 'Hello');
    var count = parameters.int('count', 2, min: 0, max: 9);
    var dense = parameters.bool('denseaa', false);
    return Scaffold(
      appBar: AppBar(title: const Text('Knobs3')),
      body: Center(
        child: Text(
          'KNOB $label x$count ${dense ? 'dense' : 'roomy'}',
          style: TextStyle(fontSize: dense ? 12 : 20),
        ),
      ),
    );
  }
}
