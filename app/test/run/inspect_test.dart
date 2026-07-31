import 'package:flutterware_app/src/run/inspect.dart';
import 'package:test/test.dart';

/// A node shaped the way `ext.flutter.inspector.getRootWidgetTree` shapes them.
Map<String, Object?> node(
  String type, {
  String? description,
  String? file,
  int line = 1,
  int column = 1,
  bool local = true,
  String? preview,
  List<Map<String, Object?>> children = const [],
}) => {
  'description': description ?? type,
  'widgetRuntimeType': type,
  'createdByLocalProject': local,
  'textPreview': ?preview,
  if (file != null)
    'creationLocation': {'file': file, 'line': line, 'column': column},
  if (children.isNotEmpty) 'children': children,
};

void main() {
  test('ids are the child-index path, not the inspector own ids', () {
    var tree = RunInspector.convertNode({
      ...node(
        'RootWidget',
        children: [
          node(
            'MyApp',
            children: [
              node('Left'),
              node('Right', children: [node('Deep')]),
            ],
          ),
        ],
      ),
      // Present in the real payload and deliberately ignored: it is minted per
      // object group and dies with it.
      'valueId': 'inspector-0',
    }, '');

    expect([for (var n in _walk(tree)) n.id], ['', '0', '0/0', '0/1', '0/1/0']);
    expect(
      [for (var n in _walk(tree)) n.type],
      ['RootWidget', 'MyApp', 'Left', 'Right', 'Deep'],
    );
  });

  test('carries the creation location, which is what survives a relaunch', () {
    var tree = RunInspector.convertNode(
      node('Text', file: 'file:///p/lib/main.dart', line: 66, column: 11),
      '0',
    );

    expect(tree.source!.line, 66);
    expect(tree.source!.column, 11);
    expect(tree.source!.describe(relativeTo: '/p'), 'lib/main.dart:66:11');
  });

  test('a description that only repeats the type is dropped', () {
    expect(RunInspector.convertNode(node('Padding'), '').description, isNull);
    expect(
      RunInspector.convertNode(
        node('SizedBox', description: 'SizedBox(width: 8.0)'),
        '',
      ).description,
      'SizedBox(width: 8.0)',
    );
  });

  test('a text preview becomes the description', () {
    expect(
      RunInspector.convertNode(node('Text', preview: 'Save'), '').description,
      'Text("Save")',
    );
  });

  test('marks whose code it is', () {
    expect(
      RunInspector.convertNode(node('MyApp'), '').createdByLocalProject,
      isTrue,
    );
    expect(
      RunInspector.convertNode(
        node('RootWidget', local: false),
        '',
      ).createdByLocalProject,
      isFalse,
    );
  });

  test('leaves layout null — the VM service has no position to give', () {
    // Not an oversight and worth pinning: `getLayoutExplorerNode` answers with
    // a size and no offset, so cropping and annotating need the guest runtime.
    var tree = RunInspector.convertNode(
      node('Scaffold', children: [node('Text')]),
      '',
    );
    expect([for (var n in _walk(tree)) n.layout], everyElement(isNull));
  });

  test('a node with nothing in it still converts', () {
    var empty = RunInspector.convertNode(const {}, '');
    expect(empty.id, '');
    expect(empty.type, '');
    expect(empty.children, isEmpty);
    expect(empty.source, isNull);
  });

  test('a child that is not a map is skipped rather than fatal', () {
    var tree = RunInspector.convertNode({
      ...node('Root'),
      'children': [node('Kept'), 'nonsense', 42],
    }, '');

    expect([for (var n in tree.children) n.type], ['Kept']);
  });
}

Iterable<T> _walk<T>(T node) sync* {
  yield node;
  for (var child in (node as dynamic).children as List) {
    yield* _walk(child as T);
  }
}
