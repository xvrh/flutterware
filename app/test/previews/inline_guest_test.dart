import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware/plugins.dart';
import 'package:flutterware/previews.dart';
import 'package:flutterware/previews_guest.dart';
import 'package:flutterware_app/src/previews/catalog_entry.dart';
import 'package:flutterware_app/src/previews/catalog_session.dart';
import 'package:flutterware_app/src/previews/catalog_view.dart';
import 'package:flutterware_app/src/previews/inline_guest.dart';
import 'package:flutterware_app/src/address/address_scope.dart';
import 'package:flutterware_app/src/ui/aside.dart';

/// The previews panel over a guest drawn **inside** the test — no daemon, no
/// embedder process. The entry is a real widget with a real knob; the stage
/// draws it, the inspector walks it, a point finds a node in it, and a knob
/// set through the address rebuilds it. Every one of those reaches the guest
/// through the same two seams the embedder guest uses — `GuestSurface` for
/// the picture and `GuestChannel` for the extensions — which is what makes a
/// browser, where no process can be spawned, the same panel.
void main() {
  const alpha = CatalogEntry(
    path: 'demo/a.dart',
    symbol: 'alpha',
    annotation: "Preview(name: 'Alpha')",
    name: 'Alpha',
  );

  CatalogEntryBuilder? entryOf(String id) => id == alpha.id
      ? (preview: const Preview(name: 'Alpha'), builder: () => const _Alpha())
      : null;

  late ValueNotifier<Address> address;

  Future<CatalogSession> pumpInline(WidgetTester tester) async {
    installInlineGuest(ids: () => [alpha.id]);
    var session = CatalogSession(
      appPackageRoot: '/app',
      flutterSdkRoot: '/sdk',
      projectRoot: '/project',
    )..entries = [alpha];
    addTearDown(session.dispose);
    session.debugInstallGuest(
      InlineGuestSurface(
        root: CatalogHost(fileEntryId: alpha.id, entryOf: entryOf),
      ),
      InProcessGuestChannel(),
      entry: alpha,
    );
    address = ValueNotifier(
      Address(worktree: 'test', plugin: 'flutterware.previews'),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: AddressRoot(
          address: address,
          onChanged: (next) => address.value = next,
          child: AsideScope(
            aside: AsideVisibility(
              railVisible: () => true,
              setRailVisible: (_) {},
            ),
            child: Scaffold(body: CatalogView(session: session)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return session;
  }

  testWidgets('the stage draws the entry', (tester) async {
    await pumpInline(tester);
    expect(find.text('Hello'), findsOneWidget);
  });

  testWidgets('the inspector walks the entry in this process', (tester) async {
    var session = await pumpInline(tester);
    await session.readTree();
    await tester.pump();
    var tree = session.treeForSelection;
    expect(tree, isNotNull);
    expect(
      tree!.nodes.map((n) => n.type),
      contains('_Alpha'),
      reason: 'the walk starts at the demo root, not at the studio',
    );
    expect(tree.nodes.map((n) => n.type), isNot(contains('CatalogView')));
  });

  testWidgets('a point finds a node', (tester) async {
    var session = await pumpInline(tester);
    await session.readTree();
    await tester.pump();
    var text = tester.getCenter(find.text('Hello'));
    var picture = tester.getTopLeft(find.byType(InlineGuestPicture));
    var id = await session.nodeUnder(
      text.dx - picture.dx,
      text.dy - picture.dy,
    );
    expect(id, isNotNull);
    expect(session.treeForSelection!.nodeAt(id!)!.type, 'Text');
  });

  testWidgets('a knob set through the address rebuilds the entry', (
    tester,
  ) async {
    await pumpInline(tester);
    address.value = address.value.copyWith(axes: {'knob.label': 'Bye'});
    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('Bye'), findsOneWidget);
    expect(find.text('Hello'), findsNothing);
  });
}

class _Alpha extends StatelessWidget {
  const _Alpha();

  @override
  Widget build(BuildContext context) {
    var label = context.knobs.string('label', 'Hello');
    return Center(child: Text(label));
  }
}
