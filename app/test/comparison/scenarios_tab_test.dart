import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware_app/src/capture/settle.dart';
import 'package:flutterware_app/src/comparison/channels.dart';
import 'package:flutterware_app/src/comparison/comparison_controller.dart';
import 'package:flutterware_app/src/comparison/frame_ref.dart';
import 'package:flutterware_app/src/comparison/scenario_comparison.dart';
import 'package:flutterware_app/src/comparison/shot_store.dart';
import 'package:flutterware_app/src/comparison/ui/merged_tree.dart';
import 'package:flutterware_app/src/comparison/ui/scenarios_tab.dart';
import 'package:flutterware_app/src/ui/theme.dart';

/// The three verdicts reached **without replaying anything**, which is the
/// state the tab had no drawing for: `items` is empty by design, so the merged
/// tree drew nothing and picking the row looked like a row that would not open.
void main() {
  var settle = SettleRegistry();

  Future<void> pump(
    WidgetTester tester,
    List<ScenarioComparison> scenarios, {
    String? selected,
  }) async {
    var half = ComparisonHalf(
      ComparisonHalfKind.scenarios,
      stage: HalfStage.done,
    );
    for (var scenario in scenarios) {
      half.addScenario(scenario);
    }
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme,
        home: Scaffold(
          body: ScenariosTab(
            half: half,
            store: _NoShots(),
            settle: settle,
            selected: selected,
            onSelect: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a skipped scenario says why there is nothing behind it', (
    tester,
  ) async {
    await pump(tester, [
      const ScenarioComparison.notRun(
        scenario: 'test/cart_test.dart#cart',
        state: ComparedState.skipped,
      ),
    ], selected: 'test/cart_test.dart#cart');

    expect(find.text('Not replayed'), findsOneWidget);
    expect(
      find.textContaining('Nothing that decides its pixels changed'),
      findsOneWidget,
    );
  });

  testWidgets('a scenario only this branch has says so in its own words', (
    tester,
  ) async {
    await pump(tester, [
      const ScenarioComparison.notRun(
        scenario: 'test/cart_test.dart#cart',
        state: ComparedState.added,
      ),
    ], selected: 'test/cart_test.dart#cart');

    expect(find.text('Only on this branch'), findsOneWidget);
  });

  testWidgets('a scenario that was replayed still draws its tree', (
    tester,
  ) async {
    await pump(tester, [
      const ScenarioComparison(
        scenario: 'test/cart_test.dart#cart',
        state: ComparedState.changed,
        items: [ComparedItem(id: 'Cart', state: ComparedState.changed)],
        branches: [],
      ),
    ], selected: 'test/cart_test.dart#cart');

    expect(find.text('Not replayed'), findsNothing);
    expect(find.byKey(mergedTreeKey), findsOneWidget);
  });
}

/// Every frame evicted — the store is not what these tests are about, and a
/// scenario that was never replayed has no frames to open anyway.
class _NoShots implements ShotStore {
  @override
  Future<Shot?> byKey(String key) async => null;

  @override
  Future<Shot?> byRef(FrameRef ref) async => null;
}
