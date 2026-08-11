import 'package:flutter/material.dart';

import '../ui/theme.dart';
import 'patch_index.dart';

/// **Where in the file the change sits, and how heavy each hunk is.**
///
/// A minimap compressed to a hundred pixels: the track is the whole file, each
/// mark is a hunk at its own position, and the mark's split says whether it
/// added or removed. *Three hunks clustered at the top* reads differently from
/// *changes scattered through four hundred lines*, and neither is legible from
/// `+140 −22`.
///
/// Everything it draws is already in [PatchIndex] — the scan records each
/// hunk's start and its weight — so this costs no second pass over the patch
/// and nothing is decoded to draw it.
class HunkRuler extends StatelessWidget {
  const HunkRuler({
    required this.file,
    this.width = 110,
    this.height = 12,
    super.key,
  });

  final FileChange file;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    return SizedBox(
      width: width,
      height: height,
      child: CustomPaint(
        painter: _RulerPainter(
          file: file,
          track: colors.line,
          added: colors.grn,
          removed: colors.red,
        ),
      ),
    );
  }
}

class _RulerPainter extends CustomPainter {
  _RulerPainter({
    required this.file,
    required this.track,
    required this.added,
    required this.removed,
  });

  final FileChange file;
  final Color track;
  final Color added;
  final Color removed;

  /// Narrower than this and a one-line hunk disappears; the ruler's job is to
  /// say *there is something here*, and a mark too small to see fails at it.
  static const _minMark = 2.0;

  @override
  void paint(Canvas canvas, Size size) {
    var trackPaint = Paint()..color = track;
    canvas.drawRect(Offset.zero & size, trackPaint);

    var length = _fileLength;
    if (length <= 0) return;

    for (var hunk in file.hunks) {
      var (at, count) = _extentOf(hunk);
      var start = (at / length).clamp(0.0, 1.0) * size.width;
      var span = (count / length).clamp(0.0, 1.0) * size.width;
      var w = span < _minMark ? _minMark : span;
      if (start + w > size.width) start = size.width - w;

      // The split is the hunk's own balance, so a mostly-deleting hunk reads as
      // one at a glance. A pure addition or a pure deletion fills the mark.
      var weight = hunk.added + hunk.removed;
      var addShare = weight == 0 ? 1.0 : hunk.added / weight;

      canvas.drawRect(
        Rect.fromLTWH(start, 0, w, size.height * addShare),
        Paint()..color = added,
      );
      canvas.drawRect(
        Rect.fromLTWH(
          start,
          size.height * addShare,
          w,
          size.height * (1 - addShare),
        ),
        Paint()..color = removed,
      );
    }
  }

  /// Where a hunk sits, **on whichever side of it exists**.
  ///
  /// The post-image is the natural frame — you are reading the file as it is
  /// now — but a *deleted* file has no post-image at all: git writes
  /// `@@ -1,322 +0,0 @@`, so a ruler measured on the new side computed a length
  /// of zero and drew nothing. Five blank tracks on a real branch is how this
  /// was found; a fixture would not have caught it, because a fixture is never
  /// a whole-file deletion by accident.
  static (int, int) _extentOf(HunkSpan hunk) => hunk.newCount > 0
      ? (hunk.newStart, hunk.newCount)
      : (hunk.oldStart, hunk.oldCount);

  /// How long the file is, as far as the patch can tell.
  ///
  /// The last hunk's end is a **lower bound**, not the file's length — a change
  /// at line 10 of a 4,000-line file would otherwise fill the whole track. The
  /// bound is honest about what it is: with only one hunk near the top, the
  /// ruler says "near the top of what the patch touched", which is the most the
  /// patch knows without reading the file.
  double get _fileLength {
    var end = 0;
    for (var hunk in file.hunks) {
      var (at, count) = _extentOf(hunk);
      var hunkEnd = at + count;
      if (hunkEnd > end) end = hunkEnd;
    }
    // A little headroom so a hunk that ends the patch does not paint flush to
    // the right edge and read as "runs off the end".
    return end == 0 ? 0 : end * 1.08;
  }

  @override
  bool shouldRepaint(_RulerPainter old) =>
      old.file != file ||
      old.added != added ||
      old.removed != removed ||
      old.track != track;
}
