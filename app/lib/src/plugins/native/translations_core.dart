import 'dart:async';
import 'dart:io';

import 'package:flutterware/plugins.dart';
import 'package:flutterware/translations.dart';
import 'package:path/path.dart' as p;

import '../../translations/exporter.dart';
import '../../translations/loader.dart';
import '../../translations/row.dart';
import '../../translations/survey.dart';
import '../plugin_core.dart';
import '../plugin_host.dart';
import 'scenarios_core.dart';
import 'scenarios_results.dart';
import 'translations_address.dart';
import 'translations_results.dart';

/// The registered id — also what `tool/flutterware.dart` declares.
const translationsPluginId = 'flutterware.translations';

/// Which translation key is on which screen, and a picture of it.
///
/// Two halves that only answer together. A run knows **where a key appeared**,
/// because the app's catalog was funnelled through `indexTranslations` and
/// every string it rendered can be traced back by object identity. The files
/// on disk know **which keys exist and what each locale says**. Put them side
/// by side and the same pass that answers "show me this string in context"
/// also answers "where are we still showing English to a Dutch user" — for
/// free, because both halves were already needed.
///
/// Holds to the two rules every core holds to: the constructor allocates
/// nothing, and [report] only formats what somebody already caused to load.
/// Loading here is reading and parsing the catalog JSON — the run that
/// produces the screens is behind the `export` action, where a caller chose it
/// by name.
class TranslationsCore extends PluginCore {
  TranslationsCore(super.host);

  /// Declared packages, filtered to those the workspace knows about, so a typo
  /// cannot make the plugin scan a directory that is not there.
  late final List<String> packages = [
    for (var path in host.packagePaths)
      if (host.workspace.exists(path)) path,
  ];

  final _catalogs = <String, Map<String, LoadedCatalog>>{};
  final _failures = <String, String>{};
  final _pending = <String, Future<void>>{};

  /// The last export, **read back off disk** rather than kept from the run
  /// that produced it.
  ///
  /// Three things follow from reading it rather than remembering it. It
  /// survives a restart and a config reload — which swaps cores under mounted
  /// panels, so a core that only remembered would go permanently cold. It
  /// costs one JSON parse, which is inside [computeAll]'s budget. And it makes
  /// the panel the published reader's first consumer: if
  /// `package:flutterware/translations.dart` is wrong, it is wrong here, in
  /// front of whoever is about to ship it, rather than in somebody's script
  /// weeks later.
  final _exports = <String, ({TranslationExport export, DateTime at})>{};

  /// What `export` says while it is running.
  final _busy = <String, String>{};

  /// The catalogs declared for [path], as `tool/flutterware.dart` wrote
  /// them.
  List<({String name, String files, String template})> declaredFor(
    String path,
  ) {
    for (var config in host.packageConfigs) {
      if (config['path'] != path) continue;
      return [
        for (var entry in config['catalogs'] as List? ?? const [])
          if (entry is Map)
            (
              name: entry['name'] as String? ?? '',
              files: entry['files'] as String? ?? '',
              template: entry['template'] as String? ?? 'en',
            ),
      ];
    }
    return const [];
  }

  /// The loaded catalogs for [path], or null when nothing has read them yet.
  Map<String, LoadedCatalog>? catalogsFor(String path) => _catalogs[path];

  String? failureFor(String path) => _failures[path];

  /// The last export for [path], or null when none has been written.
  TranslationExport? exportFor(String path) => _exports[path]?.export;

  /// When it was written. Off the file's own timestamp, deliberately: the
  /// format carries no time of its own so that two exports of an unchanged
  /// suite stay byte-identical, and the filesystem already knows this.
  DateTime? exportedAt(String path) => _exports[path]?.at;

  /// Where a row *is*.
  ///
  /// Built here rather than left to a reader to reassemble, which is how two
  /// surfaces come to disagree about what a thing is called.
  Address addressFor(
    String package, {
    String? catalog,
    String? key,
    String? locale,
    TranslationFilter filter = TranslationFilter.all,
  }) => Address(
    worktree: host.worktree.name,
    plugin: host.id,
    segments: translationSegments(package, catalog: catalog, key: key),
    axes: translationAxes(locale: locale, filter: filter),
  );

  /// Where an export for [path] is looked for.
  String exportDirectoryFor(String path) => TranslationExporter.defaultOutputIn(
    host.workspace.packageFor(path).directory.path,
  );

  /// Every locale any of [path]'s catalogs has a file for, sorted.
  ///
  /// This is what an export runs across when the caller names no languages:
  /// **the set the project actually ships**, which is the only set for which
  /// "this locale is falling back" is a statement worth making.
  List<String> localesFor(String path) {
    var found = <String>{};
    for (var catalog in _catalogs[path]?.values ?? const <LoadedCatalog>[]) {
      found.addAll(catalog.byLocale.keys);
    }
    return found.toList()..sort();
  }

  void track(String path) => unawaited(_load(path));

  /// Drops the cached catalogs so the next read re-parses. What the panel
  /// calls when a translation file changes underneath it.
  void invalidate(String path) {
    _catalogs.remove(path);
    _failures.remove(path);
    _pending.remove(path);
    notifyChanged();
  }

  @override
  Future<void> computeAll() async {
    await Future.wait([for (var path in packages) _load(path)]);
  }

  Future<void> _load(String path) {
    if (_catalogs.containsKey(path)) return Future.value();
    if (_pending[path] case var pending?) return pending;
    return _pending[path] = () async {
      try {
        var root = host.workspace.packageFor(path).directory.path;
        _catalogs[path] = await loadCatalogs(
          declaredFor(path),
          read: catalogFilesUnder(root),
        );
        await _loadExport(path);
        _failures.remove(path);
      } catch (error) {
        _failures[path] = '$error';
      } finally {
        _pending.remove(path)?.ignore();
        notifyChanged();
      }
    }();
  }

  /// Reads the export beside [path], if there is one.
  ///
  /// Best effort and quiet about it: an export that is absent, half-written or
  /// from a version this build cannot read must not take the catalogs down
  /// with it. The table is useful with no export at all, which is the whole
  /// reason the panel does not wait for one.
  Future<void> _loadExport(String path) async {
    var directory = exportDirectoryFor(path);
    var file = File(p.join(directory, translationExportFile));
    if (!file.existsSync()) {
      _exports.remove(path);
      return;
    }
    try {
      _exports[path] = (
        export: await TranslationExport.read(directory),
        at: file.statSync().modified,
      );
    } catch (_) {
      _exports.remove(path);
    }
  }

  /// Every key the catalogs define, with what each locale says and the shot
  /// the last export found for it.
  ///
  /// **Values come from the files, not from the export**, because the files are
  /// what a person just edited and the export is from whenever it last ran. A
  /// row whose text disagrees with its picture is the honest rendering of a
  /// stale export.
  List<TranslationRow> rowsFor(String path) {
    var catalogs = _catalogs[path];
    if (catalogs == null) return const [];
    var export = _exports[path]?.export;
    var rows = <TranslationRow>[];
    for (var catalog in catalogs.values) {
      var keys = catalog.keys.toList()..sort();
      for (var key in keys) {
        var exported = export?['${catalog.name}/$key'];
        rows.add(
          TranslationRow(
            catalog: catalog.name,
            key: key,
            template: catalog.template,
            values: {
              for (var locale in catalog.byLocale.keys)
                locale: ?catalog.valueOf(locale, key),
            },
            shot: exported?.representative,
            occurrences: exported?.occurrences ?? const [],
          ),
        );
      }
    }
    return rows;
  }

  /// The template locale of [path]'s first catalog — what a switch starts on
  /// and what stays pinned beside whatever it switches to.
  String templateFor(String path) =>
      _catalogs[path]?.values.firstOrNull?.template ?? 'en';

  @override
  PluginReport get report => PluginReport(
    id: host.id,
    label: host.label,
    // Quiet when unconfigured. A project with no catalogs is not in trouble,
    // it just does not use the feature — the panel is where the setup
    // instructions live, and a permanent warning in the rail taught people to
    // stop reading the slot. Same policy as every other plugin's row.
    status: Status.none,
    badge: _badge,
    children: [
      for (var path in packages)
        PluginChild(
          id: path,
          label: path == '.' ? 'root' : path,
          status: _childStatus(path),
        ),
    ],
    actions: _actions,
    view: _view,
  );

  StatusBadge get _badge {
    for (var path in packages) {
      if (_failures.containsKey(path)) {
        return const StatusBadge.dot(Tone.error);
      }
    }
    // The one thing worth a mark on the rail. Not a count of everything the
    // export noticed — a suite that has not run says nothing, and a key with
    // no picture is a gap in coverage rather than a defect. A language with
    // nothing to say is a defect, and it reads with no export at all.
    for (var path in packages) {
      if (missingFor(path) > 0) return const StatusBadge.dot(Tone.warn);
    }
    return StatusBadge.none;
  }

  /// Keys some target locale has no text for.
  int missingFor(String path) {
    var locales = localesFor(path);
    var count = 0;
    for (var row in rowsFor(path)) {
      if (row.missingAnywhere(locales)) count++;
    }
    return count;
  }

  /// Keys the last export has no shot for — including all of them when there
  /// is no export.
  int withoutPictureFor(String path) {
    var count = 0;
    for (var row in rowsFor(path)) {
      if (!row.hasPicture) count++;
    }
    return count;
  }

  Status _childStatus(String path) {
    if (_busy[path] case var message?) return Status.info(message);
    if (_failures[path] case var failure?) return Status.error(failure);
    var declared = declaredFor(path);
    if (declared.isEmpty) return const Status.warn('No catalogs declared');
    var loaded = _catalogs[path];
    if (loaded == null) return Status.none;
    // A catalog whose glob matched nothing is the mistake worth shouting
    // about: everything downstream still works, and quietly attributes
    // nothing.
    var empty = [
      for (var catalog in loaded.values)
        if (catalog.keys.isEmpty) catalog.name,
    ];
    if (empty.isNotEmpty) {
      return Status.error(
        empty.length == 1
            ? 'Catalog "${empty.single}" matched no files'
            : '${empty.length} catalogs matched no files',
      );
    }
    var missing = missingFor(path);
    if (missing > 0) {
      return Status.warn('$missing keys untranslated somewhere');
    }
    var rows = rowsFor(path);
    return Status.good('${rows.length} keys · ${localesFor(path).join(', ')}');
  }

  PluginView get _view => PluginView([
    if (packages.isEmpty)
      const ViewText(
        'Declare a package with its catalogs in tool/flutterware.dart:\n'
        'fw.use(Translations(packages: [TranslationsPackage(app, catalogs: '
        "[TranslationCatalog(name: 'app', files: 'assets/i18n/*.json')])]));",
      ),
    for (var path in packages)
      ViewSection(path == '.' ? 'root' : path, [
        if (_failures[path] case var failure?)
          ViewText(failure)
        else ...[
          for (var catalog
              in _catalogs[path]?.values ?? const <LoadedCatalog>[])
            ViewField(
              catalog.name,
              '${catalog.keys.length} keys · '
              '${catalog.byLocale.keys.join(', ')} · '
              'from ${catalog.template}',
            ),
          if (missingFor(path) case var missing when missing > 0)
            ViewField('Untranslated somewhere', '$missing keys'),
          if (_exports[path] != null)
            ViewField(
              'Pictures',
              '${rowsFor(path).length - withoutPictureFor(path)} '
                  'of ${rowsFor(path).length} keys',
            )
          else
            const ViewText('No export yet — run it to add a picture per key.'),
        ],
      ]),
  ]);

  List<PluginAction> get _actions => [
    PluginAction(
      exportActionId,
      'Export',
      returns: TranslationExportResult,
      description:
          'Runs the scenarios across every locale the catalogs have, and '
          'writes a directory a translator can read: the screenshots, a '
          '`keys.json` of key to where it was seen, and a page that draws the '
          'box. Nothing is cropped and nothing is drawn into the pixels — the '
          'rectangle rides in the JSON, so the same file serves this page and '
          'a translation service. Read it back typed with '
          '`package:flutterware/translations.dart`.',
      parameters: [
        ActionParameter(
          'package',
          'Package',
          kind: ActionParameterKind.choice,
          required: false,
          description: 'Which declared package; the only one when there is one',
          options: [for (var path in packages) ActionOption(path)],
        ),
        const ActionParameter(
          'output',
          'Output',
          kind: ActionParameterKind.string,
          required: false,
          description:
              'Where the directory goes. Defaults to '
              '`${TranslationExporter.defaultOutput}` in the package, and is '
              'emptied first.',
        ),
        const ActionParameter(
          'languages',
          'Languages',
          kind: ActionParameterKind.string,
          required: false,
          description:
              'A matrix — `en,nl,fr`. Defaults to the source language alone, '
              'because that is the one a translator is shown: a service '
              'attaches the picture to the string id, not to a locale. Which '
              'locales are missing a key is read off the catalog files and '
              'needs no run. Name languages here when you want the target '
              'screens themselves — what German does to a button.',
        ),
        const ActionParameter(
          'device',
          'Device',
          kind: ActionParameterKind.string,
          required: false,
          description:
              'What the screens are captured on — `iphone-16`. One device, '
              'because a translator wants one picture per key and a second '
              'device only doubles the candidates.',
        ),
        const ActionParameter(
          'file',
          'File',
          kind: ActionParameterKind.string,
          required: false,
          description:
              'Narrow to one scenario file, package-relative. The export is '
              'only as complete as what it runs.',
        ),
        const ActionParameter(
          'capture-scale',
          'Capture scale',
          kind: ActionParameterKind.string,
          required: false,
          description:
              'Screenshot pixels per logical pixel, up to 4. Defaults to 2 — '
              'these are read on a retina screen and zoomed into, which is '
              'the one place the bytes are worth it.',
        ),
      ],
    ),
  ];

  @override
  Future<Object?> invoke(
    String actionId, {
    Map<String, Object?> arguments = const {},
  }) => switch (actionId) {
    exportActionId => export(arguments),
    _ => super.invoke(actionId, arguments: arguments),
  };

  /// Runs the suite and writes the export.
  ///
  /// **Re-runs rather than reading the last run**, for a reason the scenario
  /// web export shares and one it does not. Shared: an export is dated and
  /// shared, and may not be a picture of a suite as it stood at some earlier
  /// moment nobody recorded. Its own: the questions worth asking are
  /// cross-locale, and the last run was almost certainly one language.
  Future<TranslationExportResult> export(Map<String, Object?> arguments) async {
    var stopwatch = Stopwatch()..start();
    var path = _requested(arguments);
    await _load(path);
    if (_failures[path] case var failure?) throw StateError(failure);

    var catalogs = _catalogs[path] ?? const <String, LoadedCatalog>{};
    if (catalogs.isEmpty) {
      throw StateError(
        'Package "$path" declares no translation catalogs. Add them to its '
        'TranslationsPackage in tool/flutterware.dart.',
      );
    }

    // **One language by default, and it is the source one.**
    //
    // A translation service attaches a screenshot to a *string id*, not to a
    // locale: the translator is shown the English in place and writes the
    // French. Shots of the French would be a picture of what they are about to
    // replace. And the questions the other locales could answer — which of
    // them is missing a key — are answered by the catalog files with no run
    // at all, which is what the panel's columns already read.
    //
    // So running every locale cost N passes over the whole suite and bought
    // almost nothing. Naming languages still runs them, for the case that does
    // want target-locale screens: seeing what German does to a button.
    var languages = switch (arguments['languages']) {
      String value when value.trim().isNotEmpty => [
        for (var tag in value.split(',')) tag.trim(),
      ],
      _ => [templateFor(path)],
    };
    if (languages.isEmpty) {
      throw StateError(
        'No locales to run. The declared catalogs matched no files — check '
        'their `files:` globs, which are relative to the package.',
      );
    }

    var captureScale = switch (arguments['capture-scale']) {
      num value => value.toDouble(),
      String value => double.tryParse(value),
      _ => null,
    };
    if (arguments['capture-scale'] != null &&
        (captureScale == null || captureScale <= 0 || captureScale > 4)) {
      throw ArgumentError.value(
        arguments['capture-scale'],
        'capture-scale',
        'a number in (0, 4]',
      );
    }
    captureScale ??= 2;

    var packageRoot = host.workspace.packageFor(path).directory.path;
    var output = switch (arguments['output']) {
      String value when value.trim().isNotEmpty =>
        p.isAbsolute(value) ? value : p.join(packageRoot, value),
      _ => TranslationExporter.defaultOutputIn(packageRoot),
    };

    _setBusy(path, 'running ${languages.length} locales…');
    ScenarioRunResult run;
    var scenarios = _scenariosFor(path);
    try {
      run =
          (await scenarios.invoke(
                'run',
                arguments: {
                  'package': path,
                  'languages': languages.join(','),
                  'device': ?arguments['device'],
                  'file': ?arguments['file'],
                  'capture-scale': captureScale,
                  // The whole point: every step, so every screen a key was
                  // seen on is in the result rather than only the failures.
                  'steps': 'all',
                },
              ))!
              as ScenarioRunResult;
    } finally {
      _setBusy(path, 'building the export…');
      scenarios.dispose();
    }

    try {
      var worktreeRoot = host.worktree.path;
      var survey = await buildSurvey(
        run: run,
        catalogs: catalogs,
        readArtifact: (artifact) async {
          var file = File(p.join(worktreeRoot, artifact));
          return file.existsSync() ? file.readAsString() : null;
        },
        captureScale: captureScale,
      );

      var written = TranslationExporter(
        worktreeRoot: worktreeRoot,
      ).write(survey: survey, output: output, captureScale: captureScale);

      var occurrences = 0;
      for (var key in written.export.keys) {
        occurrences += key.occurrences.length;
      }
      var failed = 0;
      for (var package in run.packages) {
        for (var outcome in package.scenarios) {
          if (!outcome.ok) failed++;
        }
      }

      var result = TranslationExportResult(
        output: _relative(written.output),
        keysJson: _relative(written.keysJson),
        indexHtml: _relative(written.indexHtml),
        catalogs: written.export.catalogs.length,
        locales: languages.length,
        keys: written.export.keys.length,
        keysSeen: written.export.seen.length,
        occurrences: occurrences,
        shots: written.shots,
        missingShots: written.missingShots,
        fallingBack: written.export.findings.fallingBack.length,
        disagrees: written.export.findings.disagrees.length,
        notReached: written.export.findings.notReached.length,
        absentFromCatalog: written.export.findings.absentFromCatalog.length,
        overflowing: written.export.findings.overflowing.length,
        unkeyed: written.export.findings.unkeyed.length,
        scenariosFailed: failed,
        durationMs: stopwatch.elapsedMilliseconds,
        open: 'open ${_relative(written.indexHtml)}',
      );
      // Re-read rather than keep what was just built: the panel must show the
      // same bytes a push script would, and the one way to be sure of that is
      // to go through the same door.
      await _loadExport(path);
      return result;
    } finally {
      _setBusy(path, null);
    }
  }

  /// A scenarios core over this plugin's own declaration.
  ///
  /// Synthesized rather than reached for. Two cores would otherwise have to
  /// find each other through the session, which is a coupling the plugin
  /// contract deliberately does not have — and the translations plugin
  /// declares its own packages anyway, so the config it would borrow is config
  /// it already has. What this buys is everything: the matrix, the axis
  /// slugs, the artifact layout and the failure reporting are the scenarios
  /// plugin's, unchanged, so an export cannot drift from what `scenarios run`
  /// does.
  ScenariosCore _scenariosFor(String path) => ScenariosCore(
    PluginHost(
      id: scenariosPluginId,
      label: 'Scenarios',
      worktree: host.worktree,
      workspace: host.workspace,
      config: {
        'packages': [
          {'path': path},
        ],
      },
    ),
  );

  String _requested(Map<String, Object?> arguments) {
    var requested = arguments['package'];
    if (requested != null && requested is! String) {
      throw ArgumentError.value(requested, 'package', 'must be a package path');
    }
    if (requested == null) {
      if (packages.length == 1) return packages.single;
      if (packages.isEmpty) {
        throw StateError(
          'No packages are declared for this plugin. Add one to '
          'Translations(packages: …) in tool/flutterware.dart.',
        );
      }
      throw ArgumentError(
        '`package` is required when more than one is declared. '
        'Declared: ${packages.join(', ')}',
      );
    }
    if (!packages.contains(requested)) {
      throw ArgumentError.value(
        requested,
        'package',
        'not declared for this plugin. Declared: ${packages.join(', ')}',
      );
    }
    return requested as String;
  }

  void _setBusy(String path, String? message) {
    if (message == null) {
      _busy.remove(path);
    } else {
      _busy[path] = message;
    }
    notifyChanged();
  }

  /// A path as every surface reports it: relative to the worktree, so it
  /// survives being read on another machine.
  String _relative(String path) {
    var root = host.worktree.path;
    return p.isWithin(root, path) ? p.relative(path, from: root) : path;
  }
}

const exportActionId = 'export';

PluginCore translationsCoreFactory(PluginHost host) => TranslationsCore(host);
