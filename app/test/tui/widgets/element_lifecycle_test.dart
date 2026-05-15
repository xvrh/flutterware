import 'package:flutterware_app/src/tui/buffer.dart';
import 'package:flutterware_app/src/tui/geometry.dart';
import 'package:flutterware_app/src/tui/painter.dart';
import 'package:flutterware_app/src/tui/widgets/widgets.dart';
import 'package:test/test.dart';

/// Shared lifecycle-call log; reset in [setUp].
var log = <String>[];

/// A [StatefulWidget] whose [State] records every lifecycle call.
class Probe extends StatefulWidget {
  const Probe(this.label, {super.key});

  final String label;

  /// The most recently mounted [ProbeState], for identity assertions.
  static ProbeState? lastState;

  @override
  State<Probe> createState() => ProbeState();
}

class ProbeState extends State<Probe> {
  @override
  void initState() {
    Probe.lastState = this;
    log.add('initState ${widget.label}');
  }

  @override
  void didChangeDependencies() =>
      log.add('didChangeDependencies ${widget.label}');

  @override
  void didUpdateWidget(Probe oldWidget) =>
      log.add('didUpdateWidget ${widget.label}<-${oldWidget.label}');

  @override
  void deactivate() => log.add('deactivate ${widget.label}');

  @override
  void dispose() => log.add('dispose ${widget.label}');

  @override
  Widget build(BuildContext context) {
    log.add('build ${widget.label}');
    return Text(widget.label);
  }
}

/// A stateful host that swaps its built subtree between frames.
class Host extends StatefulWidget {
  const Host({super.key});

  static Widget body = const Text('');
  static HostState? last;

  @override
  State<Host> createState() => HostState();
}

class HostState extends State<Host> {
  @override
  void initState() {
    Host.last = this;
  }

  void show(Widget body) => setState(() => Host.body = body);

  @override
  Widget build(BuildContext context) => Host.body;
}

TuiBinding pump(Widget body) {
  Host.body = body;
  var binding = TuiBinding();
  binding.attachRootWidget(const Host());
  binding.handleResize(CellSize(8, 12));
  binding.drawFrame(Painter(CellBuffer(8, 12)));
  return binding;
}

void rebuild(TuiBinding binding, Widget body) {
  Host.last!.show(body);
  binding.drawFrame(Painter(CellBuffer(8, 12)));
}

void main() {
  setUp(() {
    log = <String>[];
    Probe.lastState = null;
  });

  test('StatefulElement wires State on construction', () {
    var element = const Probe('a').createElement();
    expect(element.state, isA<ProbeState>());
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

  test('mount runs initState -> didChangeDependencies -> build in order', () {
    pump(const Probe('a'));
    expect(log, ['initState a', 'didChangeDependencies a', 'build a']);
  });

  test('rebuild with a same-type widget runs didUpdateWidget then build', () {
    var binding = pump(const Probe('a'));
    log.clear();

    rebuild(binding, const Probe('b'));
    expect(log, ['didUpdateWidget b<-a', 'build b']);
  });

  test('removing a widget runs deactivate then dispose', () {
    var binding = pump(const Probe('a'));
    log.clear();

    // Replace the Probe with a plain Text => the Probe leaves the tree.
    rebuild(binding, const Text('gone'));
    expect(log, ['deactivate a', 'dispose a']);
  });

  test('State.mounted flips false after the element is unmounted', () {
    var binding = pump(const Probe('a'));
    var state = Probe.lastState!;
    expect(state.mounted, isTrue);

    rebuild(binding, const Text('gone'));
    expect(state.mounted, isFalse);
  });

  test('the State is the same instance across a same-type rebuild', () {
    var binding = pump(const Probe('a'));
    var first = Probe.lastState!;

    rebuild(binding, const Probe('b'));
    // initState did not re-run, so lastState is unchanged.
    expect(identical(first, Probe.lastState), isTrue,
        reason: 'a same-type update reuses the element and its State');
    expect(first.widget.label, 'b',
        reason: 'the reused State sees the new widget');
  });
}
