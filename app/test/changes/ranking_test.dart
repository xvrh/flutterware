import 'dart:convert';
import 'dart:typed_data';

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

  RankedFile rank(
    String path, {
    ChangesConfig? config,
    Map<String, Set<String>> attributes = const {},
  }) => rankChanges(
    [file(path)],
    config: config,
    attributes: attributes,
  ).files.single;

  group('built-in defaults, with no config at all', () {
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

    test('demotes generated code and lockfiles', () {
      expect(rank('lib/model.g.dart').tier, RankTier.noise);
      expect(rank('lib/model.g.dart').reason, 'built-in: *.g.dart');
      expect(rank('app/pubspec.lock').tier, RankTier.noise);
      // The hand-rolled suffix, which this repository uses itself.
      expect(rank('lib/src/shapes.generated.dart').tier, RankTier.noise);
      expect(rank('build/app/outputs/x.apk').tier, RankTier.noise);
      expect(rank('test/__snapshots__/a.json').tier, RankTier.noise);
    });

    test('leaves ordinary code alone, with nothing to explain', () {
      var ranked = rank('lib/src/auth.dart');
      expect(ranked.tier, RankTier.ordinary);
      expect(ranked.reason, isNull);
      expect(ranked.rule, isNull);
    });

    test('the lock is still demoted, and the manifest is left alone', () {
      // **The asymmetry that survives.** Noise defaults are facts about the
      // toolchain flutterware is *for* — `pubspec.lock` is pub's output — and
      // getting one wrong is cheap: the file is still listed, one lens away.
      // Getting attention wrong is loud, so nothing pins `pubspec.yaml` unless
      // the project says to.
      expect(rank('pubspec.lock').tier, RankTier.noise);
      expect(rank('pubspec.yaml').tier, RankTier.ordinary);
    });
  });

  group('precedence — project, then .gitattributes, then built-in', () {
    test('the project pins something the defaults call noise', () {
      var ranked = rank(
        'lib/model.g.dart',
        config: const ChangesConfig(attention: ['**/model.g.dart']),
      );
      expect(ranked.tier, RankTier.attention);
      expect(ranked.reason, 'matches **/model.g.dart');
    });

    test('the project demotes something the defaults pin', () {
      // This is the documented way to *subtract* from the defaults: name the
      // path in the other section.
      var ranked = rank(
        'pubspec.yaml',
        config: const ChangesConfig(noise: ['pubspec.yaml']),
      );
      expect(ranked.tier, RankTier.noise);
      expect(ranked.reason, 'matches pubspec.yaml');
    });

    test('the project beats .gitattributes', () {
      var ranked = rank(
        'vendor/thing.dart',
        config: const ChangesConfig(attention: ['vendor/**']),
        attributes: {
          'vendor/thing.dart': {'linguist-vendored'},
        },
      );
      expect(ranked.tier, RankTier.attention);
      expect(ranked.source, RankSource.project);
    });

    test('.gitattributes beats the built-in defaults', () {
      // `lib/api.dart` is ordinary by default; the repository says otherwise.
      var ranked = rank(
        'lib/api.dart',
        attributes: {
          'lib/api.dart': {'linguist-generated'},
        },
      );
      expect(ranked.tier, RankTier.noise);
      expect(ranked.reason, 'generated in .gitattributes');
      expect(ranked.source, RankSource.gitAttributes);
    });

    test('which attribute is named does not depend on git printing order', () {
      var both = {
        'x.dart': {'diff', 'linguist-generated'},
      };
      var reversed = {
        'x.dart': {'linguist-generated', 'diff'},
      };
      expect(
        rank('x.dart', attributes: both).reason,
        rank('x.dart', attributes: reversed).reason,
      );
    });
  });

  group('attributesFrom', () {
    List<String> records(String joined) => joined.split('|');

    test('reads the triplets check-attr -z prints', () {
      var parsed = attributesFrom(records('a.g.dart|linguist-generated|true'));
      expect(parsed, {
        'a.g.dart': {'linguist-generated'},
      });
    });

    test('unset and unspecified are not set', () {
      var parsed = attributesFrom(
        records(
          'a.dart|linguist-generated|unset|'
          'b.dart|linguist-generated|unspecified|'
          'c.dart|linguist-generated|false',
        ),
      );
      expect(parsed, isEmpty);
    });

    test('diff inverts: -diff is the interesting state', () {
      // `-diff` means "do not read this as text", so `unset` is what counts —
      // the opposite of every other attribute here.
      expect(attributesFrom(records('a.bin|diff|unset')), {
        'a.bin': {'diff'},
      });
      expect(attributesFrom(records('a.dart|diff|set')), isEmpty);
    });

    test('a truncated final record is dropped rather than misread', () {
      expect(attributesFrom(records('a.dart|linguist-generated')), isEmpty);
    });

    test('a repository with no .gitattributes says nothing at all', () {
      expect(attributesFrom(const []), isEmpty);
    });
  });

  group('derived rules — what no glob can express', () {
    PatchIndex index(List<String> lines) =>
        indexPatch(Uint8List.fromList(utf8.encode(lines.join('\n'))));

    test('a reformat is noise, and says which kind', () {
      var patch = index([
        'diff --git a/lib/a.dart b/lib/a.dart',
        '--- a/lib/a.dart',
        '+++ b/lib/a.dart',
        '@@ -1,2 +1,2 @@',
        '-void main( ) { print(1); }',
        '-var x=1;',
        '+void main() {',
        '+  print(1);}var x = 1;',
        '',
      ]);
      var ranked = rankChanges(patch.files, patch: patch).files.single;
      expect(ranked.tier, RankTier.noise);
      expect(ranked.reason, 'only whitespace changed');
    });

    test('an import shuffle is noise', () {
      var patch = index([
        'diff --git a/lib/a.dart b/lib/a.dart',
        '--- a/lib/a.dart',
        '+++ b/lib/a.dart',
        '@@ -1,2 +1,2 @@',
        "-import 'b.dart';",
        "-import 'a.dart';",
        "+import 'a.dart';",
        "+import 'b.dart';",
        '',
      ]);
      var ranked = rankChanges(patch.files, patch: patch).files.single;
      expect(ranked.tier, RankTier.noise);
      expect(ranked.reason, 'only imports changed');
    });

    test('real code beside a moved import is not noise', () {
      var patch = index([
        'diff --git a/lib/a.dart b/lib/a.dart',
        '--- a/lib/a.dart',
        '+++ b/lib/a.dart',
        '@@ -1,2 +1,2 @@',
        "-import 'b.dart';",
        "+import 'a.dart';",
        '+var answer = 42;',
        '',
      ]);
      expect(
        rankChanges(patch.files, patch: patch).files.single.tier,
        RankTier.ordinary,
      );
    });

    test('the derived rules never demote a pinned file', () {
      // A migration that was only reindented is still a migration — but only
      // the project can say that it is one.
      var patch = index([
        'diff --git a/db/migrations/1.sql b/db/migrations/1.sql',
        '--- a/db/migrations/1.sql',
        '+++ b/db/migrations/1.sql',
        '@@ -1,1 +1,1 @@',
        '-select 1;',
        '+  select 1;',
        '',
      ]);
      var ranked = rankChanges(
        patch.files,
        patch: patch,
        config: const ChangesConfig(attention: ['**/migrations/**']),
      ).files.single;
      expect(ranked.tier, RankTier.attention);
    });

    test('no patch means the derived rules stay quiet', () {
      // The refused-patch path: globs and attributes still rank, and nothing
      // is claimed about content nobody read.
      expect(rank('lib/a.dart').tier, RankTier.ordinary);
    });
  });

  group('attentionForUntracked', () {
    test('a project rule pins a file nobody has staged yet', () {
      expect(
        attentionForUntracked(
          'db/migrations/002.sql',
          config: const ChangesConfig(attention: ['**/migrations/**']),
        ),
        'matches **/migrations/**',
      );
    });

    test('with no project rules it pins nothing', () {
      expect(attentionForUntracked('openapi.yaml'), isNull);
      expect(attentionForUntracked('db/migrations/1.sql'), isNull);
    });

    test('a directory is never pinned, whatever it matches', () {
      // git reports the topmost untracked directory and does not descend.
      // Neither does this — matching into it would be the walk being avoided.
      expect(
        attentionForUntracked(
          'db/migrations/',
          config: const ChangesConfig(attention: ['**']),
        ),
        isNull,
      );
    });

    test('an ordinary new file is not pinned', () {
      expect(attentionForUntracked('scratch.txt'), isNull);
    });

    test('noise rules do not apply — nothing here can be demoted', () {
      // An untracked file is already in the quietest section there is.
      expect(
        attentionForUntracked(
          'lib/a.g.dart',
          config: const ChangesConfig(noise: ['**/*.g.dart']),
        ),
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
      ]);
      expect(ranking.files, hasLength(3));
      expect(
        ranking.attention.length +
            ranking.ordinary.length +
            ranking.noise.length,
        3,
      );
      expect(ranking.forPath('lib/a.g.dart')?.tier, RankTier.noise);
      expect(ranking.forPath('nowhere.dart'), isNull);
    });
  });
}
