import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware_app/src/ui/action_button.dart';
import 'package:flutterware_app/src/ui/theme.dart';

/// The button's whole contribution is *timing*, so that is what is asserted.
///
/// A press that ran the work and returned to idle within a frame would satisfy
/// any test written against the callback alone, and would be exactly the button
/// this replaces — the one that did its job and looked like it had done nothing.
void main() {
  Future<void> mount(
    WidgetTester tester,
    Future<void> Function()? onPressed,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme,
        home: Scaffold(
          body: Center(
            child: FwActionButton(label: 'Reload', onPressed: onPressed),
          ),
        ),
      ),
    );
  }

  testWidgets('holds a running state even when the work is instant', (
    tester,
  ) async {
    var runs = 0;
    await mount(tester, () async => runs++);

    await tester.tap(find.byType(FwActionButton));
    await tester.pump();

    // The work is already done — and the button still says so, because 40ms of
    // "Reload…" is a dropped frame rather than an acknowledgement.
    expect(runs, 1);
    expect(find.text('Reload…'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Done'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 1500));
    expect(find.text('Reload'), findsOneWidget);
  });

  testWidgets('does not delay work that outlasts the floor', (tester) async {
    var completer = Completer<void>();
    await mount(tester, () => completer.future);

    await tester.tap(find.byType(FwActionButton));
    await tester.pump(const Duration(milliseconds: 900));
    // Well past the floor, and still running — the floor is a minimum, not an
    // addition.
    expect(find.text('Reload…'), findsOneWidget);

    completer.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Done'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 1500));
  });

  testWidgets("keeps a failure up, in the error's own words", (tester) async {
    await mount(
      tester,
      () async => throw StateError('flutter_native_splash.yaml:4:3'),
    );

    await tester.tap(find.byType(FwActionButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Failed'), findsOneWidget);

    // Far longer than a success would last. A failure that timed out is a
    // failure nobody read.
    await tester.pump(const Duration(seconds: 5));
    expect(find.text('Failed'), findsOneWidget);

    var tooltip = tester.widget<Tooltip>(find.byType(Tooltip));
    expect(tooltip.message, contains('flutter_native_splash.yaml:4:3'));
  });

  testWidgets('a second press while running starts nothing', (tester) async {
    var runs = 0;
    var completer = Completer<void>();
    await mount(tester, () {
      runs++;
      return completer.future;
    });

    await tester.tap(find.byType(FwActionButton));
    await tester.pump();
    await tester.tap(find.byType(FwActionButton));
    await tester.pump();

    expect(runs, 1);

    completer.complete();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 1500));
  });

  testWidgets('a null callback is the disabled state', (tester) async {
    await mount(tester, null);
    await tester.tap(find.byType(FwActionButton));
    await tester.pump();
    expect(find.text('Reload'), findsOneWidget);
    expect(find.text('Reload…'), findsNothing);
  });
}
