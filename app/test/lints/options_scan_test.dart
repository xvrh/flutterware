import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware_app/src/lints/model/options_scan.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('fw_lints_scan');
  });

  tearDown(() {
    root.deleteSync(recursive: true);
  });

  void write(String relative, String content) {
    var file = File(p.join(root.path, relative));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
  }

  LintOptionsScan scan({String? Function(Uri)? resolvePackageUri}) =>
      LintOptionsScanner(
        repoRoot: root.path,
        resolvePackageUri: resolvePackageUri,
      ).scan();

  test('finds every options file, root first', () {
    write('analysis_options.yaml', 'linter:\n  rules:\n    - rule_a\n');
    write('member/analysis_options.yaml', 'include: ../analysis_options.yaml');
    var result = scan();
    expect(result.files.map((f) => f.path), [
      'analysis_options.yaml',
      'member/analysis_options.yaml',
    ]);
    expect(result.root, isNotNull);
  });

  test('reads both rule spellings and the analyzer errors section', () {
    write('analysis_options.yaml', '''
linter:
  rules:
    rule_a: true
    rule_b: false
analyzer:
  errors:
    rule_c: ignore
''');
    var file = scan().files.single;
    expect(file.mentions['rule_a']!.enabled, isTrue);
    expect(file.mentions['rule_b']!.enabled, isFalse);
    expect(file.severityOverrides['rule_c'], 'ignore');
    expect(file.enabled, {'rule_a'});
  });

  test('a relative include chain applies deepest first, local wins', () {
    write('base.yaml', '''
linter:
  rules:
    - rule_a
    - rule_b
''');
    write('analysis_options.yaml', '''
include: base.yaml

linter:
  rules:
    rule_b: false
    rule_c: true
''');
    var file = scan().root!;
    expect(file.hasInclude, isTrue);
    expect(file.includeChain, ['base.yaml']);
    expect(file.enabled, {'rule_a', 'rule_c'});
    expect(file.effective['rule_a']!.via, 'base.yaml');
    expect(file.effective['rule_b']!.via, 'analysis_options.yaml');
  });

  test('package: includes resolve through the resolver and chain onward', () {
    // Two files standing in for package:lints — recommended includes core.
    write('fake_pub/core.yaml', 'linter:\n  rules:\n    - core_rule\n');
    write(
      'fake_pub/recommended.yaml',
      'include: core.yaml\n\nlinter:\n  rules:\n    - recommended_rule\n',
    );
    write('analysis_options.yaml', 'include: package:lints/recommended.yaml\n');
    var file = scan(
      resolvePackageUri: (uri) =>
          uri.toString() == 'package:lints/recommended.yaml'
          ? p.join(root.path, 'fake_pub', 'recommended.yaml')
          : null,
    ).root!;
    expect(file.enabled, {'core_rule', 'recommended_rule'});
    expect(file.includeChain, [
      'fake_pub/core.yaml',
      'package:lints/recommended.yaml',
    ]);
    expect(file.effective['core_rule']!.via, 'fake_pub/core.yaml');
  });

  test('an unresolvable include is an error, not a guess', () {
    write('analysis_options.yaml', 'include: package:lints/recommended.yaml\n');
    var file = scan().root!;
    expect(file.includeErrors, ['package:lints/recommended.yaml']);
    expect(file.enabled, isEmpty);
  });

  test('no include severs inheritance and says so', () {
    write('analysis_options.yaml', 'linter:\n  rules:\n    - rule_a\n');
    write('vendored/analysis_options.yaml', 'analyzer:\n');
    var vendored = scan().files.last;
    expect(vendored.hasInclude, isFalse);
    expect(vendored.enabled, isEmpty);
  });

  test('an include cycle terminates', () {
    write('a.yaml', 'include: analysis_options.yaml\n');
    write('analysis_options.yaml', '''
include: a.yaml

linter:
  rules:
    - rule_a
''');
    expect(scan().root!.enabled, {'rule_a'});
  });

  test('comments attach: trailing first, else the block just above', () {
    write('analysis_options.yaml', '''
linter:
  rules:
    rule_a: false # too noisy for generated code
    # We tried this one and the churn
    # was not worth it.
    rule_b: false

    rule_c: false
''');
    var mentions = scan().root!.mentions;
    expect(mentions['rule_a']!.comment, 'too noisy for generated code');
    expect(
      mentions['rule_b']!.comment,
      'We tried this one and the churn was not worth it.',
    );
    expect(mentions['rule_c']!.comment, isNull);
  });

  test('commented-out rules are mentions, not comments on neighbours', () {
    write('analysis_options.yaml', '''
linter:
  rules:
    #avoid_web_libraries_in_flutter: false
    rule_a: true
    # - some_listed_rule
''');
    var file = scan().root!;
    expect(
      file.commentedOut,
      containsAll(['avoid_web_libraries_in_flutter', 'some_listed_rule']),
    );
    // The commented-out line above rule_a is not rule_a's why.
    expect(file.mentions['rule_a']!.comment, isNull);
  });

  test('a multi-include list applies in order', () {
    write('one.yaml', 'linter:\n  rules:\n    rule_a: true\n');
    write('two.yaml', 'linter:\n  rules:\n    rule_a: false\n');
    write('analysis_options.yaml', '''
include:
  - one.yaml
  - two.yaml
''');
    var file = scan().root!;
    expect(file.enabled, isEmpty);
    expect(file.effective['rule_a']!.via, 'two.yaml');
  });
}
