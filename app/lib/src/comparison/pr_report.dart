import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import 'artifact.dart';
import 'channels.dart';
import 'frame_ref.dart';
import 'pixel_diff.dart';
import 'scenario_comparison.dart';
import 'shot_cache.dart';

/// What a pull-request comment needs, as files.
///
/// **fw emits, the workflow hosts and posts.** A comment on GitHub can only
/// show images by URL, and where those URLs live — an orphan branch, Pages, a
/// bucket — is the repository's business, not this tool's. So the comment is
/// written with `__MOSAIC_URL__` and `__VIEWER_URL__` placeholders, and the
/// fifteen lines of workflow that upload the files substitute them.
class PrReport {
  const PrReport({required this.commentPath, this.mosaicPath});

  final String commentPath;

  /// Absent when nothing changed — a clean comment carries no picture.
  final String? mosaicPath;
}

/// One row of the mosaic: what to call it, and the two frames.
class _MosaicRow {
  const _MosaicRow({
    required this.title,
    required this.base,
    required this.head,
    this.clusters = const [],
  });

  final String title;
  final img.Image? base;
  final img.Image? head;

  /// Burned onto the head frame, in its pixel space.
  final List<DiffRect> clusters;
}

/// Writes `comment.md` and, when anything changed, `mosaic.png` into
/// [directory].
///
/// The mosaic is one row per finding, base beside head, capped at
/// [mosaicRowCap] — it is the teaser, and the exported page is the artifact.
PrReport writePrReport({
  required ComparisonArtifact artifact,
  required ShotCache cache,
  required String against,
  required String directory,
}) {
  Directory(directory).createSync(recursive: true);

  var findings = _findings(artifact);
  var rows = [
    for (var finding in findings.take(mosaicRowCap))
      ?_row(finding, cache: cache),
  ];

  String? mosaicPath;
  if (rows.isNotEmpty) {
    mosaicPath = p.join(directory, 'mosaic.png');
    File(mosaicPath).writeAsBytesSync(_mosaic(rows));
  }

  var commentPath = p.join(directory, 'comment.md');
  File(commentPath).writeAsStringSync(
    _comment(
      artifact,
      against: against,
      findings: findings,
      hasMosaic: mosaicPath != null,
    ),
  );
  return PrReport(commentPath: commentPath, mosaicPath: mosaicPath);
}

/// The mosaic stops here and the comment says "and N more" — a comment is a
/// teaser, and forty rows of phone frames is a page pretending to be one.
const mosaicRowCap = 20;

/// Both frames scale to this height, so a phone step and a wide desktop
/// preview read as rows of one table rather than a ransom note.
const _rowHeight = 320;
const _pad = 12;
const _titleHeight = 28;

/// One finding, whichever half it came from.
class _Finding {
  const _Finding({
    required this.id,
    required this.state,
    this.delta,
    this.item,
    this.frames,
  });

  final String id;
  final ComparedState state;

  /// The third column: `0.38% · 2 regions`, or the step that moved.
  final String? delta;

  /// The row whose shots and clusters draw, when there is one.
  final ComparedItem? item;

  /// A scenario step's frames, which are files rather than cache keys.
  final ({FrameRef? base, FrameRef? head})? frames;
}

List<_Finding> _findings(ComparisonArtifact artifact) {
  var findings = <_Finding>[];
  for (var item in artifact.previews.items) {
    if (!_isFinding(item.state)) continue;
    findings.add(
      _Finding(id: item.id, state: item.state, delta: _delta(item), item: item),
    );
  }
  for (var scenario
      in artifact.scenarios?.items ?? const <ScenarioComparison>[]) {
    if (!_isFinding(scenario.state)) continue;
    // The scenario's face in the mosaic is its worst step that has pictures —
    // one row per flow, because one decision in the source should not fill
    // the comment with four near-identical frames.
    ComparedItem? worst;
    for (var step in scenario.items) {
      if (!_isFinding(step.state)) continue;
      if (scenario.frames[step.id] == null) continue;
      if (worst == null || step.state.index < worst.state.index) worst = step;
    }
    findings.add(
      _Finding(
        id: scenario.scenario,
        state: scenario.state,
        delta: worst == null
            ? scenario.branches.isEmpty
                  ? null
                  : '${scenario.branches.length} branch'
                        '${scenario.branches.length == 1 ? '' : 'es'}'
            : 'step `${worst.id}`',
        item: worst,
        frames: worst == null ? null : scenario.frames[worst.id],
      ),
    );
  }
  findings.sort(
    (a, b) => a.state.index == b.state.index
        ? a.id.compareTo(b.id)
        : a.state.index.compareTo(b.state.index),
  );
  return findings;
}

bool _isFinding(ComparedState state) =>
    state != ComparedState.same && state != ComparedState.skipped;

String? _delta(ComparedItem item) {
  var pixels = item.pixels?.diff;
  if (pixels == null || !pixels.changed) return item.note;
  return '${(pixels.fraction * 100).toStringAsFixed(2)}% · '
      '${pixels.clusters.length} region${pixels.clusters.length == 1 ? '' : 's'}';
}

_MosaicRow? _row(_Finding finding, {required ShotCache cache}) {
  img.Image? decode(String? key, FrameRef? ref) {
    if (key != null) {
      var bytes = cache.read(key);
      var record = cache.meta(key);
      if (bytes == null || record == null) return null;
      return _fromRgba(bytes, record.width, record.height);
    }
    if (ref != null && ref.isDrawable) {
      var file = File(ref.path);
      if (!file.existsSync()) return null;
      return _fromRgba(file.readAsBytesSync(), ref.width, ref.height);
    }
    return null;
  }

  var shots = finding.item?.shots;
  var base = decode(shots?.base, finding.frames?.base);
  var head = decode(shots?.head, finding.frames?.head);
  if (base == null && head == null) return null;
  return _MosaicRow(
    title: '${finding.state.name}  ${finding.id}',
    base: base,
    head: head,
    clusters: finding.item?.pixels?.diff.clusters ?? const [],
  );
}

img.Image _fromRgba(Uint8List rgba, int width, int height) =>
    img.Image.fromBytes(
      width: width,
      height: height,
      bytes: rgba.buffer,
      bytesOffset: rgba.offsetInBytes,
      numChannels: 4,
      order: img.ChannelOrder.rgba,
    );

Uint8List _mosaic(List<_MosaicRow> rows) {
  var scaled = <(_MosaicRow, img.Image?, img.Image?)>[];
  var width = 0;
  for (var row in rows) {
    var base = row.base == null
        ? null
        : img.copyResize(row.base!, height: _rowHeight);
    img.Image? head;
    if (row.head != null) {
      // The clusters are burned in before scaling, in the frame's own pixel
      // space — scaled coordinates drift a pixel per region and a box that
      // misses what it points at is worse than none.
      var full = row.head!.clone();
      for (var rect in row.clusters) {
        img.drawRect(
          full,
          x1: rect.x - 1,
          y1: rect.y - 1,
          x2: rect.x + rect.width + 1,
          y2: rect.y + rect.height + 1,
          color: img.ColorRgb8(255, 160, 0),
          thickness: (full.width / 300).clamp(1, 4).toDouble(),
        );
      }
      head = img.copyResize(full, height: _rowHeight);
    }
    scaled.add((row, base, head));
    var rowWidth = (base?.width ?? 0) + (head?.width ?? 0) + _pad * 3;
    if (rowWidth > width) width = rowWidth;
  }

  var height = rows.length * (_rowHeight + _titleHeight + _pad * 2);
  var canvas = img.Image(width: width, height: height, numChannels: 3);
  img.fill(canvas, color: img.ColorRgb8(250, 250, 250));

  var y = 0;
  for (var (row, base, head) in scaled) {
    img.drawString(
      canvas,
      row.title,
      font: img.arial14,
      x: _pad,
      y: y + _pad,
      color: img.ColorRgb8(40, 40, 40),
    );
    var top = y + _titleHeight + _pad;
    var x = _pad;
    for (var frame in [base, head]) {
      if (frame != null) {
        img.compositeImage(canvas, frame, dstX: x, dstY: top);
        x += frame.width + _pad;
      }
    }
    y += _rowHeight + _titleHeight + _pad * 2;
  }
  return img.encodePng(canvas);
}

String _comment(
  ComparisonArtifact artifact, {
  required String against,
  required List<_Finding> findings,
  required bool hasMosaic,
}) {
  var counts = artifact.counts;
  var compared = counts.values.fold(0, (a, b) => a + b);
  var skipped = counts[ComparedState.skipped] ?? 0;
  var summary = [
    for (var entry in counts.entries)
      if (_isFinding(entry.key)) '${entry.value} ${entry.key.name}',
  ].join(' · ');

  var buffer = StringBuffer()..writeln('### Comparison against `$against`\n');
  if (findings.isEmpty) {
    buffer.writeln(
      'Nothing changed — $compared entries compared, $skipped answered by '
      'the skip rule.',
    );
  } else {
    buffer
      ..writeln(
        '**$summary** — $compared entries compared, $skipped answered by '
        'the skip rule.\n',
      )
      ..writeln('| entry | state | Δ |')
      ..writeln('|---|---|---|');
    for (var finding in findings) {
      buffer.writeln(
        '| `${finding.id}` | ${finding.state.name} | ${finding.delta ?? ''} |',
      );
    }
    buffer.writeln();
    if (hasMosaic) {
      buffer.writeln('![comparison]($mosaicUrlPlaceholder)\n');
      if (findings.length > mosaicRowCap) {
        buffer.writeln(
          '*…and ${findings.length - mosaicRowCap} more — the page below has '
          'them all.*\n',
        );
      }
    }
    buffer.writeln('[Open the full comparison]($viewerUrlPlaceholder)\n');
  }
  buffer.writeln(
    '<sub>`fw compare` — both sides computed from git; nothing is '
    'blessed.</sub>',
  );
  return buffer.toString();
}

/// What the workflow substitutes once it has hosted `mosaic.png`.
const mosaicUrlPlaceholder = '__MOSAIC_URL__';

/// What the workflow substitutes once it has hosted the `web/` page.
const viewerUrlPlaceholder = '__VIEWER_URL__';
