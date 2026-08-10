import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware/src/inspect/guest_inspect.dart';
import 'package:flutterware/src/inspect/node.dart';

/// The properties leg of a node: what the widget's own diagnostics say,
/// filtered to what a detail pane's reader would keep. Measured before being
/// kept — +168µs on the shop tree's 1.5ms read, +6KB on its 37KB JSON — so
/// what these tests pin is the *filter*: the useful survive, the noise and
/// the paragraphs do not.
void main() {
  InspectTree read(WidgetTester tester) => GuestInspector(
    rootOf: () => tester.binding.rootElement,
    entryIdOf: () => null,
  ).read();

  InspectNode node(InspectTree tree, String type) =>
      tree.nodes.firstWhere((n) => n.type == type);

  testWidgets('a widget reports what it was configured with', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Padding(
          padding: EdgeInsets.all(8),
          child: Text('Save', maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ),
    );
    var tree = read(tester);

    expect(node(tree, 'Padding').properties['padding'], 'EdgeInsets.all(8.0)');
    var text = node(tree, 'Text').properties;
    expect(text['data'], '"Save"');
    expect(text['maxLines'], '1');
    expect(text['overflow'], 'ellipsis');
    expect(
      text.containsKey('inherit'),
      isFalse,
      reason: 'the resting state of every style distinguishes no node',
    );
  });

  testWidgets('a paragraph of a value is elided, not carried', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Tooltip(
          message: 'a' * 400,
          child: const SizedBox(width: 10, height: 10),
        ),
      ),
    );
    var tree = read(tester);

    var message = node(tree, 'Tooltip').properties['message']!;
    expect(message.length, lessThan(100));
    expect(message, contains('…'));
  });

  testWidgets('the flag survives the wire', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Padding(padding: EdgeInsets.all(8))),
    );
    var decoded = InspectTree.fromJson(read(tester).toJson());
    expect(
      node(decoded, 'Padding').properties['padding'],
      'EdgeInsets.all(8.0)',
    );
  });
}
