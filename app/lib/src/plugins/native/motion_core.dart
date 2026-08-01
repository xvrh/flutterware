import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutterware/plugins.dart';
import 'package:path/path.dart' as p;

import '../../motion/discovery.dart';
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
    if (packages.isEmpty) return const Status.warn('no packages');
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
