import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: implementation_imports
import 'package:flutterware/src/inspect/node.dart';
import 'package:flutterware/plugins.dart' show Address;
import 'package:flutterware_app/src/address/address_scope.dart';
import 'package:flutterware_app/src/inspect/elements_view.dart';
import 'package:flutterware_app/src/ui/theme.dart';

/// What the tree pane opens on.
///
/// It used to open on the raw tree, which in a real app is a dozen or more
/// wrappers before the first widget anybody wrote — while the drive verbs had
/// been handing agents a filtered tree since the noise filter landed. Two
/// surfaces, one app, two different shapes. These pin the pane to the agent's
/// reading, and pin the way back.
void main() {
  /// A button under the kind of scaffolding a real tree carries: each wrapper
  /// shares its only child's box, which is exactly what the filter drops.
  InspectNode fixture() => InspectTree.fromJson({
    'root': {
      'id': '',
      'type': 'MaterialApp',
      'layout': {'x': 0, 'y': 0, 'width': 400, 'height': 800},
      'children': [
        {
          'id': '0',
          'type': 'MouseRegion',
          'layout': {'x': 0, 'y': 0, 'width': 400, 'height': 800},
          'children': [
            {
              'id': '0/0',
              'type': 'GestureDetector',
              'layout': {'x': 0, 'y': 0, 'width': 400, 'height': 800},
              'children': [
                {
                  'id': '0/0/0',
                  'type': 'ElevatedButton',
                  'label': 'Pay',
                  // Its own box, unlike the wrappers above it — which is
                  // precisely what makes them wrappers and it a widget.
                  'layout': {'x': 0, 'y': 40, 'width': 200, 'height': 48},
                },
              ],
            },
          ],
        },
      ],
    },
  }).root!;

  Widget host(InspectNode root) {
    var address = ValueNotifier(Address(worktree: 'wt'));
    return MaterialApp(
      theme: appTheme,
      home: AddressRoot(
        address: address,
        onChanged: (a) => address.value = a,
        child: Scaffold(
          body: ElementsView(
            root: root,
            placeholder: 'nothing',
            highlight: ValueNotifier<String?>(null),
            displayRoot: '/tmp',
            readsWidgets: true,
          ),
        ),
      ),
    );
  }

  testWidgets('the wrappers are hidden, and the count says how many', (
    tester,
  ) async {
    await tester.pumpWidget(host(fixture()));
    await tester.pumpAndSettle();

    expect(find.text('ElevatedButton'), findsOneWidget);
    expect(find.text('MouseRegion'), findsNothing);
    expect(find.text('GestureDetector'), findsNothing);
    expect(find.textContaining('wrappers hidden'), findsOneWidget);
  });

  testWidgets('Show all brings them back, and the label inverts', (
    tester,
  ) async {
    await tester.pumpWidget(host(fixture()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Show all'));
    await tester.pumpAndSettle();

    expect(find.text('MouseRegion'), findsOneWidget);
    expect(find.text('GestureDetector'), findsOneWidget);
    expect(find.textContaining('wrappers shown'), findsOneWidget);

    await tester.tap(find.text('Hide'));
    await tester.pumpAndSettle();
    expect(find.text('MouseRegion'), findsNothing);
  });

  testWidgets('a tree with nothing to drop offers no toggle at all', (
    tester,
  ) async {
    var bare = InspectTree.fromJson({
      'root': {
        'id': '',
        'type': 'ElevatedButton',
        'label': 'Pay',
        'layout': {'x': 0, 'y': 0, 'width': 400, 'height': 800},
      },
    }).root!;

    await tester.pumpWidget(host(bare));
    await tester.pumpAndSettle();

    expect(find.textContaining('wrappers'), findsNothing);
  });
}
