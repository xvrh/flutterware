import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware_app/src/tui/tui.dart';

/// A FocusNode with a fixed rect, so traversal works without a widget tree.
class _RectNode extends FocusNode {
  _RectNode(this.fixedRect);
  final CellRect fixedRect;
  @override
  CellRect? get rect => fixedRect;
}

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

  test('handleKeyEvent dispatches to the primary focus first', () {
    var manager = FocusManager();
    var node = FocusNode();
    manager.rootScope.debugAttachChild(node);
    node.requestFocus();
    manager.applyFocusChangesIfNeeded();

    KeyEvent? seen;
    node.onKeyEvent = (n, e) {
      seen = e;
      return KeyEventResult.handled;
    };
    var event = CharKey(rune: 0x61, modifiers: const {});
    var result = manager.handleKeyEvent(event);
    expect(seen, event);
    expect(result, KeyEventResult.handled);
  });

  test('handleKeyEvent bubbles to ancestors when ignored', () {
    var manager = FocusManager();
    var node = FocusNode();
    manager.rootScope.debugAttachChild(node);
    node.requestFocus();
    manager.applyFocusChangesIfNeeded();

    var order = <String>[];
    node.onKeyEvent = (n, e) {
      order.add('node');
      return KeyEventResult.ignored;
    };
    manager.rootScope.onKeyEvent = (n, e) {
      order.add('root');
      return KeyEventResult.handled;
    };
    manager.handleKeyEvent(CharKey(rune: 0x61, modifiers: const {}));
    expect(order, ['node', 'root']);
  });

  test('handleKeyEvent stops bubbling once handled', () {
    var manager = FocusManager();
    var node = FocusNode();
    manager.rootScope.debugAttachChild(node);
    node.requestFocus();
    manager.applyFocusChangesIfNeeded();

    var rootCalled = false;
    node.onKeyEvent = (n, e) => KeyEventResult.handled;
    manager.rootScope.onKeyEvent = (n, e) {
      rootCalled = true;
      return KeyEventResult.ignored;
    };
    manager.handleKeyEvent(CharKey(rune: 0x61, modifiers: const {}));
    expect(rootCalled, isFalse);
  });

  test('unhandled Tab moves focus forward via the fallback', () {
    var manager = FocusManager();
    var a = _RectNode(CellRect.fromTLWH(0, 0, 4, 1));
    var b = _RectNode(CellRect.fromTLWH(0, 10, 4, 1));
    manager.rootScope.debugAttachChild(a);
    manager.rootScope.debugAttachChild(b);
    a.requestFocus();
    manager.applyFocusChangesIfNeeded();

    var result = manager.handleKeyEvent(
        const SpecialKey(code: SpecialKeyCode.tab, modifiers: {}));
    manager.applyFocusChangesIfNeeded();
    expect(result, KeyEventResult.handled);
    expect(manager.primaryFocus, b);
  });

  test('unhandled Shift-Tab moves focus backward', () {
    var manager = FocusManager();
    var a = _RectNode(CellRect.fromTLWH(0, 0, 4, 1));
    var b = _RectNode(CellRect.fromTLWH(0, 10, 4, 1));
    manager.rootScope.debugAttachChild(a);
    manager.rootScope.debugAttachChild(b);
    a.requestFocus();
    manager.applyFocusChangesIfNeeded();

    manager.handleKeyEvent(const SpecialKey(
        code: SpecialKeyCode.tab, modifiers: {Modifier.shift}));
    manager.applyFocusChangesIfNeeded();
    expect(manager.primaryFocus, b); // wraps backward
  });

  test('unhandled arrow key moves focus directionally', () {
    var manager = FocusManager();
    var a = _RectNode(CellRect.fromTLWH(0, 0, 4, 3));
    var b = _RectNode(CellRect.fromTLWH(0, 20, 4, 3));
    manager.rootScope.debugAttachChild(a);
    manager.rootScope.debugAttachChild(b);
    a.requestFocus();
    manager.applyFocusChangesIfNeeded();

    manager.handleKeyEvent(
        const SpecialKey(code: SpecialKeyCode.right, modifiers: {}));
    manager.applyFocusChangesIfNeeded();
    expect(manager.primaryFocus, b);
  });
}
