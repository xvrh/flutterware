import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware/plugins.dart';
// ignore: implementation_imports
import 'package:flutterware/src/log_client.dart';
import 'package:flutterware_app/src/context.dart';
import 'package:flutterware_app/src/lints/model/pricing.dart';
import 'package:flutterware_app/src/lints/model/rule_catalog.dart';
import 'package:flutterware_app/src/plugins/native/lints_core.dart';
import 'package:flutterware_app/src/plugins/native/lints_results.dart';
import 'package:flutterware_app/src/plugins/plugin_host.dart';
import 'package:flutterware_app/src/shell/workspace.dart';
import 'package:flutterware_app/src/shell/worktree.dart';
import 'package:flutterware_app/src/utils/flutter_sdk.dart';
import 'package:flutterware_app/src/utils/run_dir.dart';
import 'package:path/path.dart' as p;

/// Everything asserted here is read through [PluginReport] and the actions —
/// the same surfaces the sidebar, `fw` and an agent see.
void main() {
  late Directory scratch;
  late Directory root;
  late Directory sdk;

  const dartVersion = '3.13.0-fake';

  void write(String relative, String content) {
    var file = File(p.join(root.path, relative));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
  }

  /// Seeds the catalog store's disk cache, so the whole test runs offline.
  Directory seedCatalog(List<Map<String, Object?>> rules) {
    var cache = Directory(p.join(scratch.path, 'catalog-cache'))
      ..createSync(recursive: true);
    File(
      p.join(cache.path, '$dartVersion.json'),
    ).writeAsStringSync(jsonEncode(rules));
    return cache;
  }

  Map<String, Object?> rule(String name, {String since = '2.0'}) => {
    'name': name,
    'description': 'about $name',
    'state': 'stable',
    'sinceDartSdk': since,
  };

  LintsCore core({Directory? catalogCache, RunProcess? runProcess}) {
    var worktree = Worktree(path: root.path);
    return LintsCore(
      PluginHost(
        id: lintsPluginId,
        label: 'Lints',
        worktree: worktree,
        workspace: Workspace(
          root: worktree.path,
          declared: [Pkg('.')],
          discovered: ['.'],
          appContext: AppContext(logger: LogClient.print()),
          flutterSdk: FlutterSdkPath(sdk.path),
        ),
        config: {},
      ),
      catalogStore: LintCatalogStore(
        cacheDirectory: catalogCache ?? seedCatalog([]),
      ),
      pricer: LintPricer(runProcess: runProcess),
    );
  }

  setUp(() {
    scratch = Directory.systemTemp.createTempSync('fw_lints_core_test');
    root = Directory(p.join(scratch.path, 'repo'))..createSync();
    sdk = Directory(p.join(scratch.path, 'flutter'))..createSync();
    File(p.join(sdk.path, 'bin', 'cache', 'dart-sdk', 'version'))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('$dartVersion\n');
    flutterwareDirOverride = p.join(scratch.path, 'dot-flutterware');
  });

  tearDown(() {
    flutterwareDirOverride = null;
    if (scratch.existsSync()) scratch.deleteSync(recursive: true);
  });

  test('reading the report starts no work', () {
    write('analysis_options.yaml', 'linter:\n  rules:\n    - rule_a\n');
    var lints = core();
    expect(lints.report.status, Status.none);
    expect(lints.classification, isNull);
  });

  test('status classifies against the cached catalog, offline', () async {
    write('analysis_options.yaml', '''
linter:
  rules:
    on_rule: true
    off_rule: false # not for us
''');
    var cache = seedCatalog([
      rule('on_rule'),
      rule('off_rule'),
      rule('fresh_rule', since: '3.13'),
    ]);
    var lints = core(catalogCache: cache);

    var result = (await lints.invoke('status'))! as LintsStatusResult;
    expect(result.dartVersion, dartVersion);
    expect(result.catalogAvailable, isTrue);
    expect(result.files.single.path, 'analysis_options.yaml');

    String bucketOf(String name) =>
        result.rules.singleWhere((r) => r.name == name).bucket;
    expect(bucketOf('on_rule'), 'enabled');
    expect(bucketOf('off_rule'), 'dismissed');
    expect(bucketOf('fresh_rule'), 'unevaluated');
    expect(
      result.rules.singleWhere((r) => r.name == 'off_rule').comment,
      'not for us',
    );

    // And the report says the one number the rail should carry.
    expect(lints.report.status.message, contains('1 unevaluated'));
    expect(lints.report.badge, const StatusBadge.count(1));
  });

  test('price runs one analyzer pass and remembers it across cores', () async {
    write('analysis_options.yaml', 'linter:\n  rules:\n    on_rule: true\n');
    var cache = seedCatalog([rule('on_rule'), rule('fresh_rule')]);
    var analyzeRuns = 0;
    var lints = core(
      catalogCache: cache,
      runProcess: (executable, arguments, {workingDirectory}) async {
        analyzeRuns++;
        expect(executable, p.join(sdk.path, 'bin', 'dart'));
        expect(arguments, ['analyze', '--format=json', '.']);
        return ProcessResult(
          0,
          3,
          jsonEncode({
            'version': 1,
            'diagnostics': [
              {'code': 'fresh_rule'},
              {'code': 'fresh_rule'},
            ],
          }),
          '',
        );
      },
    );

    var result = (await lints.invoke('price'))! as LintsPriceResult;
    expect(analyzeRuns, 1);
    expect(result.counts, {'fresh_rule': 2});
    expect(result.freeWins, 0);

    // A new core over the same repo reads the persisted pricing — a price
    // that costs seconds to minutes should survive a restart.
    var reborn = core(catalogCache: cache);
    var status = (await reborn.invoke('status'))! as LintsStatusResult;
    expect(status.pricing, isNotNull);
    expect(status.rules.singleWhere((r) => r.name == 'fresh_rule').price, 2);
  });

  test('price without a catalog refuses with the reason', () async {
    write('analysis_options.yaml', 'linter:\n');
    var lints = core(
      catalogCache: Directory(p.join(scratch.path, 'empty-cache'))
        ..createSync(),
    );
    await expectLater(lints.invoke('price'), throwsStateError);
  });

  test('an unknown action names what is declared', () async {
    await expectLater(core().invoke('nope'), throwsArgumentError);
  });
}
