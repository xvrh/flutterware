import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:flutterware/previews.dart';

/// The shop's launcher icon, drawn here and nowhere else.
///
/// Every icon file under `android/` and `ios/` is a picture of this preview:
/// `app/tool/demo/brand_icons.dart` photographs it once per set and role at
/// 1024 and writes each file at the size it already has, so the sets keep the
/// shapes the README explains — a partial override, an iOS-only set — and
/// only the art changes. The two knobs are the two things a file differs by:
/// which set it belongs to, told apart by tint, and which role it plays.
@Preview(name: 'App icon', group: 'Brewline', size: Size(1024, 1024))
Widget appIcon() => const BrandIcon();

class BrandIcon extends StatelessWidget {
  const BrandIcon({super.key});

  static const tints = {
    'main': Color(0xFF6F4E37),
    'pro': Color(0xFF2E7D32),
    'kiosk': Color(0xFFC62828),
    'partner': Color(0xFF6A1B9A),
  };

  @override
  Widget build(BuildContext context) {
    var knobs = context.knobs;
    var set = knobs.picker('set', {
      for (var name in tints.keys) name: name,
    }, 'main');
    var role = knobs.picker('role', const {
      'icon': 'icon',
      'foreground': 'foreground',
      'monochrome': 'monochrome',
    }, 'icon');
    var tint = tints[set] ?? tints['main']!;
    // Its own directionality: this is a picture, not a screen in an app.
    return Directionality(
      textDirection: TextDirection.ltr,
      child: LayoutBuilder(
        builder: (context, constraints) {
          var side = constraints.biggest.shortestSide;
          return switch (role) {
            // Opaque and square: iOS masks its own corners and refuses alpha,
            // and a legacy Android launcher shows the file as it is.
            'icon' => ColoredBox(
              color: tint,
              child: Center(
                child: Icon(
                  Icons.coffee_rounded,
                  size: side * 0.62,
                  color: const Color(0xFFFFF3E0),
                ),
              ),
            ),
            // The adaptive foreground: transparent, with the cup inside the
            // 66% safe zone a launcher may mask to.
            'foreground' => Center(
              child: Icon(
                Icons.coffee_rounded,
                size: side * 0.44,
                color: const Color(0xFFFFF3E0),
              ),
            ),
            // The themed icon: one colour, same geometry as the foreground.
            _ => Center(
              child: Icon(
                Icons.coffee_rounded,
                size: side * 0.44,
                color: Colors.white,
              ),
            ),
          };
        },
      ),
    );
  }
}
