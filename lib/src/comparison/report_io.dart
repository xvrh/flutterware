/// The disk-facing half of the comparison report — what a `tool/` script calls.
///
/// Split from `report.dart` because the model itself must stay importable in a
/// browser (the exported comparison page parses it), and this half reads files.
library;

import 'dart:convert';
import 'dart:io';

import 'frame_ref.dart';
import 'report.dart';

/// A written comparison, read back.
///
/// ```dart
/// var report = await ComparisonReport.read('build/comparison/report/web');
/// if (report.index.ok) return;
/// for (var finding in report.index.findings) {
///   print('${finding.state.name} ${finding.id}');
///   if (finding.preview?.shots case var shots?) {
///     if (report.frame(shots.head) case var png?) {
///       await service.upload(png, finding.id);
///     }
///   }
/// }
/// ```
class ComparisonReport {
  const ComparisonReport({required this.directory, required this.index});

  /// Where `index.json` was found, and what a frame reference resolves
  /// against.
  final String directory;

  final ComparisonIndex index;

  /// Reads the `index.json` in [directory].
  ///
  /// Point it at an **exported** page — `fw compare --export=<dir>` or the
  /// `web/` inside `--report=<dir>`. The comparison cache under
  /// `~/.flutterware` holds a file of the same name and the same verdict, and
  /// this reads it too; what it cannot do there is open a frame, and [frame]
  /// says so rather than handing back a path that does not exist.
  ///
  /// Throws [FormatException] when the directory holds no report, or holds one
  /// this version cannot read. Both name what was found and what was expected,
  /// since the reader is usually looking at build output from elsewhere.
  static Future<ComparisonReport> read(String directory) async {
    var file = File('$directory${Platform.pathSeparator}$comparisonReportFile');
    if (!file.existsSync()) {
      throw FormatException(
        'No $comparisonReportFile in "$directory". '
        'Run `fw compare --report=<dir>` first, and read its `web/`.',
      );
    }
    return ComparisonReport(
      directory: directory,
      index: ComparisonIndex.fromJson(switch (jsonDecode(
        await file.readAsString(),
      )) {
        Map json => json.cast<String, Object?>(),
        var other => throw FormatException(
          '${file.path} is ${other.runtimeType}, not an object.',
        ),
      }),
    );
  }

  /// Turns a frame reference — a preview row's `shots.base`/`shots.head`, or
  /// a scenario step's [FrameRef.path] — into a file beside [directory].
  ///
  /// **Null when this report does not carry that frame.** An export writes
  /// what the shot cache still held: a frame evicted before it ran keeps its
  /// original reference rather than gaining a PNG, which the page renders as
  /// nothing rendered and this reports as nothing to open. Composing a path
  /// for it anyway would hand back a `File` that is not there — the one
  /// failure a typed reader exists to prevent, because it is indistinguishable
  /// from a file the caller simply has not written yet.
  ///
  /// Throws [StateError] on a report whose frames are
  /// [ComparisonFrames.local], which is a different mistake: not one absent
  /// frame but the wrong directory. There is nothing openable there at all — a
  /// preview's reference is a `ShotCache` key rather than a path, and a
  /// scenario step's is a headerless raw frame no image library will read.
  /// Both are what an export exists to turn into PNGs.
  File? frame(String reference) {
    if (index.frames == ComparisonFrames.local) {
      throw StateError(
        'This comparison names frames on the machine that ran it, so '
        '"$reference" cannot be opened from here. Re-run with '
        '`fw compare --report=<dir>` and read the `web/` it writes, which '
        'carries the frames as PNGs.',
      );
    }
    var native = reference.replaceAll('/', Platform.pathSeparator);
    // An absolute reference inside an exported page is one the export could
    // not rewrite. It points into whichever machine produced it — where it may
    // even still exist, and be the raw frame rather than the PNG this claims
    // to hand back — so it is not this page's to open either.
    if (File(native).isAbsolute) return null;
    var file = File('$directory${Platform.pathSeparator}$native');
    return file.existsSync() ? file : null;
  }
}
