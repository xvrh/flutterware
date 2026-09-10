import 'dart:io';

import 'package:flutterware_app/src/embedder/build_directory.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/lock_holder.dart';

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('fw_build_dir');
  });

  tearDown(() {
    debugReleaseBuildLanes();
    root.deleteSync(recursive: true);
  });

  group('claims', () {
    test('every claim is its own directory, and it exists', () {
      var first = claimBuildDirectory(root.path, root: comparisonBuildRoot);
      var second = claimBuildDirectory(root.path, root: comparisonBuildRoot);

      expect(first, isNot(second));
      for (var claim in [first, second]) {
        expect(p.url.isWithin(comparisonBuildRoot, claim), isTrue);
        expect(Directory(p.join(root.path, claim)).existsSync(), isTrue);
      }
    });

    test('release deletes the claim and only the claim', () {
      var kept = claimBuildDirectory(root.path, root: comparisonBuildRoot);
      var released = claimBuildDirectory(root.path, root: comparisonBuildRoot);
      File(p.join(root.path, released, 'previews.dill'))
          .writeAsStringSync('kernel');

      releaseBuildDirectory(root.path, released, root: comparisonBuildRoot);

      expect(Directory(p.join(root.path, released)).existsSync(), isFalse);
      expect(Directory(p.join(root.path, kept)).existsSync(), isTrue);
    });

    test('release refuses a directory it never claimed', () {
      // The guard between "delete this run's artifacts" and "delete the warm
      // lane's": a default `build/flutterware` handed over by mistake must be
      // an error, not the panel's dill gone.
      expect(
        () => releaseBuildDirectory(
          root.path,
          defaultBuildRoot,
          root: comparisonBuildRoot,
        ),
        throwsArgumentError,
      );
    });

    test('a released claim that is already gone is not a failure', () {
      var claim = claimBuildDirectory(root.path, root: comparisonBuildRoot);
      Directory(p.join(root.path, claim)).deleteSync(recursive: true);

      // A base checkout somebody disposed of first takes the claim with it.
      expect(
        () =>
            releaseBuildDirectory(root.path, claim, root: comparisonBuildRoot),
        returnsNormally,
      );
    });

    test('claiming sweeps what a crashed run left, and nothing newer', () {
      var crashed = claimBuildDirectory(root.path, root: comparisonBuildRoot);
      File(p.join(root.path, crashed, 'scenarios.dill')).writeAsStringSync('k');
      // Released first, or it counts as ours and the sweep leaves it alone
      // however old it is — which is the point of `_ours` and is its own test
      // below. Here the directory is put back afterwards, so what is left is
      // a claim with a stamp and no owner: exactly what a crash leaves.
      releaseBuildDirectory(root.path, crashed, root: comparisonBuildRoot);
      var abandoned = Directory(p.join(root.path, crashed))
        ..createSync(recursive: true);
      File(p.join(abandoned.path, '.claim'))
        ..writeAsStringSync('')
        ..setLastModifiedSync(DateTime.now().subtract(const Duration(days: 2)));

      var live = claimBuildDirectory(root.path, root: comparisonBuildRoot);
      // Not a claim — no stamp — so however old, it is not the sweep's to
      // touch.
      var foreign = Directory(p.join(root.path, comparisonBuildRoot, 'foreign'))
        ..createSync(recursive: true);

      var claim = claimBuildDirectory(root.path, root: comparisonBuildRoot);

      expect(abandoned.existsSync(), isFalse);
      expect(foreign.existsSync(), isTrue);
      for (var survivor in [live, claim]) {
        expect(Directory(p.join(root.path, survivor)).existsSync(), isTrue);
      }
    });

    test('an aged claim this process still holds survives the sweep', () {
      // The long-lived session the age rule alone would have evicted: a studio
      // that lost the race for the shared lane and has been up for two days is
      // still building in its claim.
      var mine = claimBuildDirectory(root.path, root: sessionBuildRoot);
      File(
        p.join(root.path, mine, '.claim'),
      ).setLastModifiedSync(DateTime.now().subtract(const Duration(days: 2)));

      claimBuildDirectory(root.path, root: sessionBuildRoot);

      expect(Directory(p.join(root.path, mine)).existsSync(), isTrue);
    });
  });

  group('lanes', () {
    test('the first taker gets the directory it asked for', () {
      expect(
        takeBuildLane(
          root.path,
          preferred: defaultBuildRoot,
          program: 'previews',
        ),
        defaultBuildRoot,
      );
      expect(
        File(p.join(root.path, defaultBuildRoot, 'previews.lane')).existsSync(),
        isTrue,
      );
    });

    test('two programs share one directory', () {
      // Previews and scenarios both build in `build/flutterware`, and always
      // have: their dills, bundles and entrypoints are named apart. Only two
      // hosts on the *same* program tear anything.
      var previews = takeBuildLane(
        root.path,
        preferred: defaultBuildRoot,
        program: 'previews',
      );
      var scenarios = takeBuildLane(
        root.path,
        preferred: defaultBuildRoot,
        program: 'scenarios',
      );

      expect(previews, defaultBuildRoot);
      expect(scenarios, defaultBuildRoot);
    });

    test('asking twice answers the same lane', () {
      // A host disposed and rebuilt — `restartRunner`, a core reloaded under a
      // mounted panel — must come back to the directory it was building in
      // rather than re-race for it and land somewhere colder.
      var first = takeBuildLane(
        root.path,
        preferred: defaultBuildRoot,
        program: 'previews',
      );
      var again = takeBuildLane(
        root.path,
        preferred: defaultBuildRoot,
        program: 'previews',
      );

      expect(again, first);
    });

    test('a directory that is already a claim is handed back untouched', () {
      var claim = claimBuildDirectory(root.path, root: comparisonBuildRoot);

      expect(
        takeBuildLane(root.path, preferred: claim, program: 'previews'),
        claim,
      );
      // Nothing was locked: a claim is private by construction, and a lock
      // file per comparison would be a handle held to process exit for
      // nothing.
      expect(
        File(p.join(root.path, claim, 'previews.lane')).existsSync(),
        isFalse,
      );
    });

    test('a lane another process holds sends this one to a claim', () async {
      // The lock has to be taken by a *different* process to mean anything:
      // advisory locks are per process, so a second take inside this one
      // would succeed and prove nothing.
      var lane = File(p.join(root.path, defaultBuildRoot, 'previews.lane'))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('');
      var holder = await holdLock(lane.path);
      try {
        var taken = takeBuildLane(
          root.path,
          preferred: defaultBuildRoot,
          program: 'previews',
        );

        expect(taken, isNot(defaultBuildRoot));
        expect(p.url.isWithin(sessionBuildRoot, taken), isTrue);
        expect(Directory(p.join(root.path, taken)).existsSync(), isTrue);
      } finally {
        // Ends it early so the claim it was guarding can be released; the
        // tear-down registered in `holdLock` is what makes that unnecessary
        // rather than merely tidy.
        holder.kill();
        await holder.exitCode;
      }
    });
  });
}
