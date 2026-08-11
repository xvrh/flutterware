import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../ui/theme.dart';
import 'patch_index.dart';

/// **Where the branch's weight is, before you read a line.**
///
/// One column per changed file, additions rising from a middle baseline and
/// deletions falling below it. It is a diverging bar chart — the shape of a
/// population pyramid or a net-flows chart — chosen because add/delete is
/// naturally a *signed* quantity and the usual single ratio bar throws the
/// magnitude away. One glance separates "this branch rewrites one module" from
/// "this branch touches forty files by a line each".
///
/// **Filtering dims rather than removes.** A column that vanished would take the
/// whole-branch context with it, and the context is the entire reason the strip
/// is here rather than a number in the header.
class ChurnMap extends StatelessWidget {
  const ChurnMap({
    required this.files,
    this.visible,
    this.current,
    this.onTap,
    this.height = 56,
    super.key,
  });

  /// Every changed file, in the order the columns are drawn.
  final List<FileChange> files;

  /// Paths that survived the filter, or null when nothing is filtering. Those
  /// outside it are drawn muted, never dropped.
  final Set<String>? visible;

  /// The path the list is parked on, marked so the two views agree about where
  /// you are.
  final String? current;

  final void Function(FileChange file)? onTap;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (files.isEmpty) return const SizedBox.shrink();
    var colors = context.colors;

    // **Square-rooted, not linear.** One 2,000-line generated file against forty
    // 30-line edits flattens every other column to a hair, and the strip stops
    // saying anything about the forty. The root keeps the big one biggest while
    // leaving the rest legible — the question is "where is the weight", not
    // "how many lines exactly", which the row already answers.
    var peak = files.fold<int>(
      1,
      (top, f) => math.max(top, math.max(f.added, f.removed)),
    );
    double scale(int value) =>
        value <= 0 ? 0 : math.max(0.06, math.sqrt(value) / math.sqrt(peak));

    return SizedBox(
      height: height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Below this a column is unclickable and unreadable; past it the strip
          // scrolls rather than shrinking every file into a hairline.
          const minColumn = 6.0;
          const gap = 2.0;
          var width = math.max(
            minColumn,
            (constraints.maxWidth - gap * files.length) / files.length,
          );

          var columns = [
            for (var file in files)
              Padding(
                padding: const EdgeInsets.only(right: gap),
                child: _Column(
                  file: file,
                  width: width,
                  addFraction: scale(file.added),
                  removeFraction: scale(file.removed),
                  muted: visible != null && !visible!.contains(file.path),
                  isCurrent: file.path == current,
                  onTap: onTap == null ? null : () => onTap!(file),
                ),
              ),
          ];

          var fits =
              width * (files.length) + gap * files.length <=
              constraints.maxWidth + 1;
          var strip = Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var column in columns)
                if (fits) Expanded(child: column) else column,
            ],
          );

          return Stack(
            children: [
              // The baseline, drawn under the columns so a file with no
              // deletions still reads as sitting *on* something.
              Positioned(
                left: 0,
                right: 0,
                top: height / 2,
                child: Container(height: 1, color: colors.line),
              ),
              if (fits)
                strip
              else
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: strip,
                ),
            ],
          );
        },
      ),
    );
  }
}

class _Column extends StatelessWidget {
  const _Column({
    required this.file,
    required this.width,
    required this.addFraction,
    required this.removeFraction,
    required this.muted,
    required this.isCurrent,
    this.onTap,
  });

  final FileChange file;
  final double width;
  final double addFraction;
  final double removeFraction;
  final bool muted;
  final bool isCurrent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    var opacity = muted ? 0.25 : 1.0;

    return Tooltip(
      message: '${file.path}\n+${file.added} -${file.removed}',
      waitDuration: const Duration(milliseconds: 400),
      child: MouseRegion(
        cursor: onTap == null ? MouseCursor.defer : SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          child: SizedBox(
            width: width,
            child: Column(
              children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: FractionallySizedBox(
                      heightFactor: addFraction,
                      child: Container(
                        color: colors.grn.withValues(alpha: opacity),
                      ),
                    ),
                  ),
                ),
                // The current file gets the baseline itself, so the mark sits
                // where the eye already is rather than adding a third row of
                // pixels to scan.
                Container(
                  height: 1,
                  color: isCurrent ? colors.accent : Colors.transparent,
                ),
                Expanded(
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: FractionallySizedBox(
                      heightFactor: removeFraction,
                      child: Container(
                        color: colors.red.withValues(alpha: opacity),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
