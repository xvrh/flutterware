import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware_app/src/tui/tui.dart';

/// Builds [app] under a TuiBinding and draws one frame into a [rows]x[cols]
/// buffer. Returns the binding so the test can inspect focus state.
TuiBinding _pump(Widget app, {int rows = 10, int cols = 20}) {
  var binding = TuiBinding();
  binding.attachRootWidget(app);
  binding.handleResize(CellSize(rows, cols));
  binding.drawFrame(Painter(CellBuffer(rows, cols)));
  return binding;
}

/// Draws another frame on an existing binding.
void _frame(TuiBinding binding, {int rows = 10, int cols = 20}) {
  binding.drawFrame(Painter(CellBuffer(rows, cols)));
}

void main() {
  test('Focus owns a node and attaches it under the root scope', () {
    var node = FocusNode();
    _pump(Focus(focusNode: node, child: SizedBox()));
    expect(node.parent, isNotNull);
    expect(node.enclosingScope, isNotNull);
  });

  test('autofocus focuses the node on first frame', () {
    var node = FocusNode();
    var binding =
        _pump(Focus(focusNode: node, autofocus: true, child: SizedBox()));
    expect(binding.focusManager.primaryFocus, node);
    expect(node.hasPrimaryFocus, isTrue);
  });

  test('a descendant reading Focus.of rebuilds when hasFocus flips', () {
    var node = FocusNode();
    var builds = <bool>[];
    var binding = _pump(Focus(
      focusNode: node,
      child: Builder(builder: (context) {
        builds.add(Focus.of(context).hasFocus);
        return SizedBox();
      }),
    ));
    expect(builds.last, isFalse);

    node.requestFocus();
    _frame(binding);
    expect(builds.last, isTrue);
  });

  test('Focus disposes only the node it created', () {
    var external = FocusNode();
    var binding = _pump(Focus(focusNode: external, child: SizedBox()));
    binding.dispose();
    // An externally-owned node is still usable (not disposed by Focus).
    expect(() => external.addListener(() {}), returnsNormally);
  });

  test('FocusScope attaches a scope node beneath the root scope', () {
    var scopeNode = FocusScopeNode();
    var leaf = FocusNode();
    _pump(FocusScope(
      node: scopeNode,
      child: Focus(focusNode: leaf, child: SizedBox()),
    ));
    expect(leaf.enclosingScope, scopeNode);
    expect(scopeNode.parent, isNotNull);
  });

  test('FocusTraversalGroup exposes its policy to descendants', () {
    var policy = DirectionalFocusTraversalPolicy();
    FocusTraversalPolicy? seen;
    _pump(FocusTraversalGroup(
      policy: policy,
      child: Builder(builder: (context) {
        seen = FocusTraversalGroup.maybeOf(context);
        return SizedBox();
      }),
    ));
    expect(seen, policy);
  });
}
