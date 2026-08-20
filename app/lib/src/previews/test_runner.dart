import 'dart:convert';

import 'package:path/path.dart' as p;

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
  PreviewProgram({
    required this.packageRoot,
    required this.read,
    this.buildDirectory = TesterHost.defaultBuildDirectory,
  });

  final String packageRoot;

  /// Where the generated harness goes — the host's own directory, so an
  /// isolated runner never renumbers or prunes the warm lane's wrappers.
  final String buildDirectory;

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
      directory: buildDirectory,
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

  /// [errors] minus the ones that indict the lane rather than the entry.
  ///
  /// `flutter_test` answers **every** HTTP request with 400, so a preview of
  /// a widget that renders a remote image can never be anything but "broken"
  /// here — permanently, correct code and all. Its failure is marked
  /// `network` at the guest and set aside: two false positives out of ninety
  /// is enough to stop anybody reading the audit.
  List<Map<String, Object?>> get indicting => [
    for (var error in errors)
      if (error['network'] != true) error,
  ];

  bool get ok => compileError == null && failure == null && indicting.isEmpty;
}

/// One entry rendered and photographed, as [PreviewTestRunner.capture] hands
/// it over.
///
/// The picture and the tree are **paths**, not bytes: a frame is megabytes,
/// the service protocol is JSON, and the caller is going to hash and file the
/// pixels rather than look at them — the same transport the scenario
/// comparison uses.
class PreviewCaptureRow {
  const PreviewCaptureRow({
    required this.id,
    this.compileError,
    this.failure,
    this.errors = const [],
    this.image,
    this.width = 0,
    this.height = 0,
    this.tree,
  });

  final String id;

  /// Set when the compiler refused it, in which case nothing rendered.
  final String? compileError;

  /// Set when the entry's test did not come out clean — the builder threw,
  /// a timer outlived the audit clock. A frame may still exist beside it.
  final String? failure;

  /// What the framework reported, as `InspectErrors.toJson` wrote it.
  final List<Map<String, Object?>> errors;

  /// The settled screen as raw rgba on disk, or null when nothing rendered.
  final String? image;

  final int width;
  final int height;

  /// `InspectTree.toJson` on disk, beside the image.
  final String? tree;
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
    String buildDirectory = TesterHost.defaultBuildDirectory,
    void Function(String line)? onLog,
  }) : _program = PreviewProgram(
         packageRoot: packageRoot,
         read: read,
         buildDirectory: buildDirectory,
       ) {
    _host = TesterHost(
      packageRoot: packageRoot,
      flutterSdkRoot: flutterSdkRoot,
      program: _program,
      buildDirectory: buildDirectory,
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

  /// Renders and photographs [entryIds], handing each row over as it lands.
  ///
  /// One extension call per entry rather than one for the batch, because the
  /// caller is a comparison and a comparison answers rows as they become
  /// answerable — a batch reply would hold every verdict until the last
  /// render. The harness is brought up **once**: quarantine survives the
  /// loop, so one broken entry costs one blame pass rather than a recompile
  /// per row.
  ///
  /// Frames land under `<outDir>/<index>/`, one directory per entry so the
  /// harness's own within-call numbering cannot collide across calls.
  Future<void> capture({
    required List<String> entryIds,
    required String outDir,
    required Future<void> Function(PreviewCaptureRow row) onRow,
  }) => _host.exclusive(() async {
    _program.quarantined.clear();
    await _bringUp();

    for (var (index, id) in entryIds.indexed) {
      if (_program.quarantined[id] case var error?) {
        await onRow(PreviewCaptureRow(id: id, compileError: error));
        continue;
      }
      var response = await _host.vm.requireExtension(
        'ext.flutterware.previews.audit',
        args: {'entries': id, 'output': p.join(outDir, '$index')},
      );
      if (response!['error'] case String error) {
        throw StateError('the previews harness failed:\n$error');
      }
      var reported = (response['entries'] as Map).cast<String, Object?>();
      if (reported[id] case Map fields) {
        var row = fields.cast<String, Object?>();
        var failure = row['failure'] as String?;
        // Rendered, no failure, and yet no picture: this harness does not
        // know the `output` argument. That is version skew, not a broken
        // entry — a comparison's base side resolves the base commit's own
        // `package:flutterware`, and one from before capture ignores the
        // request silently. Name it, or every row reads "did not render"
        // against a checkout where nothing is wrong.
        if (failure == null && row['image'] == null) {
          failure =
              "this checkout's package:flutterware predates preview "
              'capture: the harness rendered the entry but handed back no '
              'picture';
        }
        await onRow(
          PreviewCaptureRow(
            id: id,
            failure: failure,
            errors: [
              for (var error in (row['errors'] as List? ?? const []))
                if (error case Map found) found.cast<String, Object?>(),
            ],
            image: row['image'] as String?,
            width: row['width'] as int? ?? 0,
            height: row['height'] as int? ?? 0,
            tree: row['tree'] as String?,
          ),
        );
      } else {
        await onRow(
          PreviewCaptureRow(
            id: id,
            failure: 'the harness returned nothing for this entry',
          ),
        );
      }
    }
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
