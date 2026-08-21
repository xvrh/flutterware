/// The keyboard that is not there: what a screen loses when one comes up, and
/// the slab that stands in for it.
///
/// Painted, never built. A keyboard composed of widgets would put key caps
/// in front of `find.text`, a hundred nodes into the semantics and transcript
/// audits, and a wall of junk into `screen()`. One [CustomPainter] under an
/// [ExcludeSemantics] is one leaf, one paint call, and invisible to every
/// finder.
///
/// No glyphs. Letters would need a font that differs between the previews
/// harness and a bare `flutter test`, and a per-locale layout to not be a lie.
/// Rows of rounded rectangles say *keyboard* without claiming a language.
///
/// Shared by both lanes on purpose — the guest drives it from a
/// [TextInputControl], a scenario drives it from the test binding, and the
/// picture they produce has to be the same picture.
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../devices.dart';

/// A screen with [height] logical pixels of keyboard across the bottom of it.
///
/// Two things at once, because they are one fact: the [MediaQuery] the app
/// reads and the pixels a capture contains. Splitting them is how a fake
/// keyboard ends up as artwork the layout does not know about — or as an inset
/// with nothing on screen to explain where the bottom third went.
///
/// Zero is free: no stack, no painter, nothing added to the tree at all.
class FakeKeyboard extends StatelessWidget {
  const FakeKeyboard({
    super.key,
    required this.height,
    this.platform,
    required this.child,
  });

  /// How tall, in logical pixels. Zero for a keyboard that is down.
  final double height;

  /// Which keyboard to draw. Null takes the iOS tint, which is also what a
  /// device with no platform of its own would be shown on.
  final DevicePlatform? platform;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    var media = MediaQuery.of(context);
    // **The wrappers are unconditional, and that is not tidiness.** A widget
    // that returns its child bare at zero and wraps it at 336 *reparents the
    // app* the moment the keyboard moves: every `State` under it is disposed
    // and rebuilt, which loses the focus, closes the text input connection and
    // empties whatever had been typed. Measured — a scenario tapping a field
    // saw `TextInput.show` immediately followed by `clearClient`, and the
    // keyboard it had just asked for went straight back down.
    //
    // So the shape stays put and only the numbers move. Down costs one
    // `MediaQuery` with the data it was given and a zero-height band.
    return MediaQuery(
      // The arithmetic, and all three numbers of it. Getting only the first is
      // how a fake keyboard ends up with a `SafeArea` floating 34 points above
      // it: `MediaQueryData.fromView` reads `view.padding` directly rather
      // than deriving it from the insets, so a driver that raises the insets
      // and leaves the padding alone is describing a phone that does not
      // exist. A real embedder eats the home indicator — measured on eight
      // simulators and an emulator, `padding.bottom` is 0 on every one of them
      // while the keyboard is up — and `viewPadding` is what still remembers
      // the device underneath.
      data: height <= 0
          ? media
          : media.copyWith(
              padding: media.padding.copyWith(
                bottom: math.max(0, media.padding.bottom - height),
              ),
              viewInsets: media.viewInsets.copyWith(bottom: height),
            ),
      child: FakeKeyboardSlab(height: height, platform: platform, child: child),
    );
  }
}

/// The slab alone, over [child], with none of the arithmetic.
///
/// Its own widget because the two lanes divide the work differently. In a
/// preview the numbers are a `MediaQuery` this package writes, so [FakeKeyboard]
/// does both halves in one place. In a scenario they are the *view's* — set on
/// the binding's test values exactly as a real embedder would report them, so
/// that every `MediaQuery.fromView` in the app sees them and not only the
/// subtree under one widget — and all that is left for the tree is the picture
/// and the occlusion. Which is this.
class FakeKeyboardSlab extends StatelessWidget {
  const FakeKeyboardSlab({
    super.key,
    required this.height,
    this.platform,
    required this.child,
  });

  final double height;
  final DevicePlatform? platform;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      // Non-directional on purpose: the default `AlignmentDirectional.topStart`
      // needs a `Directionality`, and this widget sits **above** the app — in
      // the scenario lane there is no `MaterialApp` over it to supply one, and
      // asking a keyboard to know the reading direction to draw a band at the
      // bottom of the screen would be inventing a dependency.
      alignment: Alignment.topLeft,
      children: [
        child,
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          // Zero when it is down — kept in the tree rather than removed, for
          // the reason [FakeKeyboard] gives: a child list that changes length
          // is a child list that can reparent, and reparenting the app is how
          // a keyboard ends up wiping the field that asked for it.
          height: math.max(0, height),
          // **It hit-tests true**, because that is what a keyboard does: a tap
          // that lands on it does not reach the app. Absorbing rather than
          // ignoring is the whole difference between a picture of a keyboard
          // and a keyboard.
          child: ExcludeSemantics(
            child: AbsorbPointer(
              child: CustomPaint(
                size: Size.infinite,
                painter: FakeKeyboardPainter(
                  platform: platform,
                  dark:
                      MediaQuery.platformBrightnessOf(context) ==
                      Brightness.dark,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The slab: a suggestion strip, three letter rows, a bottom row with a space
/// bar, and whatever band the platform leaves below it.
///
/// Proportional to the box it is given rather than to a key size, because the
/// box is a measurement — an iPhone SE's 260 points and an iPad Pro's 501 hold
/// the same rows at different sizes, which is what real keyboards do.
class FakeKeyboardPainter extends CustomPainter {
  FakeKeyboardPainter({required this.platform, required this.dark});

  final DevicePlatform? platform;
  final bool dark;

  bool get _android => platform == DevicePlatform.android;

  /// The slab itself.
  Color get _ground => switch ((_android, dark)) {
    (true, false) => const Color(0xFFEDEFF2),
    (true, true) => const Color(0xFF1F2023),
    (false, false) => const Color(0xFFD1D4DB),
    (false, true) => const Color(0xFF1C1C1E),
  };

  /// An ordinary letter key.
  Color get _key => switch ((_android, dark)) {
    (true, false) => const Color(0xFFFFFFFF),
    (true, true) => const Color(0xFF3C4043),
    (false, false) => const Color(0xFFFFFFFF),
    (false, true) => const Color(0xFF4A4A4E),
  };

  /// Shift, backspace, return — the ones a real keyboard draws darker.
  Color get _modifier => switch ((_android, dark)) {
    (true, false) => const Color(0xFFDCE0E5),
    (true, true) => const Color(0xFF2B2D30),
    (false, false) => const Color(0xFFAEB3BD),
    (false, true) => const Color(0xFF313134),
  };

  /// The suggestion pills, which are text on a real keyboard and shapes here.
  Color get _hint => _modifier.withValues(alpha: dark ? 0.9 : 0.75);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = _ground);
    // The one line that says where the app stops. A slab the same value as a
    // white app has no edge at all, and the app's own bottom row then looks
    // like the keyboard's top row.
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, 0.5),
      Paint()..color = const Color(0x22000000),
    );

    // The bands, top to bottom. The suggestion strip is inside the measured
    // number rather than beside it — see the design's *Not in v1* — and so is
    // the home indicator, which is why the rows stop short of the bottom.
    var strip = size.height * 0.14;
    var foot = size.height * (_android ? 0.05 : 0.10);
    var rowsTop = strip;
    var rowsHeight = size.height - strip - foot;
    if (rowsHeight <= 0) return;

    _paintStrip(canvas, Rect.fromLTWH(0, 0, size.width, strip));

    var gap = math.max(1.0, rowsHeight * 0.055);
    var rowHeight = (rowsHeight - gap * 4) / 4;
    if (rowHeight <= 0) return;
    var margin = size.width * 0.012;
    var radius = Radius.circular(_android ? rowHeight * 0.16 : rowHeight * 0.2);

    double rowTop(int index) => rowsTop + gap * (index + 1) + rowHeight * index;

    // 10, 9 inset by half a key, then shift + 7 + backspace. The alphabet
    // every Latin layout is some permutation of.
    _paintKeys(canvas, size, rowTop(0), rowHeight, margin, radius, 10, gap);
    _paintKeys(
      canvas,
      size,
      rowTop(1),
      rowHeight,
      margin + (size.width - margin * 2) / 20,
      radius,
      9,
      gap,
    );
    _paintWeighted(
      canvas,
      size,
      rowTop(2),
      rowHeight,
      margin,
      radius,
      gap,
      const [
        (1.5, true),
        (1, false),
        (1, false),
        (1, false),
        (1, false),
        (1, false),
        (1, false),
        (1, false),
        (1.5, true),
      ],
    );
    // The bottom row is where the two platforms visibly differ: iOS gives the
    // return key a fifth of the row, Android splits the same width between a
    // comma, a full stop and a smaller enter.
    _paintWeighted(
      canvas,
      size,
      rowTop(3),
      rowHeight,
      margin,
      radius,
      gap,
      _android
          ? const [(1.4, true), (1, true), (5, false), (1, true), (1.4, true)]
          : const [(1.4, true), (1.1, true), (4.6, false), (1.9, true)],
    );
  }

  /// Three pills where a real keyboard puts the words it is guessing at.
  void _paintStrip(Canvas canvas, Rect band) {
    var paint = Paint()..color = _hint;
    var pill = band.height * 0.34;
    var y = band.center.dy - pill / 2;
    // Uneven, because guesses are words rather than a measured set of three.
    const widths = [0.16, 0.22, 0.13];
    var x = band.width * 0.10;
    for (var (index, fraction) in widths.indexed) {
      var width = band.width * fraction;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x + index * band.width * 0.07, y, width, pill),
          Radius.circular(pill / 2),
        ),
        paint,
      );
      x += width;
    }
  }

  void _paintKeys(
    Canvas canvas,
    Size size,
    double top,
    double height,
    double margin,
    Radius radius,
    int count,
    double gap,
  ) {
    var available = size.width - margin * 2;
    var keyGap = gap * 0.6;
    var width = (available - keyGap * (count - 1)) / count;
    var paint = Paint()..color = _key;
    for (var i = 0; i < count; i++) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(margin + i * (width + keyGap), top, width, height),
          radius,
        ),
        paint,
      );
    }
  }

  /// A row of keys of unequal width — `(weight, isModifier)` each.
  void _paintWeighted(
    Canvas canvas,
    Size size,
    double top,
    double height,
    double margin,
    Radius radius,
    double gap,
    List<(double, bool)> keys,
  ) {
    var available = size.width - margin * 2;
    var keyGap = gap * 0.6;
    var total = keys.fold<double>(0, (sum, key) => sum + key.$1);
    var unit = (available - keyGap * (keys.length - 1)) / total;
    var x = margin;
    for (var (weight, modifier) in keys) {
      var width = unit * weight;
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(x, top, width, height), radius),
        Paint()..color = modifier ? _modifier : _key,
      );
      x += width + keyGap;
    }
  }

  @override
  bool shouldRepaint(FakeKeyboardPainter old) =>
      old.platform != platform || old.dark != dark;
}

/// [FakeKeyboardSlab] as tall as the **view** says the keyboard is.
///
/// For the lanes where the numbers are the view's rather than a widget's — a
/// scenario, and the previews harness on `flutter_tester` — which is every
/// lane running under a test binding. Reading the height back off the view is
/// what stops the picture and the layout from being two facts: they are one,
/// and the app met it first.
class ViewKeyboardSlab extends StatelessWidget {
  const ViewKeyboardSlab({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => FakeKeyboardSlab(
    height: MediaQuery.viewInsetsOf(context).bottom,
    // The staged platform, which the run has already set from the device —
    // the same fact the app's own `.adaptive` widgets read.
    platform: defaultTargetPlatform == TargetPlatform.android
        ? DevicePlatform.android
        : DevicePlatform.ios,
    child: child,
  );
}
