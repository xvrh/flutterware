import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware_app/src/tui/tui.dart';

class _PingIntent extends Intent {
  const _PingIntent();
}

class _PingAction extends Action<_PingIntent> {
  bool invoked = false;
  bool enabled = true;
  @override
  bool isEnabled(_PingIntent intent) => enabled;
  @override
  Object? invoke(_PingIntent intent) {
    invoked = true;
    return null;
  }
}

void main() {
  const pingKey = CharKey(rune: 0x70 /* p */, modifiers: {});

  ({FocusManager manager, FocusNode node}) focusedManager() {
    var manager = FocusManager();
    var node = FocusNode();
    manager.rootScope.debugAttachChild(node);
    node.requestFocus();
    manager.applyFocusChangesIfNeeded();
    return (manager: manager, node: node);
  }

  test('a bound key invokes a fallback action and returns handled', () {
    var fm = focusedManager();
    var action = _PingAction();
    var sm = ShortcutManager(
      shortcuts: {pingKey: const _PingIntent()},
      fallbackActions: {_PingIntent: action},
    );
    var result = sm.handleFocusKeyEvent(fm.manager.rootScope, pingKey);
    expect(result, KeyEventResult.handled);
    expect(action.invoked, isTrue);
  });

  test('an unbound key returns ignored', () {
    var fm = focusedManager();
    var sm = ShortcutManager(
      shortcuts: {pingKey: const _PingIntent()},
      fallbackActions: {_PingIntent: _PingAction()},
    );
    var result = sm.handleFocusKeyEvent(
        fm.manager.rootScope, const CharKey(rune: 0x7a /* z */, modifiers: {}));
    expect(result, KeyEventResult.ignored);
  });

  test('a disabled action returns ignored and is not invoked', () {
    var fm = focusedManager();
    var action = _PingAction()..enabled = false;
    var sm = ShortcutManager(
      shortcuts: {pingKey: const _PingIntent()},
      fallbackActions: {_PingIntent: action},
    );
    var result = sm.handleFocusKeyEvent(fm.manager.rootScope, pingKey);
    expect(result, KeyEventResult.ignored);
    expect(action.invoked, isFalse);
  });

  test('a bound intent with no action anywhere returns ignored', () {
    var fm = focusedManager();
    var sm = ShortcutManager(shortcuts: {pingKey: const _PingIntent()});
    var result = sm.handleFocusKeyEvent(fm.manager.rootScope, pingKey);
    expect(result, KeyEventResult.ignored);
  });
}
