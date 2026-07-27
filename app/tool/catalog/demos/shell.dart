import 'package:flutter/material.dart';

import 'package:flutterware/ui_catalog.dart';

/// Stands in for a project's own catalog shell.
///
/// The axes are its optional named parameters and nothing else. That keeps the
/// function assignable to `WidgetWrapper` — `@Demo(wrapper: wrapInApp)` still
/// takes it, Flutter's own previewer still calls it with one argument, and the
/// real app still calls it like any other function. Only the catalog calls it
/// by name, which is where the named parameters are still visible.
enum Flavor { dev, staging, prod }

@CatalogShell()
Widget wrapInApp(
  Widget child, {
  Flavor flavor = Flavor.dev,
  bool compact = false,
}) => _Shell(flavor: flavor, compact: compact, child: child);

class _Shell extends StatelessWidget {
  const _Shell({
    required this.flavor,
    required this.compact,
    required this.child,
  });

  final Flavor flavor;
  final bool compact;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: switch (flavor) {
          Flavor.dev => const Color(0xff3366ff),
          Flavor.staging => const Color(0xffff9900),
          Flavor.prod => const Color(0xff11aa55),
        },
        visualDensity: compact ? VisualDensity.compact : VisualDensity.standard,
      ),
      // On screen so the headless check can read which way the axes are set
      // without a picture — the probe walks the tree for Text.
      home: Stack(
        children: [
          child,
          Positioned(
            right: 0,
            bottom: 0,
            child: Text(
              'SHELL ${flavor.name} ${compact ? 'compact' : 'roomy'}',
            ),
          ),
        ],
      ),
    );
  }
}
