//@flutterware:scenes=1
// This folder is a scene group: every `.scene.dart` below it is one of its
// scenes, and this file says what those scenes may use. The flutterware
// scene editor reads it as text — the closures are skipped — and generates
// `scene_args.dart` beside it; it never writes here except to attach a token
// library you created.
//
// This is the file that stands in for resolving the package. The editor
// never compiles the app, so it cannot discover that `DrinkBadge` takes a
// `double size` — it is told here, and everything downstream follows: the
// generated `DrinkBadgeArgs` a scene file spells, the type the inspector
// shows, and the refusal for an argument the widget does not have.
//
// - widgets: the app's widgets a scene may place, each with its arguments.
//   It is the only place in the system that names an argument with a
//   string, by decision: written by hand, it has to compile before anything
//   has been generated from it, so it mentions nothing generated.
// - exports: the app's own values, named for the scenes — any type, any
//   expression. The canvas resolves them; the editor only names them.
// - libraries: the token libraries these scenes read, imported above.
// - wrap: what the canvas is mounted under — this app's theme.
import 'package:flutter/material.dart';
import 'package:flutterware/scene.dart';
import 'package:flutterware/scene_authoring.dart';
import 'package:flutterware_example/shop/shop_app.dart' as app;

import 'brand.tokens.dart';

final scenes = SceneGroup(
  libraries: [brandTokens],
  widgets: [
    ExternalWidget(
      'DrinkBadge',
      args: [const Arg<double>('size', 56)],
      build: (a) => app.DrinkBadge(app.drinks[1], size: a.number('size') ?? 56),
    ),
    ExternalWidget(
      'Spinner',
      args: [const Arg<double>('size', 36)],
      build: (a) => app.Spinner(size: a.number('size') ?? 36),
    ),
    ExternalWidget(
      'OrderButton',
      // `style` is the app's own object: a scene fills it with an exported
      // token or leaves it to the widget, and the editor never sees inside.
      args: [
        const Arg<String>('label', 'Order now'),
        const Arg<ButtonStyle>('style'),
      ],
      build: (a) => app.OrderButton(
        label: a.text('label') ?? 'Order now',
        style: a.raw('style') as ButtonStyle?,
      ),
    ),
  ],
  exports: [
    // The app's own look for its call to action: named here, filled into
    // `OrderButtonArgs(style: tokens.ctaStyle)` by a scene, built by this
    // process — only this app ever sees inside a ButtonStyle.
    Token<ButtonStyle>(
      'ctaStyle',
      FilledButton.styleFrom(
        backgroundColor: const Color(0xFFE8632B),
        foregroundColor: Colors.white,
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 18),
      ),
    ),
  ],
  // The app's own look — what the editor canvas inherits by construction.
  wrap: (child) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(colorSchemeSeed: const Color(0xFF8C5A3C)),
    home: child,
  ),
);
