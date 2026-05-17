import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware_app/src/tui/tui.dart';

class _PingIntent extends Intent {
  const _PingIntent();
}

/// An `Action<ActivateIntent>` that runs a callback when invoked.
class _CallbackActivate extends Action<ActivateIntent> {
  _CallbackActivate(this.onInvoke);
  final void Function() onInvoke;
  @override
  Object? invoke(ActivateIntent intent) {
    onInvoke();
    return null;
  }
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

  test('defaultShortcuts binds Tab, arrows, Enter, and Escape', () {
    var map = defaultShortcuts();
    expect(map[const SpecialKey(code: SpecialKeyCode.tab, modifiers: {})],
        isA<NextFocusIntent>());
    expect(
        map[const SpecialKey(
            code: SpecialKeyCode.tab, modifiers: {Modifier.shift})],
        isA<PreviousFocusIntent>());
    expect(map[const SpecialKey(code: SpecialKeyCode.up, modifiers: {})],
        isA<DirectionalFocusIntent>());
    expect(map[const SpecialKey(code: SpecialKeyCode.enter, modifiers: {})],
        isA<ActivateIntent>());
    expect(map[const SpecialKey(code: SpecialKeyCode.escape, modifiers: {})],
        isA<DismissIntent>());
  });

  test('a Shortcuts widget intercepts a key for its focused subtree', () {
    var node = FocusNode();
    var invoked = false;
    var binding = TuiBinding();
    binding.attachRootWidget(Shortcuts(
      shortcuts: {
        const CharKey(rune: 0x78 /* x */, modifiers: {}): const ActivateIntent()
      },
      child: Actions(
        actions: {ActivateIntent: _CallbackActivate(() => invoked = true)},
        child: Focus(
            focusNode: node,
            autofocus: true,
            child: SizedBox(width: 4, height: 2)),
      ),
    ));
    binding.handleResize(CellSize(8, 12));
    binding.drawFrame(Painter(CellBuffer(8, 12)));

    binding.focusManager
        .handleKeyEvent(const CharKey(rune: 0x78, modifiers: {}));
    expect(invoked, isTrue);
  });

  test('an inner Shortcuts shadows an outer one for the same key', () {
    var node = FocusNode();
    var hits = <String>[];
    var binding = TuiBinding();
    const xKey = CharKey(rune: 0x78 /* x */, modifiers: {});
    binding.attachRootWidget(Shortcuts(
      shortcuts: {xKey: const ActivateIntent()},
      child: Actions(
        actions: {ActivateIntent: _CallbackActivate(() => hits.add('outer'))},
        child: Shortcuts(
          shortcuts: {xKey: const ActivateIntent()},
          child: Actions(
            actions: {
              ActivateIntent: _CallbackActivate(() => hits.add('inner'))
            },
            child: Focus(
                focusNode: node,
                autofocus: true,
                child: SizedBox(width: 4, height: 2)),
          ),
        ),
      ),
    ));
    binding.handleResize(CellSize(8, 12));
    binding.drawFrame(Painter(CellBuffer(8, 12)));

    binding.focusManager.handleKeyEvent(xKey);
    expect(hits, ['inner']);
  });
}
