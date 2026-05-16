import 'package:flutterware_app/src/tui/buffer.dart';
import 'package:flutterware_app/src/tui/painter.dart';
import 'package:flutterware_app/src/tui/widgets/widgets.dart';
import 'package:test/test.dart';

import 'harness.dart' as harness;

TuiBinding pump(Widget widget) =>
    harness.pump(widget, rows: 8, cols: 12).binding;

void frame(TuiBinding binding) => binding.drawFrame(Painter(CellBuffer(8, 12)));

/// Records every build call into a shared list.
var buildLog = <String>[];

/// A leaf stateful widget that counts its builds and exposes its state.
class Leaf extends StatefulWidget {
  const Leaf(this.label, {super.key});

  final String label;

  static final Map<String, LeafState> states = {};

  @override
  State<Leaf> createState() => LeafState();
}

class LeafState extends State<Leaf> {
  int builds = 0;

  @override
  void initState() {
    Leaf.states[widget.label] = this;
  }

  void poke() => setState(() {});

  @override
  Widget build(BuildContext context) {
    builds += 1;
    buildLog.add('build ${widget.label}');
    return Text(widget.label);
  }
}

/// A stateful widget that contains another stateful widget — used to prove
/// parent-before-child ordering.
class Outer extends StatefulWidget {
  const Outer({super.key});

  static OuterState? last;

  @override
  State<Outer> createState() => OuterState();
}

class OuterState extends State<Outer> {
  @override
  void initState() {
    Outer.last = this;
  }

  void poke() => setState(() {});

  @override
  Widget build(BuildContext context) {
    buildLog.add('build Outer');
    return const Leaf('Inner');
  }
}

/// A widget whose first build issues a re-entrant setState on itself.
class Reentrant extends StatefulWidget {
  const Reentrant({super.key});

  /// Total build count across the widget's life — read by the regression test.
  static int builds = 0;

  @override
  State<Reentrant> createState() => ReentrantState();
}

class ReentrantState extends State<Reentrant> {
  bool _bumpedOnce = false;

  @override
  Widget build(BuildContext context) {
    Reentrant.builds += 1;
    if (!_bumpedOnce) {
      _bumpedOnce = true;
      // A markNeedsBuild() issued *during* build(): if performRebuild cleared
      // _dirty before build(), this re-entrant request is honoured rather
      // than dropped by the `if (_dirty) return;` guard.
      setState(() {});
    }
    return Text('${Reentrant.builds}');
  }
}

void main() {
  setUp(() {
    buildLog = <String>[];
    Leaf.states.clear();
    Outer.last = null;
    Reentrant.builds = 0;
  });

  test('setState marks exactly its element dirty; siblings do not rebuild', () {
    var binding = pump(const Column(children: [Leaf('a'), Leaf('b')]));
    var a = Leaf.states['a']!;
    var b = Leaf.states['b']!;
    expect(a.builds, 1);
    expect(b.builds, 1);

    a.poke();
    frame(binding);

    expect(a.builds, 2, reason: 'the poked element rebuilt');
    expect(b.builds, 1, reason: 'the sibling was untouched');
  });

  test('nested dirty elements rebuild parent before child', () {
    var binding = pump(const Outer());
    buildLog.clear();

    // Dirty both the outer and the inner element before the frame.
    Outer.last!.poke();
    Leaf.states['Inner']!.poke();
    frame(binding);

    // Outer is shallower, so it must rebuild first.
    expect(buildLog, ['build Outer', 'build Inner']);
  });

  test('onBuildScheduled fires once per idle->dirty transition', () {
    var binding = pump(const Column(children: [Leaf('a'), Leaf('b')]));
    var scheduled = 0;
    binding.onFrameNeeded = () => scheduled += 1;

    // First dirty element of an idle owner -> one schedule.
    Leaf.states['a']!.poke();
    expect(scheduled, 1);
    // A second dirty element while the owner is already dirty -> no schedule.
    Leaf.states['b']!.poke();
    expect(scheduled, 1);

    // After the frame drains the dirty list, the owner is idle again.
    frame(binding);
    Leaf.states['a']!.poke();
    expect(scheduled, 2);
  });

  test('a re-entrant setState during build() rebuilds again (regression)', () {
    // Regression for the dropped re-entrant rebuild: ComponentElement
    // .performRebuild must clear _dirty *before* build(), so a markNeedsBuild()
    // issued during build() is not swallowed by the `if (_dirty) return;`
    // guard. If the bug were present, the build count would stop at 1 because
    // the re-entrant request would be dropped.
    var binding = pump(const Reentrant());
    // The first frame built once and the in-build setState re-dirtied the
    // element; that re-entrant request must be honoured within the same pass
    // (BuildOwner.buildScope re-sorts and revisits dirty elements).
    expect(Reentrant.builds, greaterThanOrEqualTo(2),
        reason: 'the re-entrant markNeedsBuild was honoured, not dropped');

    // A further frame is stable: the element is clean and does not rebuild.
    var settled = Reentrant.builds;
    frame(binding);
    expect(Reentrant.builds, settled, reason: 'no spurious rebuilds');
  });
}
