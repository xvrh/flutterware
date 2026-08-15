import 'dart:convert';

import '../embedder/tester_host.dart';
import 'catalog_entry.dart';
import 'compile_blame.dart';
import 'devices.dart';
import 'harness_generator.dart';

/// What the harness is generated from, read fresh on every sync.
///
/// A record rather than two parameters because the two move together: a canvas
/// list edited in `tool/flutterware.dart` changes the generated program exactly
/// as adding a preview does, and a fingerprint that watched only the entries
/// would leave a warm harness framing them the old way.
typedef PreviewCatalog = ({
  List<CatalogEntry> entries,
  List<PreviewCanvas> canvases,
});

/// The previews half of a [TesterHost].
class PreviewProgram extends TesterProgram {
  PreviewProgram({required this.packageRoot, required this.read});

  final String packageRoot;

  /// Re-read on every sync, so a preview written while the harness is warm
  /// restarts it rather than staying invisible until somebody reopens the
  /// panel.
  final PreviewCatalog Function() read;

  /// Entries the compiler refused, and what it said. They are left out of the
  /// generated program — the harness imports every entry, so one that does not
  /// build fails the compile for all of them, and dropping it is what serves
  /// the rest.
  final quarantined = <String, String>{};

  /// The last read, so [writeEntrypoint] generates from what [sources]
  /// fingerprinted rather than from a second read that may have moved.
  PreviewCatalog? _last;

  /// Every entry the scan found, quarantine included — what blame is
  /// attributed against.
  List<CatalogEntry> get scanned => _last?.entries ?? const [];

  @override
  String get name => 'previews';

  @override
  String get readyLine => 'flutterware previews harness ready';

  @override
  List<String> sources() {
    var catalog = _last = read();
    return [
      for (var entry in _servable(catalog)) entry.id,
      // The generated file is a function of the canvases too, and a canvas
      // change has to restart the guest for the same reason an entry change
      // does: `main` has already run and no reload re-runs it.
      'canvases:${jsonEncode([for (var c in catalog.canvases) c.toJson()])}',
    ]..sort();
  }

  /// Generates from the catalog [sources] just read.
  ///
  /// The argument is the fingerprint rather than the material — an entry id is
  /// not enough to write a wrapper from — so this reads the catalog it was
  /// computed from instead of parsing it back.
  @override
  String writeEntrypoint(List<String> sources) {
    var catalog = _last ??= read();
    return writePreviewHarness(
      packageRoot,
      _servable(catalog),
      canvases: catalog.canvases,
    );
  }

  List<CatalogEntry> _servable(PreviewCatalog catalog) => [
    for (var entry in catalog.entries)
      if (!quarantined.containsKey(entry.id)) entry,
  ];
}

/// What one entry said when the harness rendered it.
class PreviewAuditRow {
  const PreviewAuditRow({
    required this.id,
    this.compileError,
    this.failure,
    this.errors = const [],
  });

  final String id;

  /// Set when the compiler refused it, in which case nothing rendered.
  final String? compileError;

  /// Set when it did not render at all — the builder threw outright, the test
  /// timed out. A different kind of broken from an entry that rendered badly.
  final String? failure;

  /// What the framework reported while it built and painted, as
  /// `InspectErrors.toJson` wrote it.
  final List<Map<String, Object?>> errors;

  bool get ok => compileError == null && failure == null && errors.isEmpty;
}

/// Renders a package's whole catalog under `flutter_tester` and reports what
/// each entry said.
///
/// The embedder guest renders one entry at a time in real time, which is right
/// for a panel somebody is looking at and wrong for a catalog-wide check: a
/// demo that animates for ever costs three real seconds there and microseconds
/// of fake clock here. What is *not* given up is fidelity — the harness spawns
/// its own tester precisely so it can omit `--use-test-fonts`, mounts each
/// entry under the same `CatalogGuest` the guest entrypoint mounts, and reports
/// through the same [GuestErrors] buffer, so the two backends' rows are
/// comparable.
class PreviewTestRunner {
  PreviewTestRunner({
    required String packageRoot,
    required String flutterSdkRoot,
    required PreviewCatalog Function() read,
    void Function(String line)? onLog,
  }) : _program = PreviewProgram(packageRoot: packageRoot, read: read) {
    _host = TesterHost(
      packageRoot: packageRoot,
      flutterSdkRoot: flutterSdkRoot,
      program: _program,
      onLog: onLog,
    );
  }

  final PreviewProgram _program;
  late final TesterHost _host;

  /// Rounds of drop-and-retry. Bounded for the reason the daemon's own loop is:
  /// each round quarantines at least one entry, and errors in one file
  /// routinely hide errors in the next.
  static const _blameRounds = 10;

  /// Renders [entryIds] — or everything — and reports each entry's verdict.
  Future<List<PreviewAuditRow>> audit({
    List<String>? entryIds,
    String? device,
    String? orientation,
  }) => _host.exclusive(() async {
    _program.quarantined.clear();
    await _bringUp();

    var response = await _host.vm.requireExtension(
      'ext.flutterware.previews.audit',
      args: {
        'entries': ?entryIds?.join(','),
        'device': ?device,
        'orientation': ?orientation,
      },
    );
    if (response!['error'] case String error) {
      throw StateError('the previews harness failed:\n$error');
    }

    var reported = (response['entries'] as Map).cast<String, Object?>();
    return [
      for (var entry in _program.quarantined.entries)
        if (entryIds == null || entryIds.contains(entry.key))
          PreviewAuditRow(id: entry.key, compileError: entry.value),
      for (var row in reported.entries)
        if (row.value case Map reported)
          PreviewAuditRow(
            id: row.key,
            failure: reported['failure'] as String?,
            errors: [
              for (var error in (reported['errors'] as List? ?? const []))
                if (error case Map fields) fields.cast<String, Object?>(),
            ],
          ),
    ];
  });

  /// A live harness, dropping whatever will not compile until one exists.
  ///
  /// The generated program imports every entry, so a single demo mid-edit fails
  /// the compile for the whole catalog. This reads the compiler's own
  /// diagnostics, quarantines the entries declared in the files it blamed, and
  /// tries again with the rest — the same bargain the catalog daemon strikes,
  /// and the reason an audit answers at all while something is broken.
  ///
  /// Errors nobody declares an entry in — a shared helper, the app itself —
  /// cannot be fixed by dropping anything, so they stay fatal.
  Future<void> _bringUp() async {
    for (var round = 0; round < _blameRounds; round++) {
      try {
        await _host.ensureGuest();
        // Warm: what is on disk may have moved since the last audit, and an
        // audit of code the user has already edited is worse than a slow one.
        if (round == 0) await _host.sync();
        return;
      } on TesterCompileException catch (e) {
        var blame = CompileBlame.of(
          e.output,
          entries: _program.scanned,
          projectRoot: _program.packageRoot,
          workingDirectory: _program.packageRoot,
        );
        if (blame.isEmpty) rethrow;
        var diagnostics = e.output.join('\n');
        for (var id in blame.entryIds) {
          _program.quarantined[id] = diagnostics;
        }
      }
    }
    throw StateError(
      'the previews harness still would not compile after $_blameRounds '
      'rounds of dropping what the compiler blamed',
    );
  }

  Future<void> dispose() => _host.dispose();
}
