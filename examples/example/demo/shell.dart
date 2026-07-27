import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

/// The app chrome a demo needs to look like itself: theme, localizations,
/// directionality.
///
/// Demos are widgets, not apps — the catalog renders the widget and nothing
/// else — so anything that normally comes from `MaterialApp` has to be put back
/// by a wrapper. This is that wrapper, and it is shared rather than repeated
/// because a demo that themes itself differently from the app is not a preview
/// of the app.
Widget wrapInApp(Widget child) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: ThemeData(
    colorSchemeSeed: Colors.white,
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(),
    ),
  ),
  localizationsDelegates: [...GlobalMaterialLocalizations.delegates],
  supportedLocales: const [Locale('en'), Locale('fr')],
  home: child,
);
