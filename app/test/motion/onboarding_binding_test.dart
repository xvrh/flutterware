import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../tool/catalog/demos/onboarding_page.dart';
import '../../tool/catalog/demos/onboarding_wave.dart';

/// The differentiator, asserted rather than eyeballed: a real, validating
/// `TextFormField` bound into a slot stays fully live **while the scene is
/// mid-animation**.
///
/// This is the thing Lottie and Rive structurally cannot do, so it is the one
/// claim worth a test rather than a screenshot.
void main() {
  Widget page(double progress, {required Widget action}) => MaterialApp(
    theme: ThemeData.dark(useMaterial3: true),
    home: Scaffold(
      backgroundColor: const Color(0xFF0C0913),
      body: OnboardingPage(
        progress: progress,
        // Settled: the headline is at its reading position, so the layout
        // assertion below is about the entrance and not about the pass.
        travel: 0,
        accent: const Color(0xFFB980FF),
        image: const AuroraImage(seed: 1, accent: Color(0xFFB980FF)),
        titleLeft: 'Start your',
        titleRight: 'ritual',
        subtitle: 'One account keeps everything in sync.',
        action: action,
      ),
    ),
  );

  testWidgets('a bound field takes focus and text mid-entrance', (
    tester,
  ) async {
    var controller = TextEditingController();
    addTearDown(controller.dispose);
    var form = GlobalKey<FormState>();

    // 0.4: the action is at ~6% of its own segment, so it is still
    // translated, still scaled down and still partly transparent.
    await tester.pumpWidget(
      page(
        0.4,
        action: Form(
          key: form,
          child: TextFormField(
            controller: controller,
            validator: (value) =>
                (value ?? '').contains('@') ? null : 'Enter your email',
          ),
        ),
      ),
    );

    expect(
      tester
          .widget<Opacity>(
            find
                .ancestor(
                  of: find.byType(TextFormField),
                  matching: find.byType(Opacity),
                )
                .first,
          )
          .opacity,
      lessThan(1),
      reason: 'the field should be mid-fade, or this proves nothing',
    );

    await tester.tap(find.byType(TextFormField));
    await tester.pump();
    expect(
      tester.testTextInput.isRegistered,
      isTrue,
      reason: 'a transformed, half-faded field must still take focus',
    );

    await tester.enterText(find.byType(TextFormField), 'nope');
    await tester.pump();
    expect(controller.text, 'nope');

    expect(form.currentState!.validate(), isFalse);
    await tester.pump();
    expect(find.text('Enter your email'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField), 'me@example.com');
    await tester.pump();
    expect(form.currentState!.validate(), isTrue);
  });

  testWidgets('an entrance never changes layout, only paint', (tester) async {
    Size titleSize() => tester.getSize(
      find
          .ancestor(of: find.text('ritual'), matching: find.byType(FittedBox))
          .first,
    );

    await tester.pumpWidget(page(0.15, action: const SizedBox(height: 52)));
    var early = titleSize();

    await tester.pumpWidget(page(1, action: const SizedBox(height: 52)));
    var settled = titleSize();

    // The halves are 120px apart at the start and touching at the end, and the
    // row's width does not change by a pixel — because `MotionBox` moves things
    // with `Transform`, which paints elsewhere without laying out elsewhere.
    //
    // That is what makes auto-fit safe: the fit is computed once, so a
    // shrink-to-fit headline does not breathe through its own entrance.
    expect(settled, early);
  });
}
