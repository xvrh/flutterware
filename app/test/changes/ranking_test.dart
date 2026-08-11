import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware/plugins.dart';
import 'package:flutterware_app/src/changes/patch_index.dart';
import 'package:flutterware_app/src/changes/ranking.dart';

/// Path in, **tier and reason out**. The reason is asserted everywhere, not
/// just the tier: the row promises to name the rule that fired, and a badge
/// nobody can trace back to a line of config is magic.
void main() {
  FileChange file(String path, {int added = 5, int removed = 5}) => FileChange(
    path: path,
    status: ChangeStatus.modified,
    added: added,
    removed: removed,
    hunks: const [],
    byteStart: 0,
    byteEnd: 0,
  );

  RankedFile rank(String path, {ChangesConfig? config}) =>
      rankChanges([file(path)], config: config).files.single;

  group('with no config at all', () {
    test('pins nothing at all, because it cannot know what matters', () {
      // **There used to be a built-in attention list** — `**/migrations/**`,
      // `openapi.yaml`, `pubspec.yaml`, `.github/workflows/**` — and every one
      // of those was a guess about somebody else's project. flutterware does
      // not know whether a repository has migrations, and putting a file under
      // a heading that says *look here first* is a claim only the person
      // reading it can make.
      for (var path in [
        'db/migrations/001_users.sql',
        'openapi.yaml',
        'app/pubspec.yaml',
        '.github/workflows/ci.yaml',
        'tool/flutterware.dart',
      ]) {
        expect(
          rank(path).tier,
          isNot(RankTier.attention),
          reason: "$path is the project's to pin, not ours",
        );
      }
    });

    test('demotes nothing either — there is nowhere to demote to', () {
      // The `noise` tier is gone, and with it the built-in list that put
      // `*.g.dart`, `pubspec.lock` and `build/` behind a lens. Every one of
      // these is now an ordinary row in an ordinary tree.
      for (var path in [
        'lib/model.g.dart',
        'app/pubspec.lock',
        'lib/src/shapes.generated.dart',
        'build/app/outputs/x.apk',
        'test/__snapshots__/a.json',
      ]) {
        expect(rank(path).tier, RankTier.ordinary, reason: path);
        expect(rank(path).reason, isNull, reason: path);
      }
    });

    test('leaves ordinary code alone, with nothing to explain', () {
      var ranked = rank('lib/src/auth.dart');
      expect(ranked.tier, RankTier.ordinary);
      expect(ranked.reason, isNull);
      expect(ranked.rule, isNull);
    });
  });

  group('the project pins its own files', () {
    test('a matched glob pins, and the row can name it', () {
      var ranked = rank(
        'lib/model.g.dart',
        config: const ChangesConfig(attention: ['**/model.g.dart']),
      );
      expect(ranked.tier, RankTier.attention);
      expect(ranked.reason, 'matches **/model.g.dart');
      expect(ranked.rule, '**/model.g.dart');
    });

    test('a rule that matches nothing pins nothing', () {
      var ranked = rank(
        'lib/auth.dart',
        config: const ChangesConfig(attention: ['lib/api/**']),
      );
      expect(ranked.tier, RankTier.ordinary);
      expect(ranked.reason, isNull);
    });
  });

  group('attentionForUntracked', () {
    test('a project rule pins a file nobody has staged yet', () {
      expect(
        attentionForUntracked(
          'db/migrations/002.sql',
          attentionGlobs(const ChangesConfig(attention: ['**/migrations/**'])),
        ),
        'matches **/migrations/**',
      );
    });

    test('with no project rules it pins nothing', () {
      expect(
        attentionForUntracked('openapi.yaml', attentionGlobs(null)),
        isNull,
      );
      expect(
        attentionForUntracked('db/migrations/1.sql', attentionGlobs(null)),
        isNull,
      );
    });

    test('a directory is never pinned, whatever it matches', () {
      // git reports the topmost untracked directory and does not descend.
      // Neither does this — matching into it would be the walk being avoided.
      expect(
        attentionForUntracked(
          'db/migrations/',
          attentionGlobs(const ChangesConfig(attention: ['**'])),
        ),
        isNull,
      );
    });

    test('an ordinary new file is not pinned', () {
      expect(
        attentionForUntracked('scratch.txt', attentionGlobs(null)),
        isNull,
      );
    });
  });

  group('Ranking', () {
    test('every file lands in exactly one tier', () {
      var ranking = rankChanges([
        file('lib/a.dart'),
        file('lib/a.g.dart'),
        file('pubspec.yaml'),
      ], config: const ChangesConfig(attention: ['pubspec.yaml']));
      expect(ranking.files, hasLength(3));
      expect(
        {for (var it in ranking.files) it.file.path},
        hasLength(3),
        reason: 'and each of them exactly once',
      );
      expect(ranking.forPath('pubspec.yaml')?.tier, RankTier.attention);
      expect(ranking.forPath('lib/a.g.dart')?.tier, RankTier.ordinary);
      expect(ranking.forPath('nowhere.dart'), isNull);
    });
  });
}
