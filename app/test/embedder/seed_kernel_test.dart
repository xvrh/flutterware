import 'dart:convert';
import 'dart:io';

import 'package:flutterware_app/src/embedder/seed_kernel.dart';
import 'package:package_config/package_config.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// What a seed contains, and when it stops being one.
///
/// A seed is a kernel one checkout compiled and every other checkout on the
/// machine starts from, so both halves of it are safety claims rather than
/// conveniences: *only immutable trees go in*, because a library somebody edits
/// cannot be shared, and *every package in it must still resolve where it did*,
/// because the compiler's recovery from a stale seed is to discard the whole
/// thing — measured at 6.1s against 5.6s for handing it no seed at all.
///
/// Pure unit tests — no SDK, no compiler, no kernel.
void main() {
  late Directory temp;
  late String cache;
  late String sdk;
  late String project;

  /// A package rooted at [root] with a `lib/`, and the files under it.
  Package package(String name, String root, List<String> files) {
    for (var file in files) {
      File(p.join(root, 'lib', file))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('');
    }
    return Package(
      name,
      Uri.directory(root),
      packageUriRoot: Uri.directory(p.join(root, 'lib')),
      languageVersion: LanguageVersion(3, 0),
    );
  }

  Uri source(String root, String file) => Uri.file(p.join(root, 'lib', file));

  setUp(() {
    temp = Directory.systemTemp.createTempSync('fw-seed');
    cache = p.join(temp.path, 'pub-cache');
    sdk = p.join(temp.path, 'sdk');
    project = p.join(temp.path, 'worktree');
  });

  tearDown(() => temp.deleteSync(recursive: true));

  group('what goes in a seed', () {
    test('only libraries under an immutable root', () {
      var lib = p.join(cache, 'lib-1.0.0');
      var own = p.join(project, 'my_app');
      var resolution = PackageConfig([
        package('lib', lib, ['lib.dart']),
        package('my_app', own, ['app.dart']),
      ]);

      var plan = planSeed(
        sources: [source(lib, 'lib.dart'), source(own, 'app.dart')],
        resolution: resolution,
        immutableRoots: [cache, sdk],
      )!;

      expect(plan.imports, ['package:lib/lib.dart']);
      // The worktree's own package is not merely un-imported: naming it in the
      // manifest would make every checkout's own resolution invalidate the
      // seed, which is the one thing the seed exists to survive.
      expect(plan.packages.keys, ['lib']);
      expect(plan.packages['lib'], p.join(lib, 'lib'));
    });

    test('a part is left out, however it says so', () {
      var lib = p.join(cache, 'lib-1.0.0');
      var resolution = PackageConfig([
        package('lib', lib, ['lib.dart', 'declared.dart', 'says_so.dart']),
      ]);
      File(p.join(lib, 'lib', 'lib.dart')).writeAsStringSync('''
library lib;
part 'declared.dart';
''');
      // Nothing points at this one; it only says what it is. Both halves are
      // read because either alone lets a part through, and a single part in
      // the root fails the whole seed compile rather than its own line.
      File(p.join(lib, 'lib', 'says_so.dart')).writeAsStringSync('''
part of 'other.dart';
''');

      var plan = planSeed(
        sources: [
          for (var file in ['lib.dart', 'declared.dart', 'says_so.dart'])
            source(lib, file),
        ],
        resolution: resolution,
        immutableRoots: [cache],
      )!;

      expect(plan.imports, ['package:lib/lib.dart']);
    });

    test('a root that reaches nothing shared is no seed at all', () {
      var own = p.join(project, 'my_app');
      var plan = planSeed(
        sources: [source(own, 'app.dart')],
        resolution: PackageConfig([
          package('my_app', own, ['app.dart']),
        ]),
        immutableRoots: [cache],
      );
      expect(plan, isNull);
    });

    test('the root imports every library, and runs none of them', () {
      var lib = p.join(cache, 'lib-1.0.0');
      var plan = planSeed(
        sources: [source(lib, 'a.dart'), source(lib, 'b.dart')],
        resolution: PackageConfig([
          package('lib', lib, ['a.dart', 'b.dart']),
        ]),
        immutableRoots: [cache],
      )!;
      expect(plan.source, contains("import 'package:lib/a.dart' as _i0;"));
      expect(plan.source, contains("import 'package:lib/b.dart' as _i1;"));
      expect(plan.source, contains('void main() {}'));
    });
  });

  group('when a seed stops being one', () {
    late SeedStore store;
    late String lib;
    late String other;

    SeedPlan planFor(PackageConfig resolution) => planSeed(
      sources: [source(lib, 'lib.dart'), source(other, 'other.dart')],
      resolution: resolution,
      immutableRoots: [cache],
    )!;

    PackageConfig resolutionWith(String libRoot) => PackageConfig([
      package('lib', libRoot, ['lib.dart']),
      package('other', other, ['other.dart']),
    ]);

    setUp(() {
      lib = p.join(cache, 'lib-1.0.0');
      other = p.join(cache, 'other-2.0.0');
      store = SeedStore(
        engineRevision: 'engine-1',
        flavor: '--track-widget-creation',
        root: p.join(temp.path, 'kernels'),
      );
    });

    void commit(SeedPlan plan) {
      var draft = store.draft(plan);
      expect(
        draft.commit((to) => File(to).writeAsStringSync('kernel')),
        isNotNull,
      );
    }

    test('the same resolution finds it again', () {
      var resolution = resolutionWith(lib);
      commit(planFor(resolution));
      expect(store.find(resolution)?.packages, hasLength(2));
    });

    test('a package it holds, moved, is the end of it', () {
      commit(planFor(resolutionWith(lib)));
      var bumped = p.join(cache, 'lib-1.1.0');
      package('lib', bumped, ['lib.dart']);
      expect(store.find(resolutionWith(bumped)), isNull);
    });

    test('a package it does not hold may move freely', () {
      // The whole reason the manifest records what the seed *contains* rather
      // than what the project resolves: most of a lockfile's churn is in
      // packages nothing imports, and keying on those would throw the seed
      // away for every one of them.
      var unused = p.join(cache, 'unused-1.0.0');
      var resolution = PackageConfig([
        package('lib', lib, ['lib.dart']),
        package('other', other, ['other.dart']),
        package('unused', unused, ['unused.dart']),
      ]);
      commit(planFor(resolution));

      var bumped = p.join(cache, 'unused-9.9.9');
      expect(
        store.find(
          PackageConfig([
            package('lib', lib, ['lib.dart']),
            package('other', other, ['other.dart']),
            package('unused', bumped, ['unused.dart']),
          ]),
        ),
        isNotNull,
      );
    });

    test('a package it holds, gone, is the end of it', () {
      commit(planFor(resolutionWith(lib)));
      expect(
        store.find(
          PackageConfig([
            package('lib', lib, ['lib.dart']),
          ]),
        ),
        isNull,
      );
    });

    test('another engine does not share the directory', () {
      commit(planFor(resolutionWith(lib)));
      var newer = SeedStore(
        engineRevision: 'engine-2',
        flavor: '--track-widget-creation',
        root: p.join(temp.path, 'kernels'),
      );
      expect(newer.directory, isNot(store.directory));
      expect(newer.find(resolutionWith(lib)), isNull);
    });

    test('another set of compiler flags does not share it either', () {
      commit(planFor(resolutionWith(lib)));
      var without = SeedStore(
        engineRevision: 'engine-1',
        flavor: '',
        root: p.join(temp.path, 'kernels'),
      );
      expect(without.find(resolutionWith(lib)), isNull);
    });

    test('a manifest whose kernel is gone is not a seed', () {
      var resolution = resolutionWith(lib);
      commit(planFor(resolution));
      for (var entity in Directory(store.directory).listSync()) {
        if (entity.path.endsWith('.dill')) entity.deleteSync();
      }
      expect(store.find(resolution), isNull);
    });

    test('a manifest nothing can read is not a seed', () {
      var resolution = resolutionWith(lib);
      commit(planFor(resolution));
      for (var entity in Directory(store.directory).listSync()) {
        if (entity.path.endsWith('.json')) {
          File(entity.path).writeAsStringSync('not json');
        }
      }
      expect(store.find(resolution), isNull);
    });
  });

  group('naming', () {
    test('two checkouts compiling the same seed name the same file', () {
      // What makes a seed shareable at all: the name is a hash of the manifest,
      // and the root it is compiled from lives beside it rather than in either
      // checkout — so neither the path of the root nor anything else about who
      // built it reaches the kernel.
      var lib = p.join(cache, 'lib-1.0.0');
      var resolution = PackageConfig([
        package('lib', lib, ['lib.dart']),
      ]);
      var plan = planSeed(
        sources: [source(lib, 'lib.dart')],
        resolution: resolution,
        immutableRoots: [cache],
      )!;

      var names = <String>{};
      for (var checkout in ['a', 'b']) {
        var store = SeedStore(
          engineRevision: 'engine-1',
          flavor: '--track-widget-creation',
          root: p.join(temp.path, checkout, 'kernels'),
        );
        var draft = store.draft(plan);
        expect(p.isWithin(store.directory, draft.entrypoint), isTrue);
        names.add(p.basename(draft.entrypoint));
      }
      expect(names, hasLength(1));
    });
  });

  group('two checkouts at once', () {
    late SeedStore store;
    late String lib;
    late SeedPlan plan;
    late PackageConfig resolution;

    setUp(() {
      lib = p.join(cache, 'lib-1.0.0');
      resolution = PackageConfig([
        package('lib', lib, ['a.dart', 'b.dart']),
      ]);
      plan = planSeed(
        sources: [source(lib, 'a.dart'), source(lib, 'b.dart')],
        resolution: resolution,
        immutableRoots: [cache],
      )!;
      store = SeedStore(
        engineRevision: 'engine-1',
        flavor: '--track-widget-creation',
        root: p.join(temp.path, 'kernels'),
      );
    });

    List<String> namesIn(String dir) =>
        Directory(dir).listSync().map((e) => p.basename(e.path)).toList()
          ..sort();

    test('the second one does not rewrite the root under the first', () {
      // The root is named by the manifest, which is what makes two checkouts
      // produce the same kernel — and also what aims them at one path. A plain
      // write truncates the file the other one's compiler is reading, and a
      // half-read root is not a failure: it is a smaller seed that looks whole.
      var first = store.draft(plan);
      var before = File(first.entrypoint).statSync().modified;
      var second = store.draft(plan);
      expect(second.entrypoint, first.entrypoint);
      expect(File(first.entrypoint).statSync().modified, before);
    });

    test('a root someone else corrupted is written again', () {
      var draft = store.draft(plan);
      File(draft.entrypoint).writeAsStringSync('half a fi');
      store.draft(plan);
      expect(File(draft.entrypoint).readAsStringSync(), plan.source);
    });

    test('a commit leaves nothing staged, and finds itself', () {
      var draft = store.draft(plan);
      expect(
        draft.commit((to) => File(to).writeAsStringSync('kernel')),
        isNotNull,
      );
      expect(
        namesIn(store.directory).where((n) => n.endsWith('.tmp')),
        isEmpty,
      );
      expect(store.find(resolution), isNotNull);
    });

    test('a kernel half-copied by someone else is not published', () {
      // The manifest is the promise that the file beside it is loadable, so it
      // is written last and not at all when the kernel never arrived.
      var draft = store.draft(plan);
      expect(draft.commit((to) {}), isNull);
      expect(store.find(resolution), isNull);
      expect(
        namesIn(store.directory).where((n) => n.endsWith('.json')),
        isEmpty,
      );
    });

    test('a manifest another process is mid-write is not read as one', () {
      var draft = store.draft(plan);
      draft.commit((to) => File(to).writeAsStringSync('kernel'));
      // What a stage looks like from the outside. It ends in `.tmp`, so the
      // listing that looks for seeds never sees it.
      File(p.join(store.directory, 'deadbeefdeadbeef.json.999.tmp'))
          .writeAsStringSync('{"packages":');
      expect(store.find(resolution), isNotNull);
    });
  });

  group('housekeeping', () {
    late String root;

    SeedStore storeFor(String engine) => SeedStore(
      engineRevision: engine,
      flavor: '--track-widget-creation',
      root: root,
    );

    /// A seed on disk that no resolution will ever match, so it is only ever
    /// counted rather than found.
    void plant(SeedStore store, String name, DateTime at) {
      Directory(store.directory).createSync(recursive: true);
      File(p.join(store.directory, '$name.dill'))
        ..writeAsStringSync('kernel')
        ..setLastModifiedSync(at);
      File(p.join(store.directory, '$name.json')).writeAsStringSync(
        jsonEncode({
          'packages': {'nothing': p.join(cache, 'nothing-1.0.0', 'lib')},
        }),
      );
    }

    int kernelsIn(SeedStore store) =>
        Directory(store.directory)
            .listSync()
            .where((e) => e.path.endsWith('.dill'))
            .length;

    setUp(() => root = p.join(temp.path, 'kernels'));

    test('one engine keeps only the newest few', () {
      var store = storeFor('engine-1');
      var now = DateTime.now();
      for (var i = 0; i < SeedStore.keep + 2; i++) {
        plant(store, 'seed$i', now.subtract(Duration(days: i)));
      }
      store.find(PackageConfig.empty);
      expect(kernelsIn(store), SeedStore.keep);
      // The newest survive, so a seed nothing starts from is the one that goes
      // — `find` touches the one it hands out.
      expect(File(p.join(store.directory, 'seed0.dill')).existsSync(), isTrue);
      expect(File(p.join(store.directory, 'seed4.dill')).existsSync(), isFalse);
    });

    test('an engine nobody starts from any more is dropped whole', () {
      var old = storeFor('engine-1');
      plant(old, 'seed', DateTime.now().subtract(SeedStore.forget * 2));
      var current = storeFor('engine-2');
      plant(current, 'seed', DateTime.now());

      current.find(PackageConfig.empty);
      expect(Directory(old.directory).existsSync(), isFalse);
      expect(Directory(current.directory).existsSync(), isTrue);
    });

    test('the seed it hands back is not the one it evicts', () {
      // Sweeping before choosing lets a lookup delete its own answer: with
      // [SeedStore.keep] full, the oldest goes, and the oldest is exactly the
      // project you have not opened in a while.
      var store = storeFor('engine-1');
      var lib = p.join(cache, 'lib-1.0.0');
      var resolution = PackageConfig([
        package('lib', lib, ['a.dart']),
      ]);
      var plan = planSeed(
        sources: [source(lib, 'a.dart')],
        resolution: resolution,
        immutableRoots: [cache],
      )!;
      var draft = store.draft(plan);
      draft.commit((to) => File(to).writeAsStringSync('kernel'));
      var mine = p.join(store.directory, p.basename(draft.entrypoint));
      File(
        p.setExtension(mine, '.dill'),
      ).setLastModifiedSync(DateTime.now().subtract(const Duration(days: 3)));
      // Everything else is newer, so a sweep that ran first would take mine.
      for (var i = 0; i < SeedStore.keep; i++) {
        plant(store, 'other$i', DateTime.now());
      }

      expect(store.find(resolution), isNotNull);
      expect(File(p.setExtension(mine, '.dill')).existsSync(), isTrue);
      expect(kernelsIn(store), SeedStore.keep);
    });

    test('a directory being built in is not read as an expired one', () {
      // `draft` writes the root before any kernel exists, and the kernel
      // arrives as a `.tmp` that is renamed at the end — so for a whole
      // excursion another engine's directory holds no `.dill`. Deleting it
      // takes the root out from under that compiler.
      var building = storeFor('engine-1');
      var lib = p.join(cache, 'lib-1.0.0');
      building.draft(
        planSeed(
          sources: [source(lib, 'a.dart')],
          resolution: PackageConfig([
            package('lib', lib, ['a.dart']),
          ]),
          immutableRoots: [cache],
        )!,
      );
      expect(
        Directory(building.directory)
            .listSync()
            .where((e) => e.path.endsWith('.dill')),
        isEmpty,
      );

      storeFor('engine-2').find(PackageConfig.empty);
      expect(Directory(building.directory).existsSync(), isTrue);
    });

    test('an engine still in use is left alone', () {
      var other = storeFor('engine-1');
      plant(other, 'seed', DateTime.now());
      storeFor('engine-2').find(PackageConfig.empty);
      expect(Directory(other.directory).existsSync(), isTrue);
    });
  });

  /// A seed that exists is not therefore the seed to have.
  ///
  /// [SeedStore.find] has always preferred the largest match and the store has
  /// always kept three, so a machine was already built to hold and pick the
  /// biggest seed it had — but while a seed was written only into an empty
  /// store, nothing ever wrote a second one. First writer won permanently:
  /// measured, a 20-package seed left by a sample project served this repo's
  /// 57-package catalog at 3877ms against 1671ms for one of its own, and no
  /// start was ever going to replace it.
  group('growing a seed somebody else left', () {
    late SeedStore store;
    late String small;
    late String big;

    /// A resolution holding both packages, so a seed of either matches it.
    PackageConfig resolution() => PackageConfig([
      package('small', small, ['small.dart']),
      package('big', big, ['big.dart']),
    ]);

    SeedKernel commit(List<String> roots) {
      var plan = planSeed(
        sources: [
          for (var root in roots) source(root, '${p.basename(root)}.dart'),
        ],
        resolution: resolution(),
        immutableRoots: [cache],
      )!;
      var draft = store.draft(plan);
      expect(
        draft.commit((to) => File(to).writeAsStringSync('kernel')),
        isNotNull,
      );
      return store.find(resolution())!;
    }

    Set<String> reaching(List<String> roots) => reachedPackages(
      sources: [
        for (var root in roots) source(root, '${p.basename(root)}.dart'),
      ],
      resolution: resolution(),
      immutableRoots: [cache],
    );

    setUp(() {
      small = p.join(cache, 'small');
      big = p.join(cache, 'big');
      store = SeedStore(
        engineRevision: 'engine-1',
        flavor: '--track-widget-creation',
        root: p.join(temp.path, 'kernels'),
      );
    });

    test('a program reaching more than the seed holds asks to grow it', () {
      var seed = commit([small]);
      expect(seedWouldGrow(seed, reaching([small, big])), isTrue);
    });

    test('a program reaching exactly what the seed holds does not', () {
      var seed = commit([small]);
      expect(seedWouldGrow(seed, reaching([small])), isFalse);
    });

    test('a program reaching less than the seed holds does not', () {
      var seed = commit([small, big]);
      expect(seedWouldGrow(seed, reaching([small])), isFalse);
    });

    test('an overlap reaching more still grows it', () {
      // **The case a strict-superset rule got wrong, and the reason this test
      // is here rather than its opposite.** Measured: this repo's catalog
      // reaches 62 packages against the 20 in the seed a sample project had
      // left, and 3 of those 20 the catalog never reaches — a sample app uses
      // localisations and an http client that a widget gallery does not. Two
      // programs in one workspace normally overlap without either containing
      // the other, so a superset rule leaves the seed stunted for ever.
      //
      // Saying yes displaces nothing: the grown seed lands beside the one it
      // grew from, under its own name.
      var seed = commit([small, big]);
      var sideways = p.join(cache, 'sideways');
      var third = p.join(cache, 'third');
      var wider = PackageConfig([
        package('small', small, ['small.dart']),
        package('big', big, ['big.dart']),
        package('sideways', sideways, ['sideways.dart']),
        package('third', third, ['third.dart']),
      ]);
      expect(
        seedWouldGrow(
          seed,
          reachedPackages(
            sources: [
              source(small, 'small.dart'),
              source(sideways, 'sideways.dart'),
              source(third, 'third.dart'),
            ],
            resolution: wider,
            immutableRoots: [cache],
          ),
        ),
        isTrue,
      );
    });

    test('and the one reaching less then has nothing to write', () {
      // Why growth cannot go round in circles: whoever reaches more writes, and
      // the store hands the bigger seed back to the one reaching less, which
      // stops there.
      var seed = commit([small, big]);
      expect(seedWouldGrow(seed, reaching([small])), isFalse);
    });

    test('the grown seed is what the next start is handed', () {
      commit([small]);
      var grown = commit([small, big]);
      expect(grown.packages.keys, containsAll(['small', 'big']));
      // Both are still here — the small one is another project's and matches
      // resolutions the big one does not.
      expect(
        Directory(store.directory)
            .listSync()
            .where((e) => e.path.endsWith('.dill')),
        hasLength(2),
      );
    });

    test('a seed already written is recognised before it is written twice', () {
      // The estimate that decides is cheaper than the plan that writes, so it
      // can come out a package high. This is what stops that costing an
      // excursion on every start for ever.
      var plan = planSeed(
        sources: [source(small, 'small.dart')],
        resolution: resolution(),
        immutableRoots: [cache],
      )!;
      expect(store.holds(plan), isFalse);
      commit([small]);
      expect(store.holds(plan), isTrue);
    });
  });

  group('which packages a program reaches', () {
    test('counts the shared ones and no others', () {
      var lib = p.join(cache, 'lib-1.0.0');
      var own = p.join(project, 'my_app');
      var resolution = PackageConfig([
        package('lib', lib, ['lib.dart']),
        package('my_app', own, ['app.dart']),
      ]);

      expect(
        reachedPackages(
          sources: [source(lib, 'lib.dart'), source(own, 'app.dart')],
          resolution: resolution,
          immutableRoots: [cache],
        ),
        {'lib'},
      );
    });

    test('agrees with the plan it is an estimate of', () {
      // The claim [reachedPackages] makes about itself, and the reason it is
      // allowed to skip reading every file: a part lives in the package of the
      // library declaring it, so dropping the parts drops no package.
      var lib = p.join(cache, 'lib-1.0.0');
      File(p.join(lib, 'lib', 'lib.dart'))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync("part 'part.dart';");
      File(p.join(lib, 'lib', 'part.dart')).writeAsStringSync('part of lib;');
      var resolution = PackageConfig([package('lib', lib, [])]);
      var sources = [source(lib, 'lib.dart'), source(lib, 'part.dart')];

      var plan = planSeed(
        sources: sources,
        resolution: resolution,
        immutableRoots: [cache],
      )!;
      expect(plan.imports, hasLength(1));
      expect(
        reachedPackages(
          sources: sources,
          resolution: resolution,
          immutableRoots: [cache],
        ),
        plan.packages.keys.toSet(),
      );
    });
  });
}
