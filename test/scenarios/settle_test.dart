import 'package:flutter/material.dart';
import 'package:flutterware/flutter_test.dart';

/// The settle policies on their own, driven through a plain `WidgetTester` —
/// the layer every verb delegates to.
void main() {
  testWidgets('a bounded settle gives up on an indefinite animation', (
    tester,
  ) async {
    await tester.pumpWidget(const _Spinner());

    // The measured trap: `pumpAndSettle` throws here, because a repeating
    // animation always has the next frame scheduled.
    expect(await Settle.standard.apply(tester), isFalse);
  });

  testWidgets('a bounded settle reports settled on a still app', (
    tester,
  ) async {
    await tester.pumpWidget(const _Still());

    expect(await Settle.standard.apply(tester), isTrue);
  });

  testWidgets('a bounded settle waits for a finite animation', (tester) async {
    await tester.pumpWidget(const _Fading());

    expect(await Settle.standard.apply(tester), isTrue);
    expect(tester.widget<Opacity>(find.byType(Opacity)).opacity, 1.0);
  });

  testWidgets('a budget shorter than the animation gives up mid-flight', (
    tester,
  ) async {
    await tester.pumpWidget(const _Fading());

    expect(
      await const Settle.upTo(Duration(milliseconds: 300)).apply(tester),
      isFalse,
    );
    expect(tester.widget<Opacity>(find.byType(Opacity)).opacity, lessThan(1.0));
  });

  // `Settle.full` is `pumpAndSettle` itself, throw included — untested here
  // because the SDK's throw escapes its own `TestAsyncUtils.guard` after the
  // body returns and fails the test whatever the body does with it. That
  // behaviour is the SDK's, and it is exactly what the other policies exist
  // to avoid.

  testWidgets('Settle.none advances one frame and no clock', (tester) async {
    await tester.pumpWidget(const _Fading());
    var before = tester.widget<Opacity>(find.byType(Opacity)).opacity;

    expect(await Settle.none.apply(tester), isFalse);
    expect(tester.widget<Opacity>(find.byType(Opacity)).opacity, before);
  });

  testWidgets('Settle.frames advances exactly what it says', (tester) async {
    await tester.pumpWidget(const _Fading());

    // Two 100ms frames into a 1s fade.
    expect(await const Settle.frames(2).apply(tester), isFalse);
    expect(
      tester.widget<Opacity>(find.byType(Opacity)).opacity,
      closeTo(0.2, 0.01),
    );
  });
}

class _Still extends StatelessWidget {
  const _Still();

  @override
  Widget build(BuildContext context) =>
      const MaterialApp(home: Scaffold(body: Text('still')));
}

class _Spinner extends StatelessWidget {
  const _Spinner();

  @override
  Widget build(BuildContext context) =>
      const MaterialApp(home: Scaffold(body: CircularProgressIndicator()));
}

/// A one-second fade that starts on its own — a finite animation, so a bounded
/// settle should ride it out.
class _Fading extends StatefulWidget {
  const _Fading();

  @override
  State<_Fading> createState() => _FadingState();
}

class _FadingState extends State<_Fading> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 1),
  )..forward();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      body: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) =>
            Opacity(opacity: _controller.value, child: const Text('fading')),
      ),
    ),
  );
}
