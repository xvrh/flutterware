import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware/plugins.dart';
import 'package:flutterware_app/src/changes/changes_config_cache.dart';
import 'package:flutterware_app/src/worktrees/facts_store.dart';
import 'package:path/path.dart' as p;

/// The one mechanism behind all four rows of the design's table: **one writer,
/// one reader.** Whatever executes `tool/flutterware.dart` writes what it got,
/// stamped with the file it read; everything that ranks reads that.
void main() {
  late Directory worktree;
  late File cacheFile;

  WorktreeFactsStore openStore() =>
      WorktreeFactsStore.open(worktree.path, at: cacheFile);

  File configFile() => File(p.join(worktree.path, 'tool', 'flutterware.dart'));

  void writeConfigFile(String source) => configFile()
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(source);

  setUp(() {
    worktree = Directory.systemTemp.createTempSync('changes-config-');
    cacheFile = File(p.join(worktree.path, '.cache', 'worktrees.json'));
    addTearDown(() => worktree.deleteSync(recursive: true));
  });

  test('nothing cached ranks by the built-in defaults', () {
    writeConfigFile('void main() {}');
    var resolved = resolveChangesConfig(worktree.path, openStore());
    expect(resolved.state, ChangesConfigState.none);
    expect(resolved.config, isNull);
    expect(resolved.notice, isNull);
  });

  test('a worktree with no config file has no key to cache against', () {
    expect(changesConfigKey(worktree.path), isNull);
    // And remembering is a no-op rather than an entry that can never validate.
    var store = openStore();
    rememberChangesConfig(
      worktree.path,
      const ChangesConfig(noise: ['*.g.dart']),
      store,
    );
    expect(store.changesConfig(worktree.path), isNull);
  });

  test('the value survives a relaunch, and reads as fresh', () {
    writeConfigFile('void main() {}');
    rememberChangesConfig(
      worktree.path,
      const ChangesConfig(attention: ['db/**'], base: 'develop'),
      openStore(),
    );

    // A second store over the same file — this is the "closed worktree on a
    // later launch" case, which is the whole reason the cache exists.
    var resolved = resolveChangesConfig(worktree.path, openStore());
    expect(resolved.state, ChangesConfigState.fresh);
    expect(resolved.config?.attention, ['db/**']);
    expect(resolved.config?.base, 'develop');
    expect(resolved.notice, isNull);
  });

  test('editing the config file makes the cached value stale, and says so', () {
    writeConfigFile('void main() {}');
    rememberChangesConfig(
      worktree.path,
      const ChangesConfig(attention: ['db/**']),
      openStore(),
    );

    // Size moves, so the key moves regardless of filesystem mtime resolution.
    writeConfigFile('void main() {} // one more comment');

    var resolved = resolveChangesConfig(worktree.path, openStore());
    expect(resolved.state, ChangesConfigState.stale);
    // Still ranked by: yesterday's rules beat no rules.
    expect(resolved.config?.attention, ['db/**']);
    expect(resolved.notice, contains('changed since'));
  });

  test('deleting the config file is not a stale cache — it is no config', () {
    // The one case where the cache would be *wrong* rather than merely old:
    // ranking by rules the user removed.
    writeConfigFile('void main() {}');
    rememberChangesConfig(
      worktree.path,
      const ChangesConfig(noise: ['**/*.sql']),
      openStore(),
    );
    configFile().deleteSync();

    var resolved = resolveChangesConfig(worktree.path, openStore());
    expect(resolved.state, ChangesConfigState.none);
    expect(resolved.config, isNull);
  });

  test('a manifest declaring nothing is still an answer worth caching', () {
    writeConfigFile('void main() {}');
    rememberChangesConfig(worktree.path, null, openStore());

    var resolved = resolveChangesConfig(worktree.path, openStore());
    // Fresh, not unknown: "this project says nothing" is what was executed.
    expect(resolved.state, ChangesConfigState.fresh);
    expect(resolved.config?.isEmpty, isTrue);
  });

  test('writing an unchanged value does not rewrite the file', () {
    writeConfigFile('void main() {}');
    const config = ChangesConfig(noise: ['*.g.dart']);
    rememberChangesConfig(worktree.path, config, openStore());
    var first = cacheFile.lastModifiedSync();

    rememberChangesConfig(worktree.path, config, openStore());
    expect(cacheFile.lastModifiedSync(), first);
  });

  test('the cache never takes the whole store down with it', () {
    // Half-written, or written by a version that spelled things differently.
    cacheFile
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('{"changesConfigs": {"x": {"nope": 1}}}');
    expect(openStore().changesConfig('x'), isNull);
  });

  test('a stale store instance no longer reverts a fresher write', () {
    // **The bug this test exists for, found by running the app twice.** The
    // store used to write the whole file from its open-time snapshot, so an
    // instance opened at startup — the explorer's — saved its sweep a second
    // after the shell wrote the changes config and reverted it. Two openers
    // in one process were fenced off by `WorktreeFactsController.store`, but
    // two *processes* — a Studio per worktree — were the same bug with no
    // fence possible. `save` now merges with the file first, so the stale
    // copy folds the fresher write in instead of erasing it.
    writeConfigFile('void main() {}');

    var explorer = openStore(); // opened first, knows nothing
    rememberChangesConfig(
      worktree.path,
      const ChangesConfig(noise: ['*.g.dart']),
      openStore(),
    );
    expect(resolveChangesConfig(worktree.path, openStore()).config, isNotNull);

    explorer.save();

    expect(
      resolveChangesConfig(worktree.path, openStore()).config,
      isNotNull,
      reason: 'the merge keeps the write the stale copy never saw',
    );
  });

  test('one instance keeps both writers', () {
    writeConfigFile('void main() {}');
    var shared = openStore();
    rememberChangesConfig(
      worktree.path,
      const ChangesConfig(noise: ['*.g.dart']),
      shared,
    );
    shared
      ..markOpened(worktree.path, DateTime.utc(2026))
      ..save();

    var reopened = openStore();
    expect(reopened.changesConfig(worktree.path)?.config.noise, ['*.g.dart']);
    expect(reopened.openedAt(worktree.path), DateTime.utc(2026));
  });

  test('the key moves when the file does, and not otherwise', () {
    writeConfigFile('void main() {}');
    var key = changesConfigKey(worktree.path);
    expect(changesConfigKey(worktree.path), key);
    writeConfigFile('void main() {} // longer');
    expect(changesConfigKey(worktree.path), isNot(key));
  });
}
