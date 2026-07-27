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
      // Where the chosen device's safe areas become a notch an AppBar
      // respects.
      //
      // The catalog draws the phone in *another process*, so the only way in
      // is the guest's window metrics — and `FlutterWindowMetricsEvent` has no
      // padding field, only `physical_view_inset_*`, which arrives as
      // `viewInsets`. The host packs the safe areas there; this turns them
      // back into padding. It has to happen under `MaterialApp`, which builds
      // its own MediaQuery from the raw view and replaces anything set above.
      builder: (context, child) {
        var media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(
            padding: media.viewInsets,
            viewPadding: media.viewInsets,
            viewInsets: EdgeInsets.zero,
          ),
          child: child!,
        );
      },
      home: child,
    );
  }
}
