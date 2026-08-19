import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:collection/collection.dart';
import 'package:flutterware/plugins.dart';
import 'package:path/path.dart' as p;

import '../../previews/catalog_entry.dart';
import '../../previews/devices.dart';
import '../../previews/headless_catalog.dart';
import '../../previews/protocol.dart';
import '../../motion/discovery.dart';
import '../../motion/filmstrip.dart';
import '../../motion/values_file.dart';
import '../plugin_core.dart';
import '../plugin_host.dart';
import 'motion_address.dart';
import 'motion_results.dart';

/// The registered id — also what `tool/flutterware.dart` declares.
const motionPluginId = 'flutterware.motion';

/// Motions per declared package: the syntactic scan projected into the report
/// and the `list` action.
///
/// Follows the dependencies core's rule: **nothing here starts work.** The
/// constructor allocates nothing and [report] only reads what somebody already
/// caused to scan. Scanning begins in [track], which the panel calls on mount
/// and `fw` calls for the duration of a request.
///
/// The panel's live half — a guest, a playhead, the values a build actually
/// read — is deliberately not here. It comes from `ext.flutterware.motion.*`
/// against a running guest, and the scan is what exists before there is one.
/// See `docs/superpowers/specs/2026-07-31-motion-design.md`.
class MotionCore extends PluginCore {
  MotionCore(super.host);

  final _scans = <String, Future<void>>{};
  final _results = <String, MotionScanResult>{};
  final _errors = <String, Object>{};

  List<String> get packages => host.packagePaths;

  /// Where this package's screens are, per `tool/flutterware.dart`.
  String directoryFor(String path) {
    for (var config in host.packageConfigs) {
      if (config['path'] == path) {
        if (config['directory'] case String directory) return directory;
      }
    }
    return defaultMotionDirectory;
  }

  MotionScanResult? resultFor(String path) => _results[path];

  Object? errorFor(String path) => _errors[path];

  bool isScanning(String path) =>
      _scans.containsKey(path) && !_results.containsKey(path);

  /// Where a motion *is*, playhead included.
  ///
  /// Built here rather than left to a reader to reassemble, which is how two
  /// surfaces come to disagree about what a thing is called.
  Address addressFor(
    String packagePath, {
    String? file,
    String? motion,
    double? t,
  }) => Address(
    worktree: host.worktree.name,
    plugin: host.id,
    segments: motionSegments(packagePath, file: file, motion: motion),
    axes: {'t': ?formatMotionT(t)},
  );

  /// The values file beside a screen — `home.dart` keeps its numbers in
  /// `home.motion.dart`.
  ///
  /// A convention rather than a lookup, and it is the only one: the editor has
  /// to know where to write before anything has been compiled, and a path it
  /// derives is a path it cannot get wrong halfway through a session.
  String valuesPathFor(String package, String motionFile) => p.join(
    host.workspace.packageFor(package).directory.path,
    p.joinAll(motionValuesPath(motionFile).split('/')),
  );

  /// Reads the values beside [motionFile], or says why it cannot.
  MotionFileResult readValues(
    String package,
    String motionFile, {
    String? constName,
  }) {
    var file = File(valuesPathFor(package, motionFile));
    if (!file.existsSync()) {
      return MotionFileResult(
        problems: [MotionFileProblem('no ${p.basename(file.path)} beside it')],
      );
    }
    return readMotionValues(file.readAsStringSync(), constName: constName);
  }

  /// Writes [targets] into the values file beside [motionFile].
  ///
  /// **Refuses when the file was not fully understood.** That is the whole of
  /// blast radius zero: this rewrites one expression in one file it owns, and
  /// where it cannot reproduce what it read it writes nothing at all rather
  /// than dropping the part it did not follow.
  List<MotionFileProblem> writeValues(
    String package,
    String motionFile,
    List<MotionTargetValues> targets, {
    String? constName,
  }) {
    var result = readValues(package, motionFile, constName: constName);
    if (!result.writable) {
      return result.problems.isEmpty
          ? [MotionFileProblem('the values file could not be read')]
          : result.problems;
    }
    File(
      valuesPathFor(package, motionFile),
    ).writeAsStringSync(result.file!.rewrite(targets));
    return const [];
  }

  /// Scans [path], unless it already has been. Idempotent.
  void track(String path) {
    if (_scans.containsKey(path)) return;
    var scanner = MotionScanner(
      packageRoot: host.workspace.packageFor(path).directory.path,
      directory: directoryFor(path),
    );
    // Parsing runs off-isolate, as the catalog's and scenarios' scans do.
    _scans[path] = Isolate.run(scanner.scan)
        .then<void>((result) => _results[path] = result)
        .catchError((Object error) => _errors[path] = error)
        .whenComplete(notifyChanged);
    notifyChanged();
  }

  @override
  Future<void> computeAll() async {
    for (var path in packages) {
      track(path);
    }
    await Future.wait(_scans.values);
  }

  @override
  PluginReport get report => PluginReport(
    id: host.id,
    label: host.label,
    status: _status(),
    children: [
      for (var path in packages)
        PluginChild(
          id: path,
          label: path == '.' ? 'root' : path,
          status: _packageStatus(path),
          badge: switch (_results[path]?.motions.length) {
            null || 0 => StatusBadge.none,
            var count => StatusBadge.count(count),
          },
        ),
    ],
    badge: _errors.isNotEmpty
        ? const StatusBadge.dot(Tone.error)
        : StatusBadge.none,
    view: _view(),
    actions: [
      PluginAction(
        'capture',
        'Capture',
        returns: Artifact,
        description:
            'Renders one motion at a point on its playhead and writes a PNG. '
            'The whole of an animation an agent can afford to look at: `t` is '
            'an axis like a device or a language, so the same call at several '
            'values is a filmstrip.',
        parameters: [
          ActionParameter(
            'motion',
            'Motion',
            required: true,
            description:
                'The `motion:` identifier, as `list` reports it — `homeMotion`',
          ),
          const ActionParameter(
            't',
            'Playhead',
            required: false,
            // A string rather than an integer, because a playhead is a
            // fraction and the kinds on offer are whole numbers or text.
            description: 'Where on the motion, 0 to 1. The end when omitted.',
          ),
          ActionParameter(
            'package',
            'Package',
            kind: ActionParameterKind.choice,
            required: false,
            description: 'Which declared package; the only one when omitted',
            options: [
              for (var path in packages)
                ActionOption(path, label: path == '.' ? 'root' : path),
            ],
          ),
          const ActionParameter(
            'device',
            'Device',
            kind: ActionParameterKind.choice,
            required: false,
            description: 'A device to render as; the panel otherwise',
          ),
        ],
      ),
      PluginAction(
        'filmstrip',
        'Filmstrip',
        returns: Artifact,
        description:
            'Renders a motion at several points on its playhead and composes '
            'them into one contact sheet. This is how to look at an animation '
            'without watching it: one image, N moments, each labelled with its '
            't and its milliseconds.',
        parameters: [
          ActionParameter(
            'motion',
            'Motion',
            required: true,
            description: 'The `motion:` identifier, as `list` reports it',
          ),
          const ActionParameter(
            'frames',
            'Frames',
            kind: ActionParameterKind.integer,
            required: false,
            description: 'How many, including both ends. 5 when omitted.',
          ),
          ActionParameter(
            'package',
            'Package',
            kind: ActionParameterKind.choice,
            required: false,
            description: 'Which declared package; the only one when omitted',
            options: [
              for (var path in packages)
                ActionOption(path, label: path == '.' ? 'root' : path),
            ],
          ),
          const ActionParameter(
            'device',
            'Device',
            kind: ActionParameterKind.choice,
            required: false,
            description: 'A device to render as; the panel otherwise',
          ),
        ],
      ),
      PluginAction(
        'list',
        'List',
        returns: MotionListResult,
        description:
            'Every motion of a package, with its targets and where each is '
            'read — from the syntactic scan, without compiling or running '
            'anything. Read the diagnostics: a target named by an expression '
            'rather than a literal is real at run time and invisible here.',
        parameters: [
          ActionParameter(
            'package',
            'Package',
            kind: ActionParameterKind.choice,
            required: false,
            description: 'Which declared package; all of them when omitted',
            options: [
              for (var path in packages)
                ActionOption(path, label: path == '.' ? 'root' : path),
            ],
          ),
        ],
      ),
    ],
  );

  @override
  Future<Object?> invoke(
    String actionId, {
    Map<String, Object?> arguments = const {},
  }) async {
    if (actionId == 'capture') return _capture(arguments);
    if (actionId == 'filmstrip') return _filmstrip(arguments);
    if (actionId != 'list') return super.invoke(actionId, arguments: arguments);
    var wanted = _requestedPackages(arguments['package']);
    for (var path in wanted) {
      track(path);
    }
    await Future.wait([for (var path in wanted) ?_scans[path]]);
    return MotionListResult(
      packages: [for (var path in wanted) _listPackage(path)],
    );
  }

  /// One frame of a motion, at a point on its playhead.
  ///
  /// Goes through [HeadlessCatalog] rather than the panel's session, so this
  /// answers the same whether a panel is open or nothing is running at all —
  /// the rule the catalog's headless half already keeps.
  Future<Artifact> _capture(Map<String, Object?> arguments) async {
    var t = switch (arguments['t']) {
      num value => value.toDouble().clamp(0.0, 1.0),
      String text when double.tryParse(text) != null => double.parse(
        text,
      ).clamp(0.0, 1.0),
      // The end, because the finished state is what a still of an animation is
      // usually being asked for.
      _ => 1.0,
    };
    var (packagePath, motion, entry, catalog) = await _resolve(arguments);
    var device = _deviceOf(arguments);
    var output = p.join(
      host.workspace.appContext.appToolDirectory.path,
      'build',
      'motion',
      '${motion.values}-t${(t * 1000).round()}.png',
    );
    var captured = await catalog.capture(
      entryId: entry.id,
      output: output,
      viewport: device == null
          ? CaptureViewport.panel
          : CaptureViewport.of(device),
      motionT: t,
    );

    return Artifact(
      kind: Artifact.png,
      // Addressed at the playhead it was taken at, per the rule that a
      // screenshot is under-specified without its axis assignment.
      address: addressFor(
        packagePath,
        file: motion.file,
        motion: motion.values,
        t: t,
      ),
      path: p.relative(captured.file.path, from: host.worktree.path),
      meta: {
        'motion': motion.values,
        'file': motion.file,
        't': t,
        'bytes': captured.file.lengthSync(),
        'device': ?device?.id,
      },
    );
  }

  /// Several frames of a motion, as one sheet.
  Future<Artifact> _filmstrip(Map<String, Object?> arguments) async {
    var (packagePath, motion, entry, catalog) = await _resolve(arguments);
    var frames = switch (arguments['frames']) {
      int value => value,
      String text when int.tryParse(text) != null => int.parse(text),
      _ => 5,
    }.clamp(2, 24);

    var device = _deviceOf(arguments);
    var output = p.join(
      host.workspace.appContext.appToolDirectory.path,
      'build',
      'motion',
      '${motion.values}-filmstrip.png',
    );
    var strip = await catalog.filmstrip(
      entryId: entry.id,
      output: output,
      stops: filmstripStops(frames),
      viewport: device == null
          ? CaptureViewport.panel
          : CaptureViewport.of(device),
    );

    return Artifact(
      kind: Artifact.png,
      // The whole motion rather than a moment in it, so the address has no `t`.
      address: addressFor(
        packagePath,
        file: motion.file,
        motion: motion.values,
      ),
      path: p.relative(strip.file.path, from: host.worktree.path),
      meta: {
        'motion': motion.values,
        'file': motion.file,
        'frames': strip.stops.length,
        'durationMs': strip.durationMs,
        'bytes': strip.file.lengthSync(),
        'device': ?device?.id,
      },
    );
  }

  Device? _deviceOf(Map<String, Object?> arguments) =>
      switch (arguments['device']) {
        String id when id.isNotEmpty && isDeviceId(id) => deviceById(id),
        _ => null,
      };

  /// The package, the motion, the catalog entry that mounts it, and a headless
  /// catalog to drive — everything both actions need before they diverge.
  Future<(String, MotionRef, CatalogEntry, HeadlessCatalog)> _resolve(
    Map<String, Object?> arguments,
  ) async {
    var wanted = '${arguments['motion'] ?? ''}';
    if (wanted.isEmpty) {
      throw ArgumentError.value(wanted, 'motion', 'name a motion');
    }
    var packagePath = _requestedPackages(arguments['package']).first;
    track(packagePath);
    await _scans[packagePath];

    var motion = _results[packagePath]?.motions.firstWhereOrNull(
      (candidate) => candidate.values == wanted,
    );
    if (motion == null) {
      var known = _results[packagePath]?.motions
          .map((m) => m.values)
          .nonNulls
          .join(', ');
      throw ArgumentError.value(
        wanted,
        'motion',
        'not found in $packagePath; try '
            '${known == null || known.isEmpty ? 'none' : known}',
      );
    }

    var catalog = _headless(packagePath);
    // The entry whose source file is the one the motion was scanned from —
    // the same join the panel makes, so a picture and the panel agree.
    // `check`, not a render: this wants the entry *list*, and asking for one
    // by rendering the whole catalog was paying for every frame in it to look
    // up a single id.
    var checked = await catalog.check();
    var entry = checked.servable.firstWhereOrNull((e) => e.path == motion.file);
    if (entry == null) {
      throw StateError(
        '`${motion.values}` lives in ${motion.file}, which is not a catalog '
        'entry — a motion is captured through the demo that mounts it',
      );
    }
    return (packagePath, motion, entry, catalog);
  }

  HeadlessCatalog _headless(String packagePath) => HeadlessCatalog(
    dartExecutable: p.join(host.workspace.flutterSdk.root, 'bin', 'dart'),
    config: DaemonConfig.forPackage(
      appToolDirectory: host.workspace.appContext.appToolDirectory.path,
      packageRoot: host.workspace.packageFor(packagePath).directory.path,
      flutterSdkRoot: host.workspace.flutterSdk.root,
      roots: [directoryFor(packagePath)],
    ),
  );

  List<String> _requestedPackages(Object? argument) {
    if (argument is! String || argument.isEmpty) return packages;
    if (!packages.contains(argument)) {
      throw ArgumentError.value(
        argument,
        'package',
        'not declared for this plugin; try ${packages.join(', ')}',
      );
    }
    return [argument];
  }

  MotionListPackage _listPackage(String path) {
    var result = _results[path];
    return MotionListPackage(
      path: path,
      directory: directoryFor(path),
      error: _errors[path]?.toString(),
      diagnostics: result?.diagnostics ?? const [],
      motions: [
        for (var motion in result?.motions ?? const <MotionRef>[])
          MotionListMotion(
            file: motion.file,
            line: motion.line,
            values: motion.values,
            address: motion.values == null
                ? null
                : '${addressFor(path, file: motion.file, motion: motion.values)}',
            targets: [
              for (var target in motion.targets)
                MotionListTarget(
                  name: target.name,
                  line: target.line,
                  properties: target.properties,
                  boxed: target.boxed,
                ),
            ],
          ),
      ],
    );
  }

  Status _status() {
    if (packages.isEmpty) return Status.none;
    if (_errors.isNotEmpty) return const Status.error('scan failed');
    return packages.any(isScanning)
        ? const Status.info('scanning…')
        : Status.none;
  }

  Status _packageStatus(String path) {
    if (_errors.containsKey(path)) return const Status.error('scan failed');
    if (!_scans.containsKey(path)) return Status.none;
    if (isScanning(path)) return const Status.info('scanning…');
    return Status.none;
  }

  PluginView _view() {
    if (packages.isEmpty) {
      return const PluginView([
        ViewText(
          'This plugin has no packages. Add them in tool/flutterware.dart.',
          tone: Tone.warn,
        ),
      ]);
    }
    return PluginView([
      for (var path in packages) ...[
        ViewText(path == '.' ? 'root' : path, tone: Tone.neutral),
        if (_errors[path] case var error?)
          ViewText('$error', tone: Tone.error)
        else if (_results[path] case var result?) ...[
          for (var motion in result.motions)
            ViewText(
              '${motion.values ?? '<expression>'} — '
              '${motion.file}:${motion.line}, '
              '${motion.targets.length} target'
              '${motion.targets.length == 1 ? '' : 's'}',
            ),
          if (result.motions.isEmpty) const ViewText('No motions found.'),
          for (var diagnostic in result.diagnostics)
            ViewText(diagnostic, tone: Tone.warn),
        ] else
          const ViewText('Not scanned yet.', tone: Tone.neutral),
      ],
    ]);
  }
}

PluginCore motionCoreFactory(PluginHost host) => MotionCore(host);
