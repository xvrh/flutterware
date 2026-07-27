import 'package:flutter/material.dart';

/// Stands in for a project's own catalog shell — the wrapper that would declare
/// theme and locale axes. A `WidgetWrapper` must be static and public.
Widget wrapInApp(Widget child) => _Shell(child: child);

class _Shell extends StatelessWidget {
  const _Shell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: const Color(0xff3366ff)),
      home: child,
    );
  }
}
