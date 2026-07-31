import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware_app/src/scenarios/discovery.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('scenarios_scan');
  });

  tearDown(() {
    root.deleteSync(recursive: true);
  });

  void write(String path, String content) {
    File(p.join(root.path, path))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(content);
  }

  test('finds scenario calls with literal names', () {
    write('test/scenarios/onboarding_test.dart', '''
import 'package:flutterware/flutter_test.dart';

void main() {
  scenario('Onboarding', (s) async {});
  scenario('Sign up', (s) async {});
}
''');
    write('test/scenarios/checkout/pay_test.dart', '''
import 'package:flutterware/flutter_test.dart';

void main() {
  scenario('Pay by card', (s) async {});
}
''');
    // Not in the scenario directory — invisible to the scan.
    write('test/unit_test.dart', "void main() { scenario('Nope', (s) {}); }");

    var result = ScenarioScanner(packageRoot: root.path).scan();
    expect(result.diagnostics, isEmpty);
    expect(
      [for (var ref in result.scenarios) '${ref.file} ${ref.name}'],
      unorderedEquals([
        'test/scenarios/onboarding_test.dart Onboarding',
        'test/scenarios/onboarding_test.dart Sign up',
        'test/scenarios/checkout/pay_test.dart Pay by card',
      ]),
    );
  });

  test('reports a non-literal name instead of guessing', () {
    write('test/scenarios/dynamic_test.dart', '''
void main() {
  var name = 'Computed';
  scenario(name, (s) async {});
}
''');
    var result = ScenarioScanner(packageRoot: root.path).scan();
    expect(result.scenarios, isEmpty);
    expect(result.diagnostics, hasLength(1));
    expect(result.diagnostics.single, contains('not a string literal'));
  });

  test('reports duplicate names across files', () {
    write(
      'test/scenarios/a_test.dart',
      "void main() => scenario('Same', (s) async {});",
    );
    write(
      'test/scenarios/b_test.dart',
      "void main() => scenario('Same', (s) async {});",
    );
    var result = ScenarioScanner(packageRoot: root.path).scan();
    expect(result.scenarios, hasLength(2));
    expect(result.diagnostics.single, contains('declared 2 times'));
  });

  test('honours a configured directory', () {
    write(
      'scenarios/home_test.dart',
      "void main() => scenario('Home', (s) async {});",
    );
    var result = ScenarioScanner(
      packageRoot: root.path,
      directory: 'scenarios',
    ).scan();
    expect(result.scenarios.single.name, 'Home');
  });

  test('an absent directory is an empty scan, not an error', () {
    var result = ScenarioScanner(packageRoot: root.path).scan();
    expect(result.scenarios, isEmpty);
    expect(result.diagnostics, isEmpty);
  });
}
