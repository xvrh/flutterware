import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware_app/src/launcher_icon/model/scan.dart';
import 'package:flutterware_app/src/launcher_icon/ui/flavor_chips.dart';
import 'package:flutterware_app/src/ui/theme.dart';

/// The row that says which flavors there are and which are worth opening.
void main() {
  Future<void> pump(
    WidgetTester tester,
    List<IconFlavor> flavors, {
    String? selected,
  }) => tester.pumpWidget(
    MaterialApp(
      theme: appTheme,
      home: Scaffold(
        body: FlavorChips(flavors: flavors, selected: selected),
      ),
    ),
  );

  IconFlavor flavor(String name, Set<IconFlavorSource> sources) =>
      IconFlavor(name, sources);

  testWidgets('the default leads, whatever the flavors are called', (
    tester,
  ) async {
    await pump(tester, [
      flavor('alpha', {IconFlavorSource.androidSourceSet}),
    ]);

    var texts = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.textSpan?.toPlainText() ?? t.data)
        .toList();
    expect(texts.first, 'main');
  });

  testWidgets('a flavor with nothing generated says so on the chip', (
    tester,
  ) async {
    // Not a border treatment: the first attempt muted the label and thinned
    // the border, and in a rendering of the row it was indistinguishable from
    // the chip beside it.
    await pump(tester, [
      flavor('dev', {IconFlavorSource.config}),
      flavor('prod', IconFlavorSource.values.toSet()),
    ]);

    expect(find.textContaining('not generated'), findsOneWidget);
    expect(
      tester
          .widget<Text>(find.textContaining('not generated'))
          .textSpan!
          .toPlainText(),
      contains('dev'),
    );
    expect(find.textContaining('prod'), findsOneWidget);
    expect(
      tester.widget<Text>(find.textContaining('prod')).textSpan!.toPlainText(),
      isNot(contains('not generated')),
    );
  });

  testWidgets('only an incomplete flavor gets a tooltip', (tester) async {
    await pump(tester, [
      flavor('whole', IconFlavorSource.values.toSet()),
      flavor('half', {
        IconFlavorSource.config,
        IconFlavorSource.androidSourceSet,
      }),
    ]);

    expect(find.byType(Tooltip), findsOneWidget);
    expect(
      tester.widget<Tooltip>(find.byType(Tooltip)).message,
      contains('AppIcon-half.appiconset'),
    );
  });

  group('the hint', () {
    test('names the missing platform, one or the other', () {
      expect(
        flavorHint(
          flavor('a', {
            IconFlavorSource.config,
            IconFlavorSource.androidSourceSet,
          }),
        ),
        contains('no AppIcon-a.appiconset'),
      );
      expect(
        flavorHint(
          flavor('b', {IconFlavorSource.config, IconFlavorSource.iosCatalog}),
        ),
        contains('no android/app/src/b/'),
      );
    });

    test('is silent for a flavor that is entirely there', () {
      expect(flavorHint(flavor('c', IconFlavorSource.values.toSet())), isNull);
    });

    test('sends an unbuilt flavor to the config it does have', () {
      expect(
        flavorHint(flavor('d', {IconFlavorSource.config})),
        contains('flutter_launcher_icons-d.yaml'),
      );
    });
  });
}
