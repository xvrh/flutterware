import 'package:flutterware_app/src/tui/widgets/widgets.dart';
import 'package:test/test.dart';

void main() {
  test('StatefulElement wires State on construction', () {
    var element = const Probe('a').createElement();
    expect(element.state, isA<ProbeState>());
    expect(element.state.widget, isA<Probe>());
    expect((element.state.widget as Probe).label, 'a');
    // Not mounted until mount() runs.
    expect(element.state.mounted, isFalse);
  });

  test('canUpdate matches type and key (sanity)', () {
    expect(Widget.canUpdate(const Probe('a'), const Probe('b')), isTrue);
    expect(
        Widget.canUpdate(const Probe('a', key: ValueKey('k')),
            const Probe('b', key: ValueKey('k'))),
        isTrue);
    expect(
        Widget.canUpdate(const Probe('a', key: ValueKey('k')),
            const Probe('b', key: ValueKey('j'))),
        isFalse);
  });

  // TODO(Task 9): Add a regression test for the re-entrant markNeedsBuild fix.
  //
  // The bug: ComponentElement.performRebuild previously called build() before
  // super.performRebuild() (which clears _dirty). Any markNeedsBuild() issued
  // *during* build() hit the `if (_dirty) return;` guard while _dirty was still
  // true, so the re-entrant rebuild request was silently dropped.
  //
  // The fix (committed in this CL) moves super.performRebuild() before build().
  //
  // A proper regression test would:
  //   1. Mount a StatefulWidget whose build() calls setState() on itself (or
  //      a sibling) to trigger a re-entrant markNeedsBuild().
  //   2. Drive a BuildOwner.buildScope() pass.
  //   3. Assert the element ends up dirty again (or is in the owner's dirty
  //      list) after the pass, rather than having the second rebuild dropped.
  //
  // This requires injecting a BuildOwner into a root element — infrastructure
  // that lands in Task 9 (binding / RenderObjectToWidgetAdapter). Wire this
  // test up there, using the root-mount helper that task provides.
}

/// A [StatefulWidget] whose [State] records its lifecycle calls; deep
/// lifecycle assertions live in the binding suite (plan Task 9).
class Probe extends StatefulWidget {
  const Probe(this.label, {super.key});

  final String label;

  @override
  State<Probe> createState() => ProbeState();
}

class ProbeState extends State<Probe> {
  @override
  Widget build(BuildContext context) => const _Leaf();
}

class _Leaf extends StatelessWidget {
  const _Leaf();

  @override
  Widget build(BuildContext context) => this;
}
