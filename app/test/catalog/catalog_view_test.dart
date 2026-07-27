import 'package:device_frame/device_frame.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware/ui_catalog.dart';
import 'package:flutterware_app/src/catalog/catalog_entry.dart';
import 'package:flutterware_app/src/catalog/catalog_session.dart';
import 'package:flutterware_app/src/catalog/catalog_view.dart';
import 'package:flutterware_app/src/catalog/protocol.dart';

/// What the panel does when a demo stops compiling.
///
/// Reachable without a guest because a broken selection renders the error
/// instead of the texture — which is the behaviour under test.
void main() {
  const alpha = CatalogEntry(
    path: 'demo/a.dart',
    symbol: 'alpha',
    annotation: "Demo(name: 'Alpha')",
    name: 'Alpha',
  );
  const beta = CatalogEntry(
    path: 'demo/b.dart',
    symbol: 'beta',
    annotation: "Demo(name: 'Beta')",
    name: 'Beta',
  );
  const gamma = CatalogEntry(
    path: 'demo/c.dart',
    symbol: 'gamma',
    annotation: "Demo(name: 'Gamma')",
    name: 'Gamma',
  );

  CatalogSession sessionOf(
    List<CatalogEntry> all,
    CatalogEntry broken,
    String error,
  ) {
    return CatalogSession(
        appPackageRoot: '/app',
        flutterSdkRoot: '/sdk',
        projectRoot: '/project',
      )
      ..phase = CatalogSessionPhase.ready
      ..entries = [
        for (var e in all)
          if (e.id != broken.id) e,
      ]
      ..quarantined = [QuarantinedEntry(entry: broken, error: error)]
      ..selected = broken
      ..active = all.first;
  }

  // Every case here keeps one entry broken and selected: that is what renders
  // the error page instead of the guest's texture, which no widget test has.
  CatalogSession sessionWithBroken(CatalogEntry broken, String error) =>
      sessionOf([alpha, beta, gamma], broken, error);

  Future<void> pump(WidgetTester tester, CatalogSession session) =>
      tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: CatalogView(session: session)),
        ),
      );

  testWidgets('a broken entry keeps its place in the tree', (tester) async {
    var session = sessionWithBroken(beta, 'boom');
    await pump(tester, session);

    // Ordered by where they sit on screen, which is the claim: a demo that
    // stops compiling does not move.
    double y(String name) => tester.getTopLeft(find.text(name)).dy;
    expect(y('Alpha'), lessThan(y('Beta')));
    expect(y('Beta'), lessThan(y('Gamma')));
  });

  testWidgets('a broken entry stays tappable, because that is the retry', (
    tester,
  ) async {
    var session = sessionWithBroken(beta, 'boom');
    await pump(tester, session);

    var row = tester.widget<InkWell>(
      find
          .ancestor(of: find.text('Beta'), matching: find.byType(InkWell))
          .first,
    );
    expect(row.onTap, isNotNull);
  });

  testWidgets('the filter narrows the tree', (tester) async {
    var session = sessionWithBroken(beta, 'boom');
    await pump(tester, session);

    session.browsing.filter = 'alp';
    await tester.pump();

    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Beta'), findsNothing);
    expect(find.text('Gamma'), findsNothing);
  });

  testWidgets('a filter that matches nothing says so', (tester) async {
    var session = sessionWithBroken(beta, 'boom');
    await pump(tester, session);

    session.browsing.filter = 'zzz';
    await tester.pump();

    expect(find.text('Nothing matches'), findsOneWidget);
  });

  testWidgets('folders fold', (tester) async {
    const one = CatalogEntry(
      path: 'demo/team/one.dart',
      symbol: 'one',
      annotation: 'Demo()',
      name: 'One',
    );
    const two = CatalogEntry(
      path: 'demo/billing/two.dart',
      symbol: 'two',
      annotation: 'Demo()',
      name: 'Two',
    );
    var session = sessionOf([one, two, beta], beta, 'boom');
    await pump(tester, session);
    expect(find.text('One'), findsOneWidget);

    await tester.tap(find.text('team'));
    await tester.pump();
    expect(find.text('One'), findsNothing);
    expect(find.text('team'), findsOneWidget, reason: 'the folder remains');
    expect(find.text('Two'), findsOneWidget, reason: 'its neighbour is intact');
  });

  testWidgets('hiding the list leaves the way back', (tester) async {
    var session = sessionWithBroken(beta, 'boom');
    await pump(tester, session);

    await tester.tap(find.byTooltip('Hide the list'));
    await tester.pump();
    expect(find.text('Alpha'), findsNothing);

    await tester.tap(find.byTooltip('Show the list'));
    await tester.pump();
    expect(find.text('Alpha'), findsOneWidget);
  });

  testWidgets('the compiler error is shown where the widget would be', (
    tester,
  ) async {
    var session = sessionWithBroken(
      beta,
      "demo/b.dart:3:7: Error: The method 'Nope' isn't defined.",
    );
    await pump(tester, session);

    expect(find.text('Beta doesn’t compile'), findsOneWidget);
    expect(
      find.text('demo/b.dart · beta'),
      findsOneWidget,
      reason: 'the header says which file to go and fix',
    );
    // The error is selectable, so it is both a Text and the EditableText
    // underneath it — what matters is that the compiler's own words are on
    // screen rather than a summary of them.
    expect(
      find.textContaining("The method 'Nope' isn't defined"),
      findsAtLeastNWidgets(1),
    );
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('the status bar keeps its height when a switch fails', (
    tester,
  ) async {
    var session = sessionWithBroken(beta, 'boom');
    await pump(tester, session);
    var bar = find
        .ancestor(
          of: find.byIcon(Icons.refresh),
          matching: find.byType(Container),
        )
        .last;
    var idle = tester.getSize(bar);
    expect(idle.height, 32);

    // A failure used to add a button to the row, and the button was taller
    // than the text it stood next to.
    session
      ..lastSwitch = SwitchReport(
        entry: beta,
        compile: const Duration(milliseconds: 1234),
        reload: Duration.zero,
        newSourceCount: 0,
        editedCount: 1,
        reloaded: true,
        error: 'boom',
      )
      ..notifyListeners();
    await tester.pump();

    expect(tester.getSize(bar), idle);
  });

  testWidgets('the filter field keeps its height as you type', (tester) async {
    var session = sessionWithBroken(beta, 'boom');
    await pump(tester, session);
    var field = find.byType(TextField);
    var empty = tester.getSize(field);

    // The clear button appears with the first character, and an
    // InputDecorator sizes itself around its icons.
    await tester.enterText(field, 'a');
    await tester.pump();

    expect(tester.getSize(field), empty);
  });

  testWidgets('a filtered row marks what matched', (tester) async {
    var session = sessionWithBroken(beta, 'boom');
    await pump(tester, session);
    session.browsing.filter = 'lph';
    await tester.pump();

    var marked = tester.widget<Text>(
      find
          .ancestor(
            of: find.text('Alpha', findRichText: true),
            matching: find.byType(Text),
          )
          .first,
    );
    var spans = (marked.textSpan! as TextSpan).children!.cast<TextSpan>();
    expect(spans.map((s) => s.text), ['A', 'lph', 'a']);
    expect(
      spans[1].style?.backgroundColor,
      isNotNull,
      reason: 'the matched run is the highlighted one',
    );
    expect(spans[0].style?.backgroundColor, isNull);
  });

  testWidgets('the busy dot waits before it shows itself', (tester) async {
    // Driven directly: what is under test is the timing, and a switch that
    // lands inside the delay must never show anything — a 90ms compile that
    // blinks at you reads as a fault, not as progress.
    Future<void> show(String? busy) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: BusyDot(busy: busy)),
        ),
      );
    }

    double opacity() =>
        tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity;

    await show(null);
    expect(opacity(), 0);

    await show('compiling');
    expect(opacity(), 0);
    await tester.pump(const Duration(milliseconds: 100));
    expect(opacity(), 0, reason: 'a warm switch is over before this');

    await tester.pump(const Duration(milliseconds: 200));
    expect(opacity(), 1);

    await show(null);
    expect(opacity(), 0);
    await tester.pumpAndSettle();
  });

  testWidgets('a folded folder still shows what is selected', (tester) async {
    const inFolder = CatalogEntry(
      path: 'demo/team/one.dart',
      symbol: 'one',
      annotation: 'Demo()',
      name: 'One',
    );
    var session = sessionOf([inFolder, alpha], inFolder, 'boom');
    await pump(tester, session);

    await tester.tap(find.text('team'));
    await tester.pump();
    expect(
      find.text('One'),
      findsOneWidget,
      reason: 'folding away the selection would hide where you are',
    );
    // The fold is remembered, not refused: its neighbours are still folded.
    expect(session.browsing.isOpen('/team'), isFalse);
  });

  testWidgets('one button folds everything, then unfolds it', (tester) async {
    const one = CatalogEntry(
      path: 'demo/team/one.dart',
      symbol: 'one',
      annotation: 'Demo()',
      name: 'One',
    );
    var session = sessionOf([one, beta], beta, 'boom');
    await pump(tester, session);
    expect(find.text('One'), findsOneWidget);

    await tester.tap(find.byTooltip('Collapse all'));
    await tester.pump();
    expect(find.text('One'), findsNothing);

    await tester.tap(find.byTooltip('Expand all'));
    await tester.pump();
    expect(find.text('One'), findsOneWidget);
  });

  group('the top bar', () {
    testWidgets('starts on Fit, and says nothing else', (tester) async {
      await pump(tester, sessionWithBroken(beta, 'boom'));

      expect(find.text('Fit'), findsOneWidget);
      expect(
        find.byTooltip('Hide the frame'),
        findsNothing,
        reason: 'there is no frame to hide until there is a device',
      );
    });

    testWidgets('picking a device sizes the guest to its screen', (
      tester,
    ) async {
      var session = sessionWithBroken(beta, 'boom');
      await pump(tester, session);

      await tester.tap(find.text('Fit'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('iPhone 13').last);
      await tester.pumpAndSettle();

      expect(session.staging.device?.name, isNotNull);
      // The screen in logical pixels, which is the number a layout is written
      // against — not the physical one the guest is actually rendering.
      expect(find.text('390×844'), findsOneWidget);
      expect(find.text('iPhone 13'), findsOneWidget);
    });

    testWidgets('the frame can be taken off once there is one', (tester) async {
      var session = sessionWithBroken(beta, 'boom');
      session.staging.device = Devices.ios.iPhone13;
      await pump(tester, session);

      await tester.tap(find.byTooltip('Hide the frame'));
      await tester.pump();

      expect(session.staging.frameVisible, isFalse);
      expect(find.byTooltip('Show the frame'), findsOneWidget);
    });
  });

  group('the form factor', () {
    test('mobile and desktop each pick a device, all picks none', () {
      var staging = CatalogStaging()..followEntry('mobile');
      expect(staging.device?.screenSize, const Size(390, 844));

      staging.followEntry('desktop');
      expect(staging.device?.identifier.platform, TargetPlatform.macOS);

      staging.followEntry('all');
      expect(staging.device, isNull, reason: 'all is an entry with no opinion');
    });

    test('an entry that says nothing leaves the choice alone', () {
      var staging = CatalogStaging()..device = Devices.ios.iPad;
      staging.followEntry(null);
      expect(staging.device?.identifier, Devices.ios.iPad.identifier);
    });
  });

  group('the knob panel', () {
    KnobReport report(List<KnobDescriptor> knobs) =>
        KnobReport(entryId: beta.id, knobs: knobs);

    testWidgets('is absent when the entry declares none', (tester) async {
      await pump(tester, sessionWithBroken(beta, 'boom'));
      expect(find.byType(Slider), findsNothing);
      expect(find.byType(Switch), findsNothing);
    });

    testWidgets('renders a control per kind', (tester) async {
      var session = sessionWithBroken(beta, 'boom')
        ..knobs = report(const [
          KnobDescriptor(
            name: 'label',
            kind: KnobKind.string,
            value: 'Hello',
            defaultValue: 'Hello',
          ),
          KnobDescriptor(
            name: 'count',
            kind: KnobKind.integer,
            value: 2,
            defaultValue: 2,
            min: 0,
            max: 9,
          ),
          KnobDescriptor(
            name: 'dense',
            kind: KnobKind.boolean,
            value: false,
            defaultValue: false,
          ),
        ]);
      await pump(tester, session);

      expect(find.text('label'), findsOneWidget);
      expect(find.text('count'), findsOneWidget);
      expect(find.text('dense'), findsOneWidget);
      // Bounded, so it slides; the value reads out beside it.
      expect(find.byType(Slider), findsOneWidget);
      expect(find.byType(Switch), findsOneWidget);
    });

    testWidgets('a number with no bounds is a field, not a slider', (
      tester,
    ) async {
      var session = sessionWithBroken(beta, 'boom')
        ..knobs = report(const [
          KnobDescriptor(
            name: 'ratio',
            kind: KnobKind.number,
            value: 1.5,
            defaultValue: 1.5,
          ),
        ]);
      await pump(tester, session);

      expect(find.byType(Slider), findsNothing);
      expect(find.text('1.5'), findsOneWidget);
    });

    testWidgets('a knob that has moved is legible against one that has not', (
      tester,
    ) async {
      var session = sessionWithBroken(beta, 'boom')
        ..knobs = report(const [
          KnobDescriptor(
            name: 'moved',
            kind: KnobKind.string,
            value: 'changed',
            defaultValue: 'Hello',
          ),
          KnobDescriptor(
            name: 'resting',
            kind: KnobKind.string,
            value: 'Hello',
            defaultValue: 'Hello',
          ),
        ]);
      await pump(tester, session);

      Color colorOf(String name) =>
          tester.widget<Text>(find.text(name)).style!.color!;
      expect(colorOf('moved'), isNot(colorOf('resting')));
    });

    testWidgets('a field keeps what you typed when another knob moves', (
      tester,
    ) async {
      // The panel rebuilds whenever any knob changes — a slider settling, a
      // value read back from the guest — and a field that rebuilt its own
      // controller would throw away the half-typed number sitting in it.
      var session = sessionWithBroken(beta, 'boom')
        ..knobs = report(const [
          KnobDescriptor(
            name: 'ratio',
            kind: KnobKind.number,
            value: 1.5,
            defaultValue: 1.5,
          ),
          KnobDescriptor(
            name: 'dense',
            kind: KnobKind.boolean,
            value: false,
            defaultValue: false,
          ),
        ]);
      await pump(tester, session);

      await tester.enterText(find.widgetWithText(TextField, '1.5'), '12');
      session.knobs = report(const [
        KnobDescriptor(
          name: 'ratio',
          kind: KnobKind.number,
          value: 1.5,
          defaultValue: 1.5,
        ),
        KnobDescriptor(
          name: 'dense',
          kind: KnobKind.boolean,
          value: true,
          defaultValue: false,
        ),
      ]);
      await pump(tester, session);

      expect(find.text('12'), findsOneWidget);
    });
  });
}
