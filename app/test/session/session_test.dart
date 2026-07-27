import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware_app/src/plugins/native/dependencies_core.dart';
import 'package:flutterware_app/src/plugins/plugin_core.dart';
import 'package:flutterware_app/src/session/session.dart';
import 'package:flutterware_app/src/shell/repo_layout.dart';

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
      'flutterware.ui_catalog',
    ]);
  });

  test('a plugin with no core registered is visible, not omitted', () async {
    // Both real plugins have cores, so this needs a build that lacks one.
    // The honest failure mode it guards: `fw` printing nothing for a declared
    // plugin would read as "this project has fewer plugins than it does".
    var bare = await Session.open(
      Directory(findRepoRoot('..')!),
      registry: PluginCoreRegistry(),
    );
    try {
      expect(bare.cores, everyElement(isA<MissingPluginCore>()));
      expect(bare.cores, hasLength(2));
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
    expect(session.reports, hasLength(2));
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

  test('reload with nothing tracked stays lazy', () async {
    var dependencies =
        session.coreById(dependenciesPluginId)! as DependenciesCore;
    await dependencies.invoke('reload');
    // Reload refreshes what is being watched. With nothing watched there is
    // nothing loaded to make stale, and starting the work here would turn an
    // action meant to *redo* work into one that begins it.
    for (var path in dependencies.packages) {
      expect(dependencies.isRealised(path), isFalse);
    }
  });
}
