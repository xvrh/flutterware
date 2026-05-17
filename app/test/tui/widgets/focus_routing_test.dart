import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware_app/src/tui/tui.dart';

TuiBinding _pump(Widget app, {int rows = 10, int cols = 30}) {
  var binding = TuiBinding();
  binding.attachRootWidget(app);
  binding.handleResize(CellSize(rows, cols));
  binding.drawFrame(Painter(CellBuffer(rows, cols)));
  return binding;
}

void main() {
  test('a key event reaches the focused node onKeyEvent', () {
    var node = FocusNode();
    KeyEvent? seen;
    var binding = _pump(Focus(
      focusNode: node,
      autofocus: true,
      onKeyEvent: (n, e) {
        seen = e;
        return KeyEventResult.handled;
      },
      child: SizedBox(),
    ));
    var event = CharKey(rune: 0x78, modifiers: const {});
    binding.focusManager.handleKeyEvent(event);
    expect(seen, event);
  });

  test('unhandled Tab moves focus between two Focus widgets', () {
    var first = FocusNode();
    var second = FocusNode();
    var binding = _pump(Row(children: [
      Focus(
          focusNode: first,
          autofocus: true,
          child: SizedBox(width: 5, height: 3)),
      Focus(focusNode: second, child: SizedBox(width: 5, height: 3)),
    ]));
    expect(binding.focusManager.primaryFocus, first);

    binding.focusManager.handleKeyEvent(
        const SpecialKey(code: SpecialKeyCode.tab, modifiers: {}));
    binding.drawFrame(Painter(CellBuffer(10, 30)));
    expect(binding.focusManager.primaryFocus, second);
  });
}
