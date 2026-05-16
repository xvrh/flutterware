import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware_app/src/tui/tui.dart';

void main() {
  test('a fresh manager has rootScope as primary focus after apply', () {
    var manager = FocusManager();
    expect(manager.primaryFocus, manager.rootScope);
  });

  test('requestFocus is pending until applyFocusChangesIfNeeded runs', () {
    var manager = FocusManager();
    var node = FocusNode();
    manager.rootScope.debugAttachChild(node);

    node.requestFocus();
    expect(manager.primaryFocus, manager.rootScope); // not applied yet

    manager.applyFocusChangesIfNeeded();
    expect(manager.primaryFocus, node);
    expect(node.hasPrimaryFocus, isTrue);
    expect(node.hasFocus, isTrue);
    expect(manager.rootScope.hasFocus, isTrue); // ancestor of primary
  });

  test('requestFocus calls onFocusChange exactly once while idle', () {
    var manager = FocusManager();
    var node = FocusNode();
    manager.rootScope.debugAttachChild(node);
    var calls = 0;
    manager.onFocusChange = () => calls++;

    node.requestFocus();
    node.requestFocus();
    expect(calls, 1);
  });

  test('unfocus hands focus to the enclosing scope', () {
    var manager = FocusManager();
    var node = FocusNode();
    manager.rootScope.debugAttachChild(node);
    node.requestFocus();
    manager.applyFocusChangesIfNeeded();

    node.unfocus();
    manager.applyFocusChangesIfNeeded();
    expect(manager.primaryFocus, manager.rootScope);
  });

  test('apply notifies nodes whose hasFocus changed', () {
    var manager = FocusManager();
    var node = FocusNode();
    manager.rootScope.debugAttachChild(node);
    var notified = 0;
    node.addListener(() => notified++);

    node.requestFocus();
    manager.applyFocusChangesIfNeeded();
    expect(notified, 1);
  });
}
