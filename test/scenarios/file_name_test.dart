import 'package:flutterware/src/scenarios/harness.dart';
import 'package:flutter_test/flutter_test.dart';

/// What a step's artifacts may be called.
///
/// The cap is the point. An automatic capture is labelled by its verb and its
/// target, and a target given as a `Finder` describes itself with the matched
/// widget's whole `toString()` — hundreds of characters, `TextStyle` dump
/// included. Uncapped that ran past `NAME_MAX` and threw, failing a scenario
/// whose only problem was that its picture could not be written down.
void main() {
  test('maps everything outside the safe set to an underscore', () {
    expect(scenarioFileSafe('Mobile / Support'), 'Mobile_Support');
    expect(scenarioFileSafe("What's new"), 'What_s_new');
    expect(scenarioFileSafe('a.b-c_d'), 'a.b-c_d');
  });

  test('caps a name at NAME_MAX', () {
    var name = scenarioFileSafe('x' * 400);
    expect(name.length, scenarioNameMax);
  });

  test('leaves a real Finder description writable', () {
    // The description that produced the bug, near enough.
    var label =
        'tap Found 1 widget with text "Jean Martin" (considering only '
        'hit-testable widgets) with a RenderBox: Text("Jean Martin", '
        'inherit: true, color: Color(alpha: 1.0000, red: 0.0902, '
        'green: 0.1294, blue: 0.1490, colorSpace: ColorSpace.sRGB), '
        'size: 15.0, weight: 500)';
    var prefix = '6-';
    var suffix = '.semantics.json';
    var component =
        '$prefix'
        '${scenarioFileSafe(label, max: scenarioNameMax - prefix.length - suffix.length)}'
        '$suffix';
    expect(component.length, lessThanOrEqualTo(scenarioNameMax));
  });

  test('a name that already fits is untouched', () {
    expect(scenarioFileSafe('Dashboard'), 'Dashboard');
    expect(scenarioFileSafe('Dashboard', max: 9), 'Dashboard');
  });
}
