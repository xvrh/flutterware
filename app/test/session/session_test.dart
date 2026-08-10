import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware/plugins.dart' show SearchReason, searchReport;
import 'package:flutterware_app/src/plugins/native/dependencies_core.dart';
import 'package:flutterware_app/src/plugins/native/dependencies_results.dart';
import 'package:flutterware_app/src/plugins/plugin_core.dart';
import 'package:flutterware_app/src/session/session.dart';
import 'package:flutterware_app/src/shell/repo_layout.dart';

import '../support/declared_dependencies.dart';

/// Drives the real repo, because the point of a session is that it resolves a
/// real `tool/flutterware.dart`. Nothing here computes anything: the laziness
/// rule is most of what is being asserted.
void main() {
  late Session session;

  setUp(() async {
    session = await Session.open(Directory(findRepoRoot('..')!));
  });

  tearDown(() => session.dispose());

  test('resolves the repo root by walking up', () {
    // Asserted by what a root *is*, not by its name: this test used to expect
    // the directory the branch was written in, which passed in one worktree
    // and failed everywhere else.
    expect(File('${session.root}/tool/flutterware.dart').existsSync(), isTrue);
    // Deliberately not asserting on `.git`: it is a directory in the main
    // checkout and a *file* in a linked worktree, so testing for either shape
    // just swaps one environment-specific failure for another.
    // Opened from `app/`, so the root has to be strictly above it.
    expect(Directory.current.path, startsWith(session.root));
    expect(Directory.current.path, isNot(session.root));
  });

  test('resolves a core per declared plugin, in declared order', () {
    expect(session.cores.map((c) => c.id), [
      'flutterware.dependencies',
      'flutterware.assets',
      'flutterware.previews',
      'flutterware.motion',
      'flutterware.splash',
      'flutterware.server',
      'flutterware.run',
      'flutterware.scenarios',
    ]);
  });

  test('a plugin with no core registered is visible, not omitted', () async {
    // Every real plugin has a core, so this needs a build that lacks one.
    // The honest failure mode it guards: `fw` printing nothing for a declared
    // plugin would read as "this project has fewer plugins than it does".
    var bare = await Session.open(
      Directory(findRepoRoot('..')!),
      registry: PluginCoreRegistry(),
    );
    try {
      expect(bare.cores, everyElement(isA<MissingPluginCore>()));
      // One per declaration, same as a real build — a registry with nothing in
      // it must not shrink the list, which is the whole point.
      expect(bare.cores, hasLength(session.cores.length));
      for (var core in bare.cores) {
        expect(core.report.status.isEmpty, isFalse);
      }
    } finally {
      bare.dispose();
    }
  });

  test('opening a session computes nothing', () {
    var dependencies =
        session.coreById(dependenciesPluginId)! as DependenciesCore;
    expect(dependencies.packages, ['.', 'app', 'examples/example']);
    for (var path in dependencies.packages) {
      expect(dependencies.isRealised(path), isFalse);
    }
    expect(dependencies.report.toText(), contains('not computed'));
  });

  test('reports are readable without any subscriber', () {
    // The rule that makes it safe for the sidebar, `fw` and an agent to call
    // this for every plugin: a pure read of cached state.
    expect(session.reports, hasLength(session.cores.length));
    expect(session.reports.first.id, dependenciesPluginId);
  });

  group('coreByShortName', () {
    test('resolves the last dotted segment', () {
      expect(session.coreByShortName('dependencies')?.id, dependenciesPluginId);
    });

    test('resolves a full id too', () {
      expect(
        session.coreByShortName(dependenciesPluginId)?.id,
        dependenciesPluginId,
      );
    });

    test('is null rather than a guess for an unknown name', () {
      expect(session.coreByShortName('nope'), isNull);
    });
  });

  test('an unknown action is refused loudly', () async {
    var dependencies = session.coreById(dependenciesPluginId)!;
    expect(
      () => dependencies.invoke('not-an-action'),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('an action asked for by name loads what it needs', () async {
    var dependencies =
        session.coreById(dependenciesPluginId)! as DependenciesCore;
    var package = dependencies.packages.first;
    expect(dependencies.isRealised(package), isFalse);

    var result =
        (await dependencies.invoke('list', arguments: {'package': package}))!
            as DependencyListResult;

    // The inversion worth keeping: a *report* may never start work, because
    // everything reads it constantly. An action was asked for by name, and in
    // `fw` and MCP the process holds nothing — so a query that only read the
    // cache would answer "nothing" every time, which is what the plugin's two
    // deleted cache-invalidation actions did.
    expect(dependencies.isRealised(package), isTrue);
    expect(result.packages.single.path, package);
    expect(result.packages.single.direct, isA<int>());
  });

  test('the list reports where each package came from', () async {
    var dependencies =
        session.coreById(dependenciesPluginId)! as DependenciesCore;

    var result =
        (await dependencies.invoke(
              'list',
              arguments: {'package': 'examples/example'},
            ))!
            as DependencyListResult;
    var entries = result.packages.single.dependencies;

    // Every one of these was null before: the source was read off a lockfile
    // entry that does not exist beside a member of a pub workspace.
    expect(entries, isNotEmpty);
    expect(entries.map((e) => e.source), everyElement(isNotEmpty));

    var flutterware = entries.firstWhere((e) => e.name == 'flutterware');
    expect(flutterware.source, 'root', reason: 'a sibling workspace member');
    expect(flutterware.direct, isTrue);

    var flutterTest = entries.firstWhere((e) => e.name == 'flutter_test');
    expect(flutterTest.source, 'sdk');
    expect(flutterTest.dev, isTrue, reason: 'declared in dev_dependencies');

    // The counts are per-member, not per-workspace — derived from the member's
    // own pubspec rather than written down here, so adding a dependency to the
    // sample project does not fail a test about where packages come from.
    var declared = DeclaredDependencies.of('../examples/example/pubspec.yaml');
    expect(result.packages.single.direct, declared.dependencies.length);
    expect(result.packages.single.dev, declared.devs.length);
    expect(
      result.packages.single.transitive,
      greaterThan(declared.dependencies.length),
    );
  });

  test('a dependency is findable in the palette once computed', () async {
    var dependencies =
        session.coreById(dependenciesPluginId)! as DependenciesCore;
    await dependencies.invoke(
      'list',
      arguments: {'package': 'examples/example'},
    );

    var hits = searchReport(dependencies.report, 'auto_size', worktree: 'wt');

    // The projection used to be a `ViewTable`, and `searchReport` skips tables
    // because a table row has nowhere to put an address. So the plugin's only
    // search hit was ever the plugin itself.
    var hit = hits.firstWhere((e) => e.title == 'auto_size_text');
    expect(hit.reason, SearchReason.item);
    expect(hit.address.plugin, dependenciesPluginId);
    expect(hit.address.segments, [
      'examples/example',
      'packages',
      'auto_size_text',
    ]);
  });

  test('nothing is searchable before it is computed', () {
    // The laziness rule, from the search side: a report that started work just
    // because somebody typed would defeat the whole design.
    var dependencies = session.coreById(dependenciesPluginId)!;
    expect(
      searchReport(dependencies.report, 'auto_size', worktree: 'wt'),
      isEmpty,
    );
  });
}
