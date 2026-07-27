import 'package:flutter/material.dart';

import 'package:flutterware/ui_catalog.dart';

import 'shell.dart';

/// Reports the padding a demo actually sees, which is the only way to tell a
/// notch that is drawn from one that is respected.
@Demo(name: 'Padding', wrapper: wrapInApp)
Widget paddingProbe() => const _PaddingProbe();

class _PaddingProbe extends StatelessWidget {
  const _PaddingProbe();

  @override
  Widget build(BuildContext context) {
    var padding = MediaQuery.paddingOf(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Padding')),
      body: Center(child: Text('PADDING ${padding.top},${padding.bottom}')),
    );
  }
}
