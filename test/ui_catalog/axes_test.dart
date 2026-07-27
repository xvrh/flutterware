import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware/src/ui_catalog/axes.dart';
import 'package:flutterware/src/ui_catalog/knob.dart';

enum Flavor { dev, staging, prod }

enum Size { small, large }

/// The top bar's switches, from the guest's side.
///
/// A shell declares them by having them in its signature, so the generated call
/// makes exactly one [CatalogAxes.pick] or [CatalogAxes.flag] per axis, every
/// build, unconditionally. That is what separates an axis from a knob: there is
/// no branch a build can take that changes the set.
void main() {
  late CatalogAxes axes;

  setUp(() {
    // A null selection is "back to the default", which is also what makes a
    // shared singleton safe to start each test from.
    axes = CatalogAxes.instance
      ..apply({'flavor': null, 'compact': null, 'size': null})
      ..beginShell(null);
  });

  test('an axis reports what there is to choose from', () {
    axes.beginShell('demo/shell.dart#wrapInApp');
    expect(axes.pick('flavor', Flavor.values, Flavor.dev), Flavor.dev);

    var report = axes.describe();
    expect(report.shellId, 'demo/shell.dart#wrapInApp');
    var axis = report.axes.single;
    expect(axis.name, 'flavor');
    expect(axis.kind, KnobKind.picker);
    expect(axis.options, ['dev', 'staging', 'prod']);
    expect(axis.value, 'dev');
    expect(axis.defaultValue, 'dev');
    expect(axis.isDefault, isTrue);
  });

  test('a selection is answered by the next pick', () {
    axes.apply({'flavor': 'prod'});
    axes.beginShell('s');
    expect(axes.pick('flavor', Flavor.values, Flavor.dev), Flavor.prod);
    expect(axes.describe().axes.single.isDefault, isFalse);
  });

  test('a selection the enum does not have falls back', () {
    // A leftover from another shell, or a `--flavor=prd` typed at a CLI.
    axes.apply({'flavor': 'nonsense'});
    axes.beginShell('s');
    expect(axes.pick('flavor', Flavor.values, Flavor.staging), Flavor.staging);
  });

  test('a selection may arrive before the shell that reads it has built', () {
    // Which is the ordinary case: the host pushes a shell's selections before
    // the reload that switches to it, precisely so no frame renders with the
    // wrong one.
    axes.apply({'flavor': 'staging'});
    expect(axes.describe().axes, isEmpty);
    axes.beginShell('s');
    expect(axes.pick('flavor', Flavor.values, Flavor.dev), Flavor.staging);
  });

  test('a flag is a closed set too, and keeps its own kind', () {
    axes.beginShell('s');
    expect(axes.flag('compact', false), isFalse);
    expect(axes.describe().axes.single.kind, KnobKind.boolean);

    axes.apply({'compact': true});
    axes.beginShell('s');
    expect(axes.flag('compact', false), isTrue);
  });

  test('the report is the current shell, not everything ever declared', () {
    axes.beginShell('one');
    axes.pick('flavor', Flavor.values, Flavor.dev);
    axes.beginShell('two');
    axes.flag('compact', false);

    var report = axes.describe();
    expect(report.shellId, 'two');
    expect(report.axes.map((a) => a.name), ['compact']);
  });

  test('a selection survives a shell it does not belong to', () {
    // Not cleared on a shell change: the host is authoritative and has already
    // pushed what this shell should show, so dropping it here would throw away
    // an instruction rather than a leftover.
    axes.apply({'flavor': 'prod'});
    axes.beginShell('other');
    axes.pick('size', Size.values, Size.small);
    axes.beginShell('back');
    expect(axes.pick('flavor', Flavor.values, Flavor.dev), Flavor.prod);
  });

  test('the order is the signature\'s', () {
    axes.beginShell('s');
    axes.flag('compact', false);
    axes.pick('flavor', Flavor.values, Flavor.dev);
    expect(axes.describe().axes.map((a) => a.name), ['compact', 'flavor']);
  });

  testWidgets('the scope declares before the shell is called, and rebuilds', (
    tester,
  ) async {
    var built = <Flavor>[];
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: CatalogAxesScope(
          shellId: 'demo/shell.dart#wrapInApp',
          builder: (context) {
            built.add(axes.pick('flavor', Flavor.values, Flavor.dev));
            return const SizedBox();
          },
        ),
      ),
    );
    expect(built, [Flavor.dev]);
    expect(axes.describe().shellId, 'demo/shell.dart#wrapInApp');

    axes.apply({'flavor': 'prod'});
    await tester.pump();
    expect(built, [Flavor.dev, Flavor.prod]);
  });

  test('an empty push changes nothing, and does not ask for a frame', () {
    var revision = axes.revision.value;
    axes.apply(const {});
    expect(axes.revision.value, revision);
  });

  test('a null selection is back to the default', () {
    axes.apply({'flavor': 'prod'});
    axes.beginShell('s');
    expect(axes.pick('flavor', Flavor.values, Flavor.dev), Flavor.prod);

    axes.apply({'flavor': null});
    axes.beginShell('s');
    expect(axes.pick('flavor', Flavor.values, Flavor.dev), Flavor.dev);
  });
}
