import 'package:flutter/material.dart';

import 'package:flutterware/ui_catalog.dart';

/// Stands in for a project's own catalog shell.
///
/// The axes are declared inside it, by asking for them, which is how the
/// catalog learns they exist — there is no list of axes anywhere, only the
/// calls the shell makes. That leaves `wrapInApp` an ordinary
/// `Widget Function(Widget)`: `@Demo(wrapper: wrapInApp)` takes it, Flutter's
/// own previewer calls it with one argument, and the real app calls it like any
/// other function. In all three the axes answer with their defaults.
enum Flavor { dev, staging, prod }

Widget wrapInApp(Widget child) => CatalogShell(
  'app',
  builder: (context, topBar) {
    // Labels, not identifiers: only the labels cross the wire, so the top bar
    // shows what is written here rather than `Flavor.prod.name`.
    var flavor = topBar.picker('flavor', {
      'Dev': Flavor.dev,
      'Staging': Flavor.staging,
      'Production': Flavor.prod,
    }, Flavor.dev);
    var compact = topBar.flag('compact', false);
    return _Shell(flavor: flavor, compact: compact, child: child);
  },
);

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
