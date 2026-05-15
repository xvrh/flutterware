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
