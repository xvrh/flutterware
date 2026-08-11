import 'dart:typed_data';

import 'package:flutterware_app/src/comparison/artifact.dart';
import 'package:flutterware_app/src/comparison/channels.dart';
import 'package:flutterware_app/src/comparison/frame_ref.dart';
import 'package:flutterware_app/src/comparison/index_reader.dart';
import 'package:flutterware_app/src/comparison/pixel_diff.dart';
import 'package:flutterware_app/src/comparison/runner.dart';
import 'package:flutterware_app/src/comparison/scenario_alignment.dart';
import 'package:flutterware_app/src/comparison/scenario_comparison.dart';
import 'package:flutterware_app/src/comparison/tree_diff.dart';
import 'package:test/test.dart';

/// The artifact, read back the way the exported page reads it.
///
/// A round trip rather than fixtures, because the writer is the one source of
/// the format: a fixture drifts silently when `toJson` gains a field, and a
/// round trip fails the moment the two halves disagree.
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
