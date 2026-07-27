import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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

  CatalogSession sessionWithBroken(CatalogEntry broken, String error) {
    return CatalogSession(
        appPackageRoot: '/app',
        flutterSdkRoot: '/sdk',
        projectRoot: '/project',
      )
      ..phase = CatalogSessionPhase.ready
      ..entries = [
        for (var e in [alpha, beta, gamma])
          if (e.id != broken.id) e,
      ]
      ..quarantined = [QuarantinedEntry(entry: broken, error: error)]
      ..selected = broken
      ..active = alpha;
  }

  Future<void> pump(WidgetTester tester, CatalogSession session) =>
      tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: CatalogView(session: session)),
        ),
      );

  testWidgets('a broken entry keeps its place in the list', (tester) async {
    var session = sessionWithBroken(beta, 'boom');
    await pump(tester, session);

    var names = tester
        .widgetList<ListTile>(find.byType(ListTile))
        .map((tile) => ((tile.title as Text?)!).data)
        .toList();
    expect(names, ['Alpha', 'Beta', 'Gamma']);
  });

  testWidgets('a broken entry stays selected and stays tappable', (
    tester,
  ) async {
    var session = sessionWithBroken(beta, 'boom');
    await pump(tester, session);

    var tile = tester.widget<ListTile>(
      find.ancestor(of: find.text('Beta'), matching: find.byType(ListTile)),
    );
    expect(
      tile.selected,
      isTrue,
      reason: 'the entry you asked for is selected',
    );
    expect(tile.enabled, isTrue);
    expect(tile.onTap, isNotNull, reason: 'selecting it again is the retry');
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
}
