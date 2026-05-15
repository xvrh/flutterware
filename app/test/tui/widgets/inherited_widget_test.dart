import 'package:flutterware_app/src/tui/widgets/widgets.dart';
import 'package:test/test.dart';

import '_harness.dart';

/// An inherited widget carrying an int, optionally suppressing notifications.
class Model extends InheritedWidget {
  const Model({
    super.key,
    required this.value,
    this.notify = true,
    required super.child,
  });

  final int value;
  final bool notify;

  static Model of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<Model>()!;

  @override
  bool updateShouldNotify(Model oldWidget) => notify;
}

/// Records every build, keyed by [label]. Reads [Model] as a dependency.
var buildLog = <String>[];

class Dependent extends StatelessWidget {
  const Dependent(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    var model = Model.of(context);
    buildLog.add('$label=${model.value}');
    return Text('$label${model.value}');
  }
}

/// Reads [Model] without registering a dependency.
class NonDependent extends StatelessWidget {
  const NonDependent(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    var model = context.getInheritedWidgetOfExactType<Model>();
    buildLog.add('$label=${model?.value}');
    return Text('$label${model?.value}');
  }
}

void main() {
  setUp(() => buildLog = <String>[]);

  test('dependOnInheritedWidgetOfExactType returns the nearest ancestor', () {
    pumpHosted(const Model(value: 7, child: Column(children: [Dependent('d')])),
        cols: 16);
    expect(buildLog, ['d=7']);
  });

  test('a nearer ancestor shadows a farther one', () {
    pumpHosted(
        const Model(
          value: 1,
          child: Model(value: 2, child: Column(children: [Dependent('d')])),
        ),
        cols: 16);
    expect(buildLog, ['d=2']);
  });

  test('updateShouldNotify == true rebuilds exactly the dependents', () {
    var binding = pumpHosted(
        const Model(
            value: 1,
            child: Column(children: [Dependent('a'), Dependent('b')])),
        cols: 16);
    expect(buildLog, ['a=1', 'b=1']);
    buildLog.clear();

    rebuild(
        binding,
        const Model(
            value: 2,
            child: Column(children: [Dependent('a'), Dependent('b')])),
        cols: 16);
    // Both dependents rebuilt with the new value.
    expect(buildLog..sort(), ['a=2', 'b=2']);
  });

  test('updateShouldNotify == false skips dependent rebuilds', () {
    var binding = pumpHosted(
        const Model(
            value: 1, notify: false, child: Column(children: [Dependent('a')])),
        cols: 16);
    expect(buildLog, ['a=1']);
    buildLog.clear();

    rebuild(
        binding,
        const Model(
            value: 2, notify: false, child: Column(children: [Dependent('a')])),
        cols: 16);
    // The dependent must NOT rebuild even though the value changed.
    expect(buildLog, isEmpty);
  });

  test('a non-dependent sibling is never rebuilt on value change', () {
    var binding = pumpHosted(
        const Model(
            value: 1,
            child: Column(children: [Dependent('dep'), NonDependent('non')])),
        cols: 16);
    expect(buildLog, ['dep=1', 'non=1']);
    buildLog.clear();

    rebuild(
        binding,
        const Model(
            value: 2,
            child: Column(children: [Dependent('dep'), NonDependent('non')])),
        cols: 16);
    // Only the registered dependent rebuilt.
    expect(buildLog, ['dep=2']);
  });

  test('getInheritedWidgetOfExactType does not register a dependency', () {
    var binding = pumpHosted(
        const Model(value: 1, child: Column(children: [NonDependent('non')])),
        cols: 16);
    expect(buildLog, ['non=1']);
    buildLog.clear();

    rebuild(binding,
        const Model(value: 2, child: Column(children: [NonDependent('non')])),
        cols: 16);
    // No dependency registered => no rebuild despite the value change.
    expect(buildLog, isEmpty);
  });
}
