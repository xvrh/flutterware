import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware_app/src/lints/model/classification.dart';
import 'package:flutterware_app/src/lints/model/options_scan.dart';
import 'package:flutterware_app/src/lints/model/rule_catalog.dart';
import 'package:path/path.dart' as p;

LintRule rule(
  String name, {
  String state = 'stable',
  String since = '2.0',
  List<String> incompatible = const [],
}) => LintRule(
  name: name,
  description: 'about $name',
  details: '',
  state: state,
  sinceDartSdk: since,
  categories: const [],
  incompatible: incompatible,
  fixStatus: 'hasFix',
);

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('fw_lints_classify');
  });

  tearDown(() {
    root.deleteSync(recursive: true);
  });

  LintOptionsScan scanOf(Map<String, String> files) {
    for (var entry in files.entries) {
      var file = File(p.join(root.path, entry.key));
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(entry.value);
    }
    return LintOptionsScanner(repoRoot: root.path).scan();
  }

  test('the four buckets, over the union of every file', () {
    var catalog = LintCatalog(
      dartVersion: '3.13.0',
      rules: [
        rule('on_everywhere'),
        rule('off_at_root'),
        rule('only_in_comment'),
        rule('never_looked_at', since: '3.13'),
        rule('gone', state: 'removed'),
      ],
    );
    var scan = scanOf({
      'analysis_options.yaml': '''
linter:
  rules:
    on_everywhere: true
    off_at_root: false # deliberate
    # only_in_comment: false
''',
      'member/analysis_options.yaml': 'include: ../analysis_options.yaml\n',
    });
    var classification = LintsClassification.build(
      scan: scan,
      catalog: catalog,
    );

    ClassifiedLint of(String name) =>
        classification.rules.singleWhere((r) => r.name == name);

    expect(of('on_everywhere').bucket, LintBucket.enabled);
    expect(of('on_everywhere').files, [
      'analysis_options.yaml',
      'member/analysis_options.yaml',
    ]);
    expect(of('off_at_root').bucket, LintBucket.dismissed);
    expect(of('off_at_root').comment, 'deliberate');
    expect(of('only_in_comment').bucket, LintBucket.mentioned);
    expect(of('never_looked_at').bucket, LintBucket.unevaluated);
    // A removed rule nobody configured is not "unevaluated" — it cannot be
    // enabled, so there is nothing to evaluate.
    expect(classification.rules.where((r) => r.name == 'gone'), isEmpty);
  });

  test('an ignore severity dismisses as surely as rule: false', () {
    var catalog = LintCatalog(dartVersion: '3.13.0', rules: [rule('quiet')]);
    var scan = scanOf({
      'analysis_options.yaml': '''
analyzer:
  errors:
    quiet: ignore
''',
    });
    var classification = LintsClassification.build(
      scan: scan,
      catalog: catalog,
    );
    expect(classification.rules.single.bucket, LintBucket.dismissed);
  });

  test('an ignored analyzer diagnostic is not an unknown rule', () {
    // `analyzer: errors:` legitimately names non-lint codes; only a name
    // spelled in a `linter: rules:` list deserves the typo warning.
    var catalog = LintCatalog(dartVersion: '3.13.0', rules: [rule('real')]);
    var scan = scanOf({
      'analysis_options.yaml': '''
analyzer:
  errors:
    unused_import: ignore
''',
    });
    var classification = LintsClassification.build(
      scan: scan,
      catalog: catalog,
    );
    expect(classification.unknownNames, isEmpty);
    expect(classification.count(LintBucket.dismissed), 0);
  });

  test('a configured name the catalog does not know rides separately', () {
    var catalog = LintCatalog(dartVersion: '3.13.0', rules: [rule('real')]);
    var scan = scanOf({
      'analysis_options.yaml': '''
linter:
  rules:
    real: true
    avoid_typoes: true
''',
    });
    var classification = LintsClassification.build(
      scan: scan,
      catalog: catalog,
    );
    expect(classification.unknownNames, ['avoid_typoes']);
    expect(classification.rules.map((r) => r.name), ['real']);
  });

  test(
    'without a catalog the local buckets stand, unevaluated is unknowable',
    () {
      var scan = scanOf({
        'analysis_options.yaml': '''
linter:
  rules:
    something: true
    other: false
''',
      });
      var classification = LintsClassification.build(scan: scan, catalog: null);
      expect(classification.hasCatalog, isFalse);
      expect(classification.count(LintBucket.enabled), 1);
      expect(classification.count(LintBucket.dismissed), 1);
      expect(classification.count(LintBucket.unevaluated), 0);
    },
  );

  test('newest-first ordering reads sinceDartSdk numerically', () {
    var catalog = LintCatalog(
      dartVersion: '3.13.0',
      rules: [
        rule('old', since: '2.16'),
        rule('newer', since: '3.9'),
        rule('newest', since: '3.13'),
      ],
    );
    var classification = LintsClassification.build(
      scan: scanOf({'analysis_options.yaml': ''}),
      catalog: catalog,
    );
    var sorted = classification.rules.toList()..sort(compareBySinceDesc);
    expect(sorted.map((r) => r.name), ['newest', 'newer', 'old']);
  });
}
