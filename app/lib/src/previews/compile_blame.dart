import 'package:path/path.dart' as p;

import 'catalog_entry.dart';

/// Works out which entries a failed compile can be blamed on.
///
/// The entrypoint imports every entry, so one demo that does not compile fails
/// the compile for all of them. Rather than let that break the catalog, the
/// daemon drops what it can blame and serves the rest — which needs a way to
/// get from a compiler diagnostic back to an entry.
///
/// Blame is per *file*, not per declaration: a file that does not compile takes
/// every entry declared in it, because none of them can be reached.
class CompileBlame {
  CompileBlame({required this.entryIds, required this.unattributed});

  /// Entries declared in a file the compiler reported an error in.
  final Set<String> entryIds;

  /// Files with errors that no entry is declared in — a shared helper, the
  /// generated entrypoint, something in the app itself.
  ///
  /// Nothing can be dropped to fix these, so a compile that produces only these
  /// stays fatal. Reporting it beats quietly serving a catalog that is missing
  /// entries for unreported reasons.
  final Set<String> unattributed;

  bool get isEmpty => entryIds.isEmpty;

  /// Reads [output] — the compiler's diagnostics, verbatim — and attributes
  /// each error to an entry of [entries] where it can.
  ///
  /// Diagnostics name paths relative to the compiler's working directory, so
  /// [workingDirectory] is needed to resolve them; [projectRoot] resolves
  /// [CatalogEntry.path].
  static CompileBlame of(
    List<String> output, {
    required List<CatalogEntry> entries,
    required String projectRoot,
    required String workingDirectory,
  }) {
    var byPath = <String, List<CatalogEntry>>{};
    for (var entry in entries) {
      byPath
          .putIfAbsent(
            p.canonicalize(p.join(projectRoot, entry.path)),
            () => [],
          )
          .add(entry);
    }

    var blamed = <String>{};
    var unattributed = <String>{};
    for (var file in errorFiles(output, workingDirectory: workingDirectory)) {
      var declared = byPath[file];
      if (declared == null) {
        unattributed.add(file);
      } else {
        blamed.addAll(declared.map((e) => e.id));
      }
    }
    return CompileBlame(entryIds: blamed, unattributed: unattributed);
  }

  /// `tool/catalog/demos/broken.dart:5:25: Error: Method not found: ...`
  ///
  /// Only `Error:` — a warning does not fail a compile, and dropping an entry
  /// over one would lose a working demo.
  static final _diagnostic = RegExp(r'^(.+\.dart):\d+:\d+: Error:');

  /// The files [output] reports errors in, as canonical absolute paths.
  static Set<String> errorFiles(
    List<String> output, {
    required String workingDirectory,
  }) {
    var files = <String>{};
    for (var line in output) {
      var match = _diagnostic.firstMatch(line.trim());
      if (match == null) continue;
      var reported = match.group(1)!;
      // The compiler has emitted both plain paths and file: URIs depending on
      // how it was invoked; accept either rather than depend on which.
      if (reported.startsWith('file:')) {
        reported = p.fromUri(Uri.parse(reported));
      }
      files.add(
        p.canonicalize(
          p.isAbsolute(reported)
              ? reported
              : p.join(workingDirectory, reported),
        ),
      );
    }
    return files;
  }
}
