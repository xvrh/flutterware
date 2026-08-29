import 'dart:typed_data';

import 'package:flutterware/comparison_report.dart';
import 'package:flutterware_app/src/comparison/artifact.dart';
import 'package:flutterware_app/src/comparison/runner.dart';
import 'package:test/test.dart';

/// The artifact, read back the way a consumer's script reads it.
///
/// A round trip rather than fixtures, because the writer is the one source of
/// the format: a fixture drifts silently when `toJson` gains a field, and a
/// round trip fails the moment the two halves disagree.
///
/// It lives in `app/` although the reader is published, because it is the
/// *pair* that is under test: `ComparisonArtifact` writes the file and
/// `package:flutterware/comparison_report.dart` reads it, and the drift worth
/// catching is between them. Everything the reader can be asked on its own is
/// tested beside it, in the root package.
void main() {
  ComparisonArtifact artifact() => ComparisonArtifact(
    previews: ComparisonResult(
      baseSha: 'abc123def456',
      headRoot: '/work/tree',
      elapsed: const Duration(milliseconds: 178),
      rendered: 2,
      items: [
        ComparedItem.of(
          id: 'demo/card.dart#card',
          pixels: PixelDiff.of(
            base: _frame(8, 8, 40),
            baseWidth: 8,
            baseHeight: 8,
            head: _frame(8, 8, 200),
            headWidth: 8,
            headHeight: 8,
          ),
          tree: const TreeDiff([
            TreeDelta(
              kind: TreeDeltaKind.changed,
              path: 'Card › Padding',
              property: 'padding',
              base: '12',
              head: '20',
            ),
          ]),
          baseTexts: ['Buy'],
          headTexts: ['Buy now'],
          shots: (base: 'k-base', head: 'k-head'),
        ),
        const ComparedItem(id: 'demo/quiet.dart#ok', state: ComparedState.same),
      ],
    ),
    scenarios: ScenarioResults.of(
      ran: 1,
      skipped: 0,
      elapsed: const Duration(seconds: 4),
      items: [
        ScenarioComparison(
          scenario: 'test/shop.dart#Checkout',
          state: ComparedState.changed,
          items: const [
            ComparedItem(
              id: 'guest › Pay',
              state: ComparedState.changed,
              label: 'tap "Pay"',
            ),
          ],
          branches: const [
            BranchDelta(
              label: 'expired card',
              added: true,
              steps: 3,
              path: ['guest'],
            ),
          ],
          frames: const {
            'guest › Pay': (
              base: FrameRef(path: '/tmp/base.raw', width: 4, height: 4),
              head: FrameRef(path: '/tmp/head.raw', width: 4, height: 4),
            ),
          },
        ),
      ],
    ),
  );

  test('the artifact reads back what it wrote', () {
    var index = ComparisonIndex.fromJson(artifact().toJson());

    expect(index.base, 'abc123def456');
    // No `against` in the raw artifact — the export adds it — so the header
    // falls back to the abbreviated sha rather than an empty string.
    expect(index.against, 'abc123de');

    var card = index.previewItems.first;
    expect(card.id, 'demo/card.dart#card');
    expect(card.state, ComparedState.changed);
    expect(card.shots, (base: 'k-base', head: 'k-head'));
    expect(card.texts!.added, ['Buy now']);
    expect(card.texts!.removed, ['Buy']);
    expect(card.tree!.diff.deltas.single.property, 'padding');
    expect(index.previewItems[1].state, ComparedState.same);

    var checkout = index.scenarios.single;
    expect(checkout.scenario, 'test/shop.dart#Checkout');
    expect(checkout.state, ComparedState.changed);
    expect(checkout.items.single.label, 'tap "Pay"');
    expect(checkout.branches.single.label, 'expired card');
    expect(checkout.branches.single.added, isTrue);
    expect(checkout.branches.single.path, ['guest']);
    expect(checkout.frames['guest › Pay']!.head!.path, '/tmp/head.raw');
    expect(checkout.frames['guest › Pay']!.head!.width, 4);
  });

  test('the file says which version it is, and the reader gates on it', () {
    var written = artifact().toJson();

    expect(written['version'], comparisonReportVersion);
    expect(ComparisonIndex.fromJson(written).version, comparisonReportVersion);

    // A reader handed a file from a newer flutterware refuses rather than
    // decoding half of it by guesswork.
    expect(
      () => ComparisonIndex.fromJson({
        ...written,
        'version': comparisonReportVersion + 1,
      }),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          allOf(
            contains('${comparisonReportVersion + 1}'),
            contains('Upgrade the flutterware dependency'),
          ),
        ),
      ),
    );
  });

  // The cache dialect names `ShotCache` keys and absolute paths to headerless
  // raw frames. It says so, so a reader never hands back a path that is not
  // there — see [ComparisonFrames].
  test('an artifact declares its frames local', () {
    expect(artifact().toJson()['frames'], 'local');
    expect(
      ComparisonIndex.fromJson(artifact().toJson()).frames,
      ComparisonFrames.local,
    );
  });

  test('a file written before the key existed reads as local', () {
    var older = {...artifact().toJson()}..remove('frames');

    expect(ComparisonIndex.fromJson(older).frames, ComparisonFrames.local);
  });

  test('both halves carry what a gate reads', () {
    var index = ComparisonIndex.fromJson(artifact().toJson());

    expect(index.ms, 4178);
    expect(index.counts, {ComparedState.changed: 2, ComparedState.same: 1});
    expect(index.previewsHalf.worked, 2);
    expect(index.previewsHalf.ms, 178);
    expect(index.scenariosHalf!.worked, 1);
    expect(index.scenariosHalf!.counts, {ComparedState.changed: 1});
  });

  // The previews half has never written a `skipped` key — its counts already
  // carry the number — so a reader taking the key at face value reports zero
  // skips on the comparison that skipped everything, which is the one number
  // the whole skip rule exists to move.
  test('the previews half is not read as having skipped nothing', () {
    var quiet = ComparisonArtifact(
      previews: ComparisonResult(
        baseSha: 'abc',
        headRoot: '/w',
        elapsed: Duration.zero,
        rendered: 0,
        items: const [
          ComparedItem(id: 'a#b', state: ComparedState.skipped),
          ComparedItem(id: 'c#d', state: ComparedState.skipped),
          ComparedItem(id: 'e#f', state: ComparedState.same),
        ],
      ),
    );
    var index = ComparisonIndex.fromJson(quiet.toJson());

    expect(quiet.toJson()['previews'], isNot(contains('skipped')));
    expect(index.previewsHalf.skipped, 2);
    expect(index.previewsHalf.worked, 0);
  });

  test('why the skip rule could not answer survives the write', () {
    var withReasons = ComparisonArtifact(
      previews: ComparisonResult(
        baseSha: 'abc',
        headRoot: '/w',
        elapsed: Duration.zero,
        rendered: 2,
        items: const [],
        because: {'pubspec.lock differs': 90},
      ),
      scenarios: ScenarioResults.of(
        ran: 1,
        skipped: 0,
        elapsed: Duration.zero,
        items: const [],
        because: {'lib/theme.dart differs': 3},
      ),
    );
    var index = ComparisonIndex.fromJson(withReasons.toJson());

    expect(index.previewsHalf.because, {'pubspec.lock differs': 90});
    expect(index.scenariosHalf!.because, {'lib/theme.dart differs': 3});
  });

  test('the findings are the gate, worst first across both halves', () {
    var index = ComparisonIndex.fromJson(artifact().toJson());

    expect(index.ok, isFalse);
    expect(index.findings.map((f) => f.id), [
      'demo/card.dart#card',
      'test/shop.dart#Checkout',
    ]);
    expect(index.findings.first.half, ComparedHalfKind.previews);
    // The whole row travels, so acting on a finding needs no second lookup.
    expect(index.findings.first.preview!.pixels!.diff.changed, isTrue);
    expect(index.findings.last.scenario!.branches.single.label, 'expired card');
  });

  test('a comparison with nothing to say is ok', () {
    var quiet = ComparisonArtifact(
      previews: ComparisonResult(
        baseSha: 'abc',
        headRoot: '/w',
        elapsed: Duration.zero,
        rendered: 0,
        items: const [
          ComparedItem(id: 'a#b', state: ComparedState.skipped),
          ComparedItem(id: 'c#d', state: ComparedState.same),
        ],
      ),
    );

    expect(ComparisonIndex.fromJson(quiet.toJson()).ok, isTrue);
  });

  // What `fw compare --json` prints is the artifact plus where it wrote
  // things. Parsing it is the cheapest CI hook there is, and the `export`
  // key is the bridge from a verdict on stdout to frames on disk.
  test('the stdout object parses, and names the exported page', () {
    var index = ComparisonIndex.fromJson({
      ...artifact().toJson(),
      'export': {'output': 'build/comparison/report/web', 'frames': 138},
      'report': {'comment': 'build/comparison/report/comment.md'},
    });

    expect(index.export, 'build/comparison/report/web');
    expect(index.report, 'build/comparison/report/comment.md');
    expect(index.findings, hasLength(2));
  });

  test('the pixel channel survives to the same five decimal places', () {
    var index = ComparisonIndex.fromJson(artifact().toJson());
    var diff = index.previewItems.first.pixels!.diff;

    expect(diff.width, 8);
    expect(diff.height, 8);
    expect(diff.changed, isTrue);
    // Every pixel differs between a 40-fill and a 200-fill.
    expect(diff.fraction, closeTo(1.0, 0.00001));
    expect(diff.clusters, isNotEmpty);
    expect(diff.clusters.first.width, 8);
  });

  test('findings count both halves and skip the quiet states', () {
    var index = ComparisonIndex.fromJson(artifact().toJson());

    expect(index.findingCounts, {ComparedState.changed: 2});
  });

  test('an artifact with no scenario half reads as none', () {
    var solo = ComparisonArtifact(
      previews: ComparisonResult(
        baseSha: 'abc',
        headRoot: '/w',
        elapsed: Duration.zero,
        rendered: 0,
        items: const [],
      ),
    );
    var index = ComparisonIndex.fromJson(solo.toJson());

    expect(index.scenarios, isEmpty);
    expect(index.scenariosNote, isNull);
  });

  test('a scenario half that refused keeps its note', () {
    var refused = ComparisonArtifact(
      previews: ComparisonResult(
        baseSha: 'abc',
        headRoot: '/w',
        elapsed: Duration.zero,
        rendered: 0,
        items: const [],
      ),
      scenarios: ScenarioResults.of(
        ran: 0,
        skipped: 0,
        elapsed: Duration.zero,
        items: const [],
        note: 'the base harness would not build',
      ),
    );
    var index = ComparisonIndex.fromJson(refused.toJson());

    expect(index.scenariosNote, 'the base harness would not build');
  });
}

Uint8List _frame(int width, int height, int value) =>
    Uint8List(width * height * 4)..fillRange(0, width * height * 4, value);
