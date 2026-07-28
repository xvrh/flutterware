import 'package:flutter/material.dart';

import 'package:flutterware/ui_catalog.dart';

/// A second shell, with axes of its own.
///
/// A project has as many as it needs, and an entry gets the axes of the one its
/// `wrapper:` builds — so the top bar changes as you move between them. Its
/// `flavor` is deliberately named like the other shell's and takes different
/// values: two shells sharing an axis name must not inherit each other's
/// selection, which is what filing selections under the shell's id is for.
enum Loudness { quiet, loud }

enum Flavour { plain, fancy }

Widget wrapInPlainApp(Widget child) => CatalogShell(
  'plain',
  builder: (context, topBar) {
    var loudness = topBar.picker('loudness', {
      'Quiet': Loudness.quiet,
      'Loud': Loudness.loud,
    }, Loudness.quiet);
    var flavor = topBar.picker('flavor', {
      'Plain': Flavour.plain,
      'Fancy': Flavour.fancy,
    }, Flavour.plain);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Stack(
        children: [
          child,
          Positioned(
            right: 0,
            bottom: 0,
            child: Text('OTHER ${loudness.name} ${flavor.name}'),
          ),
        ],
      ),
    );
  },
);

@Demo(name: 'Elsewhere', wrapper: wrapInPlainApp)
Widget elsewhere() => const Center(child: Text('ELSEWHERE'));
