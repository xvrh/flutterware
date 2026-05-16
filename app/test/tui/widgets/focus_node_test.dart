import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware_app/src/tui/tui.dart';

void main() {
  test('a node parented under a scope reports that scope as enclosingScope',
      () {
    var scope = FocusScopeNode();
    var node = FocusNode();
    scope.debugAttachChild(node);
    expect(node.enclosingScope, scope);
    expect(node.nearestScope, scope);
    expect(scope.nearestScope, scope);
  });

  test('descendants yields the whole subtree', () {
    var scope = FocusScopeNode();
    var a = FocusNode();
    var b = FocusNode();
    scope.debugAttachChild(a);
    scope.debugAttachChild(b);
    expect(scope.descendants.toSet(), {a, b});
  });

  test('reparenting a node detaches it from its previous parent', () {
    var scope1 = FocusScopeNode();
    var scope2 = FocusScopeNode();
    var node = FocusNode();
    scope1.debugAttachChild(node);
    scope2.debugAttachChild(node);
    expect(scope1.descendants, isEmpty);
    expect(scope2.descendants, [node]);
    expect(node.enclosingScope, scope2);
  });

  test('listeners fire on notify and stop after removeListener', () {
    var node = FocusNode();
    var count = 0;
    void listener() => count++;
    node.addListener(listener);
    node.debugNotify();
    expect(count, 1);
    node.removeListener(listener);
    node.debugNotify();
    expect(count, 1);
  });

  test('dispose detaches the node and clears listeners', () {
    var scope = FocusScopeNode();
    var node = FocusNode();
    scope.debugAttachChild(node);
    node.addListener(() {});
    node.dispose();
    expect(scope.descendants, isEmpty);
    expect(node.parent, isNull);
  });
}
