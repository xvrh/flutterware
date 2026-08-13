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
    // Anywhere under test/ counts — a scenario is an ordinary widget test.
    write('test/unit_test.dart', "void main() { scenario('Beside', (s) {}); }");
    // Outside test/ does not.
    write('tool/gen.dart', "void main() { scenario('Nope', (s) {}); }");

    var result = ScenarioScanner(packageRoot: root.path).scan();
    expect(result.diagnostics, isEmpty);
    expect(
      [for (var ref in result.scenarios) '${ref.file} ${ref.name}'],
      unorderedEquals([
        'test/scenarios/onboarding_test.dart Onboarding',
        'test/scenarios/onboarding_test.dart Sign up',
        'test/scenarios/checkout/pay_test.dart Pay by card',
        'test/unit_test.dart Beside',
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

  test('a name repeated across files is not a duplicate', () {
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
    // The file is in the address, in `run --scenario=`'s required company and
    // in the artifact path — nothing here has to choose between them.
    expect(result.diagnostics, isEmpty);
  });

  test('reports duplicate names within one file', () {
    write('test/scenarios/a_test.dart', '''
void main() {
  scenario('Same', (s) async {});
  scenario('Other', (s) async {});
  scenario('Same', (s) async {});
}
''');
    var result = ScenarioScanner(packageRoot: root.path).scan();
    expect(result.scenarios, hasLength(3));
    expect(
      result.diagnostics.single,
      allOf(
        contains('test/scenarios/a_test.dart'),
        contains('"Same" is declared 2 times'),
        contains('lines 2, 4'),
      ),
    );
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

  group('commonScenarioDirectory', () {
    test('is the directory a conventional suite sits under', () {
      expect(
        commonScenarioDirectory([
          'test/scenarios/a_test.dart',
          'test/scenarios/checkout/b_test.dart',
        ]),
        'test/scenarios',
      );
    });

    test('is the shared part of a spread suite', () {
      expect(
        commonScenarioDirectory([
          'test/scenarios/a_test.dart',
          'test/widgets/b_test.dart',
        ]),
        'test',
      );
    });

    test("is a single file's own directory", () {
      expect(
        commonScenarioDirectory(['test/scenarios/deep/a_test.dart']),
        'test/scenarios/deep',
      );
    });

    test('is empty with no files, or none shared', () {
      expect(commonScenarioDirectory([]), '');
      expect(
        commonScenarioDirectory(['test/a_test.dart', 'spec/b_test.dart']),
        '',
      );
    });
  });
}
