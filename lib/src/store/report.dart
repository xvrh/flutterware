/// What a store export wrote, typed — the reader for a listing's manifest.
///
/// Every `fw run store export` records what it produced beside the tree it
/// produced: every set, with its store, its display class, both locale tags,
/// the directory it landed in and the images in it. This library reads that
/// back, so a project's `tool/` script — a CI gate, an uploader, a release
/// note — is a few lines over typed classes rather than a directory walk
/// written once per project.
///
/// ```dart
/// var report = StoreShotsReport.read('build/flutterware/store');
/// for (var set in report!.sets) {
///   print('\${set.store} \${set.deviceClass} \${set.storeLocale}: '
///       '\${set.images.length}');
/// }
/// ```
///
/// This is published API, for the reason `lib/scenarios_report.dart` is: a
/// field renamed here breaks somebody's script. Hence
/// [storeShotsReportVersion], and hence [StoreShotsReport.read] refusing a
/// version it does not know rather than handing back a half-decoded object.
///
/// Plain Dart on purpose — nothing here may import `package:flutter`. A script
/// that reads an export runs under a bare `dart run`, exactly like
/// `tool/flutterware.dart` does.
///
/// **What it is not is a listing's structure.** Which listings a project
/// declares, which classes and which locales, is in `tool/flutterware.dart`
/// and needs no file to read. This says what the last export put on disk and
/// nothing else — the studio's panel walks the declaration and looks each set
/// up here, so a set with no entry draws as "not exported yet" and an entry
/// for a set nobody declares any more is never looked at. That asymmetry is
/// why there is no reconciliation anywhere, and no way for the two to
/// disagree.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// One set — one listing, one display class, one locale — as it was written.
class StoreShotsSet {
  const StoreShotsSet({
    required this.store,
    required this.deviceClass,
    required this.appLocale,
    required this.storeLocale,
    required this.output,
    required this.directory,
    required this.images,
    required this.exportedAt,
    this.failed = 0,
  });

  final String store;
  final String deviceClass;

  /// The app's tag, which is what the declaration spells and what the panel's
  /// locale switch offers. [storeLocale] is the slot it maps to.
  final String appLocale;
  final String storeLocale;

  /// The tree's root at the time of writing — recorded rather than assumed,
  /// because `--output` can send one export somewhere else and the panel still
  /// has to find the images afterwards.
  final String output;

  /// Relative to [output].
  final String directory;

  final List<String> images;
  final int failed;
  final DateTime exportedAt;

  /// What makes two entries the same set. Deliberately not the store's locale:
  /// two app locales may map to one store slot, and they are two sets.
  String get key => '$store/$deviceClass/$appLocale';

  /// Where an image of this set is, absolute.
  String pathOf(String image) => '$output/$directory/$image';

  Map<String, Object?> toJson() => {
    'store': store,
    'class': deviceClass,
    'appLocale': appLocale,
    'storeLocale': storeLocale,
    'output': output,
    'directory': directory,
    'images': images,
    if (failed > 0) 'failed': failed,
    'exportedAt': exportedAt.toIso8601String(),
  };

  static StoreShotsSet? fromJson(Map<String, Object?> json) {
    var at = DateTime.tryParse('${json['exportedAt']}');
    if (at == null) return null;
    return StoreShotsSet(
      store: '${json['store']}',
      deviceClass: '${json['class']}',
      appLocale: '${json['appLocale']}',
      storeLocale: '${json['storeLocale']}',
      output: '${json['output']}',
      directory: '${json['directory']}',
      images: [for (var image in json['images'] as List? ?? []) '$image'],
      failed: json['failed'] as int? ?? 0,
      exportedAt: at,
    );
  }
}

/// Bumped when a reader could no longer make sense of an older file.
///
/// A version a reader does not know reads as **nothing exported**, rather than
/// as a half-decoded object: the remedy is one export, and a wrong picture of a
/// listing is worse than no picture of one.
const storeShotsReportVersion = 1;

/// A listing's manifest, read and written.
class StoreShotsReport {
  const StoreShotsReport({this.sets = const []});

  /// Where the manifest sits under an export's output root. Dot-prefixed, so
  /// an upload tool pointed at that root ignores it.
  static const directory = '.store';

  static const fileName = 'manifest.json';

  final List<StoreShotsSet> sets;

  StoreShotsSet? operator [](String key) {
    for (var set in sets) {
      if (set.key == key) return set;
    }
    return null;
  }

  /// The most recent export any set records, or null when there are none.
  DateTime? get exportedAt => sets.isEmpty
      ? null
      : sets.map((s) => s.exportedAt).reduce((a, b) => a.isAfter(b) ? a : b);

  /// [updated] replacing the sets it names, everything else kept.
  ///
  /// A narrowed export writes one listing or one locale, and the sets it did
  /// not touch are still on disk and still true. Replacing the whole file
  /// would make `export --listing=play` erase the panel's knowledge of the App
  /// Store half, which is the same mistake §5's replace rule fixes on disk.
  StoreShotsReport merge(Iterable<StoreShotsSet> updated) {
    var byKey = {for (var set in sets) set.key: set};
    for (var set in updated) {
      byKey[set.key] = set;
    }
    var merged = byKey.values.toList()..sort((a, b) => a.key.compareTo(b.key));
    return StoreShotsReport(sets: merged);
  }

  /// Null when there is nothing to read, the file is unreadable, or it was
  /// written by a version this build does not know — all of which mean the
  /// same thing to a panel, and none of which is worth an error.
  /// The report for the export at [outputDirectory] — the root the tree was
  /// written to, the one holding `ios/` and `android/`.
  static StoreShotsReport? read(String outputDirectory) =>
      readFile(File(p.join(outputDirectory, directory, fileName)));

  /// The same, given the file itself.
  static StoreShotsReport? readFile(File file) {
    if (!file.existsSync()) return null;
    try {
      var json = jsonDecode(file.readAsStringSync());
      if (json is! Map) return null;
      if (json['version'] != storeShotsReportVersion) return null;
      return StoreShotsReport(
        sets: [
          for (var entry in json['sets'] as List? ?? [])
            if (entry is Map)
              ?StoreShotsSet.fromJson(entry.cast<String, Object?>()),
        ],
      );
    } on FormatException {
      return null;
    }
  }

  void writeTo(File file) {
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({
        'version': storeShotsReportVersion,
        'sets': [for (var set in sets) set.toJson()],
      }),
    );
  }
}
