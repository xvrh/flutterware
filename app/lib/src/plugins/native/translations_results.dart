import 'package:flutterware/plugins.dart';
import 'package:json_annotation/json_annotation.dart';

part 'translations_results.g.dart';

/// `export` — the run, written out as something a translator or a translation
/// service can read.
///
/// Reports the run's verdict, not the export's: the scenarios really ran to
/// produce this, and a suite that came back red is worth an exit code. The
/// export exists either way, because a key seen on a screen that failed is
/// still a key seen.
///
/// The finding counts are **findings, not failures**. Falling back to the
/// source language and clipped text are the two things this exists to surface;
/// making them fail the command would only teach people to pass a flag.
@JsonSerializable(
  explicitToJson: true,
  includeIfNull: false,
  createFactory: false,
)
class TranslationExportResult implements PluginResult, ReportsFailure {
  TranslationExportResult({
    required this.output,
    required this.keysJson,
    required this.indexHtml,
    required this.catalogs,
    required this.locales,
    required this.keys,
    required this.keysSeen,
    required this.occurrences,
    required this.shots,
    this.missingShots = 0,
    this.fallingBack = 0,
    this.disagrees = 0,
    this.notReached = 0,
    this.absentFromCatalog = 0,
    this.overflowing = 0,
    this.unkeyed = 0,
    this.scenariosFailed = 0,
    this.maxLengths = 0,
    this.maxLengthLimits = 0,
    this.maxLengthDevices,
    this.expansionBreaks = 0,
    required this.durationMs,
    required this.open,
  });

  /// The directory, worktree-relative where it sits inside one.
  final String output;

  /// The index a script reads. `package:flutterware/translations.dart` has the
  /// types for it — `TranslationExport.read(output)`.
  final String keysJson;

  /// The page a person reads.
  final String indexHtml;

  final int catalogs;

  /// How many languages the run covered. **One means the falling-back list is
  /// empty because nothing could have fallen back**, not because nothing does.
  final int locales;

  /// Every key the catalogs define.
  final int keys;

  /// How many of them this run put on a screen. The gap is [notReached].
  final int keysSeen;

  /// Every place a key was seen — the sum over all keys, and roughly what a
  /// service push will cost in calls.
  final int occurrences;

  /// Frames written, deduplicated: several keys on one screen cost one file.
  final int shots;

  /// Frames a step named that were not on disk. Nonzero means the run's
  /// artifacts were cleaned up underneath the export.
  final int missingShots;

  /// Places the app showed the source language to somebody who asked for
  /// another one.
  final int fallingBack;

  /// Places the files and the run disagree — usually a stale build.
  final int disagrees;

  /// Declared keys this run never asked for. **Coverage, not dead code.**
  final int notReached;

  /// Keys the app read that no declared catalog defines.
  final int absentFromCatalog;

  /// Sightings where the words did not fit.
  final int overflowing;

  /// Distinct strings on screen that belonged to no catalog.
  final int unkeyed;

  /// Scenarios that came back red. Their screens are in the export.
  final int scenariosFailed;

  /// Keys whose max length was measured. Zero with the flag off means
  /// nothing was measured, not that everything fits.
  final int maxLengths;

  /// Of those, keys with a *real* limit — a longer string was rendered and
  /// clipped. The rest are open bounds ("at least N characters").
  final int maxLengthLimits;

  /// The devices the measurement ran on — what every `maxLength` claim is
  /// true for. Absent when no probe ran.
  final String? maxLengthDevices;

  /// Screens that broke under expansion — a layout overflow, or a scenario
  /// red at some growth level. Detail is in `findings.expansionBreaks`.
  final int expansionBreaks;

  final int durationMs;

  /// How to look at it. Unlike the scenario web export this is a plain file
  /// open — the page inlines its own data precisely so that works.
  final String open;

  @override
  bool get ok => scenariosFailed == 0;

  @override
  Map<String, Object?> toJson() => _$TranslationExportResultToJson(this);
}
