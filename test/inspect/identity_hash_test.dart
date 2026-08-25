import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware/src/inspect/guest_inspect.dart';
import 'package:flutterware/src/inspect/node.dart';

/// Nothing a node carries may be a value the VM assigned per allocation.
///
/// [InspectNode] is read in one process and compared in another, so an
/// identity hash in any field is a difference that is always there and never
/// means anything. It reached the tree by two doors — a widget's key, fused
/// into its description by the framework, and any property that renders an
/// object — and this is the sweep that says both are shut.
void main() {
  final hash = RegExp(r'#[0-9a-f]{5}(?![0-9a-f])');

  InspectTree read(WidgetTester tester) => GuestInspector(
    rootOf: () => tester.binding.rootElement,
    entryIdOf: () => null,
  ).read();

  testWidgets('no field of any node carries one', (tester) async {
    var scroll = ScrollController();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            controller: scroll,
            children: [
              TextField(controller: TextEditingController(text: 'x')),
              AnimatedBuilder(
                animation: scroll,
                builder: (_, _) => const Text('hi'),
              ),
              Form(key: GlobalKey<FormState>(), child: const Text('f')),
              const Placeholder(key: ValueKey('tile')),
            ],
          ),
        ),
      ),
    );

    var offenders = <String>[];
    for (var node in read(tester).nodes) {
      for (var entry in {...node.properties, ...node.textStyle}.entries) {
        if (hash.hasMatch(entry.value)) {
          offenders.add('${node.type}.${entry.key} = ${entry.value}');
        }
      }
      for (var value in [node.description, node.label, node.widgetKey]) {
        if (value != null && hash.hasMatch(value)) {
          offenders.add('${node.type} = $value');
        }
      }
    }

    expect(offenders, isEmpty);
  });

  testWidgets('the object survives, only its allocation goes', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: ListView(controller: ScrollController())),
    );
    var list = read(tester).nodes.firstWhere((it) => it.type == 'ListView');

    expect(list.properties['controller'], startsWith('ScrollController#('));
  });

  // The other half of the bargain: this must not edit the app's own words.
  testWidgets('a hash-shaped string in the UI is left alone', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Text('Order#12345')));
    var text = read(tester).nodes.firstWhere((it) => it.type == 'Text');

    expect(text.description, 'Text("Order#12345")');
    expect(text.properties['data'], '"Order#12345"');
  });

  test('a key whose value merely looks like a hash keeps it', () {
    expect(
      InspectNode.splitKey("Chip-[<'build#a1b2c'>]", 'Chip').key,
      "[<'build#a1b2c'>]",
    );
  });

  test('every shape of value-less key loses its hash', () {
    expect(
      {
        for (var pair in const [
          ('Form-[LabeledGlobalKey<FormState>#acc1d]', 'Form'),
          ('Card-[GlobalKey#04a2f]', 'Card'),
          ('Row-[#a1b2c]', 'Row'),
          ('Tile-[GlobalObjectKey Item#1234f]', 'Tile'),
        ])
          InspectNode.splitKey(pair.$1, pair.$2).key,
      },
      {
        '[LabeledGlobalKey<FormState>#]',
        '[GlobalKey#]',
        '[#]',
        '[GlobalObjectKey Item#]',
      },
    );
  });
}
