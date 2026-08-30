import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:collection/collection.dart';
import 'package:crypto/crypto.dart';
import 'package:flutterware/plugins.dart';
import 'package:path/path.dart' as p;

import '../../previews/catalog_render.dart';
import '../../previews/catalog_entry.dart';
import '../../previews/devices.dart';
import '../../previews/headless_catalog.dart';
import '../../embedder/build_directory.dart';
import '../../motion/video.dart';
import '../../previews/catalog_picture.dart';
import '../../previews/protocol.dart';
import '../../previews/test_runner.dart';
import '../../previews/tester_renderer.dart';
import '../../motion/discovery.dart';
import '../../motion/filmstrip.dart';
import '../../motion/stage_file.dart';
import '../../motion/values_file.dart';
import '../plugin_core.dart';
import '../plugin_host.dart';
import 'previews_core.dart';
import 'motion_address.dart';
import 'motion_results.dart';

/// The registered id — also what `tool/flutterware.dart` declares.
const motionPluginId = 'flutterware.motion';

/// What this plugin is, for a reader who has only the id — see
/// `PluginReport.description`.
const _pluginDescription =
    'The animations each declared package declares, rendered at any point on '
    'their playhead so a curve can be looked at rather than described.';

/// Motions per declared package: the syntactic scan projected into the report
/// and the `list` action.
///
/// Follows the dependencies core's rule: nothing here starts work. The
/// constructor allocates nothing and [report] only reads what a previous call
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

  /// Which generation of a scan is the current one, so a late isolate from an
  /// older generation cannot overwrite a newer answer. See [rescan].
  final _epochs = <String, int>{};
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
  /// Refuses when the file was not fully understood. This rewrites one
  /// expression in one file it owns, and where it cannot reproduce what it read
  /// it writes nothing at all rather than dropping the part it did not
  /// follow.
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
    File(valuesPathFor(package, motionFile))
        .writeAsStringSync(result.file!.rewrite(targets));
    return const [];
  }

  /// Scans [path], unless it already has been. Idempotent.
  void track(String path) {
    if (_scans.containsKey(path)) return;
    var scanner = MotionScanner(
      packageRoot: host.workspace.packageFor(path).directory.path,
      directory: directoryFor(path),
    );
    var epoch = (_epochs[path] ?? 0) + 1;
    _epochs[path] = epoch;
    // Parsing runs off-isolate, as the catalog's and scenarios' scans do.
    _scans[path] = Isolate.run(scanner.scan)
        .then<void>((result) {
          // A scan that lost to a [rescan] must not land. Without this, an
          // isolate started before a motion was written finishes after the one
          // started to see it, and the fresh answer is overwritten by the
          // stale one — which is `ScanCache`'s epoch guard, owed here because
          // this core still keeps its own maps.
          if (_epochs[path] != epoch) return;
          _results[path] = result;
          // A success outlives any earlier failure — a save caught mid-write
          // must not brand the package "scan failed" forever.
          _errors.remove(path);
        })
        .catchError((Object error) {
          if (_epochs[path] == epoch) _errors[path] = error;
        })
        .whenComplete(notifyChanged);
    notifyChanged();
  }

  /// Drops [path]'s scan so the next [track] recomputes it.
  ///
  /// The scan is one-shot per session, so a file this plugin has just written
  /// is invisible to it — `add-element` on a motion `new` had made came back
  /// "no motion named that". Bumping the epoch is what makes dropping it safe
  /// while one is still in flight.
  void rescan(String path) {
    _epochs[path] = (_epochs[path] ?? 0) + 1;
    _scans.remove(path)?.ignore();
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
    description: _pluginDescription,
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
          const ActionParameter(
            'mode',
            'Clock',
            kind: ActionParameterKind.choice,
            required: false,
            description:
                'How each stop is reached. `playhead` sets the playhead and '
                'draws, and no time passes — right for a scene, which is what '
                'a motion is meant to be. `time` also lets exactly one frame '
                'of the frame rate elapse, so a screen with animation of its '
                'own — a controller, an implicit animation, a scroll spring — '
                'advances by exactly that much rather than by however long '
                'the machine took.',
            options: [
              ActionOption('playhead', label: 'playhead'),
              ActionOption('time', label: 'time'),
            ],
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
        'video',
        'Video',
        returns: Artifact,
        description:
            'Renders the whole motion to an mp4 at its own duration, one '
            'frame per video frame. Not a screen recording: every frame is '
            'the motion evaluated at a playhead position, so the clip is '
            'exactly what the scrubber shows and is not rendered in real '
            'time. Needs `ffmpeg` on PATH.',
        parameters: [
          ActionParameter(
            'motion',
            'Motion',
            required: true,
            description: 'The `motion:` identifier, as `list` reports it',
          ),
          const ActionParameter(
            'fps',
            'Frames per second',
            kind: ActionParameterKind.integer,
            required: false,
            description: 'Frames a second of output. 30 when omitted.',
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
          const ActionParameter(
            'knobs',
            'Knobs',
            required: false,
            description:
                'Values to turn before rendering: `name=value,name=value`, or '
                'a JSON object. This is how one authored motion becomes many '
                'clips — the same timing over different words, a different '
                'accent, a different locale — without touching the file it '
                'was authored in.',
          ),
          const ActionParameter(
            'axes',
            'Axes',
            required: false,
            description:
                'What the shell around the demo offers — `theme=dark`. Same '
                'syntax as knobs.',
          ),
          const ActionParameter(
            'mode',
            'Clock',
            kind: ActionParameterKind.choice,
            required: false,
            description:
                'How each stop is reached. `playhead` sets the playhead and '
                'draws, and no time passes — right for a scene, which is what '
                'a motion is meant to be. `time` also lets exactly one frame '
                'of the frame rate elapse, so a screen with animation of its '
                'own — a controller, an implicit animation, a scroll spring — '
                'advances by exactly that much rather than by however long '
                'the machine took.',
            options: [
              ActionOption('playhead', label: 'playhead'),
              ActionOption('time', label: 'time'),
            ],
          ),
          const ActionParameter(
            'scope',
            'Scope',
            required: false,
            description:
                'Which mounted playhead to walk, when the screen has several. '
                'A composed screen mounts one scope for its own flow and one '
                'per component inside it. Omitted, the outermost — the flow — '
                'because scopes mount in tree order. The scopes a render saw '
                'come back on the result, so a clip of the wrong timeline is '
                'visible rather than merely wrong.',
          ),
        ],
      ),
      PluginAction(
        'new',
        'New motion',
        returns: Artifact,
        description:
            'Starts a motion from nothing: a stage, a values file and a '
            'preview entry, with one element already in them so the first '
            'render is not a blank screen. This is the cold start — by hand it '
            'is roughly a hundred lines across two files that have to agree on '
            'a string.',
        parameters: [
          const ActionParameter(
            'name',
            'Name',
            required: true,
            description:
                'Lower snake case, and the basename of all three files — '
                '`checkout` gives `checkout.dart`, `checkout.motion.dart` and '
                '`checkout.stage.dart`.',
          ),
          const ActionParameter(
            'width',
            'Stage width',
            kind: ActionParameterKind.integer,
            required: false,
            description: 'Logical pixels. 360 when omitted.',
          ),
          const ActionParameter(
            'height',
            'Stage height',
            kind: ActionParameterKind.integer,
            required: false,
            description: 'Logical pixels. 640 when omitted.',
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
        ],
      ),
      PluginAction(
        'add-element',
        'Add element',
        returns: Artifact,
        description:
            "Adds one placeholder to a motion's draft stage. The stage is the "
            'only place the tool may create a target: the other place a target '
            'is named is your build method, which it does not touch. Refuses '
            'rather than approximates — a stage file outside the grammar comes '
            'back with the offset that broke it and nothing is written.',
        parameters: [
          const ActionParameter(
            'motion',
            'Motion',
            required: true,
            description:
                'The `motion:` identifier, as `list` reports it. Its stage is '
                'the `.stage.dart` beside it.',
          ),
          const ActionParameter(
            'target',
            'Target',
            required: true,
            description:
                'The name the lane and the read site will both use. Must not '
                'already be on the stage.',
          ),
          const ActionParameter(
            'kind',
            'Kind',
            kind: ActionParameterKind.choice,
            required: false,
            description: 'box when omitted',
            options: [
              ActionOption('box'),
              ActionOption('text'),
              ActionOption('circle'),
            ],
          ),
          const ActionParameter(
            'x',
            'X',
            kind: ActionParameterKind.integer,
            required: false,
            description: 'Left, in stage pixels. 24 when omitted.',
          ),
          const ActionParameter(
            'y',
            'Y',
            kind: ActionParameterKind.integer,
            required: false,
            description:
                'Top, in stage pixels. Below the lowest element when omitted, '
                'so a bare call stacks rather than overlaps.',
          ),
          const ActionParameter(
            'width',
            'Width',
            kind: ActionParameterKind.integer,
            required: false,
            description: '280 when omitted.',
          ),
          const ActionParameter(
            'height',
            'Height',
            kind: ActionParameterKind.integer,
            required: false,
            description: '48 when omitted.',
          ),
          const ActionParameter(
            'label',
            'Label',
            required: false,
            description: 'Shown inside a `text` placeholder.',
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
        ],
      ),
      PluginAction(
        'verify',
        'Verify',
        returns: MotionVerifyResult,
        description:
            'Renders the same moments twice, and again backwards, and reports '
            'whether the pictures were identical. This is how to know a '
            'motion will export correctly, because a clip cannot be checked '
            'by watching it: a frame of the wrong moment looks exactly as '
            'plausible as a frame of the right one. A motion that repeats and '
            'is order-free is a function of its playhead, which is what a '
            'scene is. One that is not can still be exported with '
            '`mode=time`, which drives such a screen deliberately.',
        parameters: [
          ActionParameter(
            'motion',
            'Motion',
            required: true,
            description: 'The `motion:` identifier, as `list` reports it',
          ),
          const ActionParameter(
            'stops',
            'Stops',
            kind: ActionParameterKind.integer,
            required: false,
            description:
                'How many playhead positions to compare, including both ends. '
                '9 when omitted. More is a finer check and a longer one.',
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
          const ActionParameter(
            'scope',
            'Scope',
            required: false,
            description:
                'Which mounted playhead to drive, when a screen has more '
                'than one',
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
    if (actionId == 'video') return _video(arguments);
    if (actionId == 'verify') return _verify(arguments);
    if (actionId == 'new') return _new(arguments);
    if (actionId == 'add-element') return _addElement(arguments);
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
    var captured = await _rendererFor(packagePath, engine: arguments['engine'])
        .capture(
          CatalogRender(
            entryId: entry.id,
            screenshot: output,
            viewport: device == null
                ? CaptureViewport.panel
                : CaptureViewport.of(device),
            motionT: t,
          ),
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
    var stops = filmstripStops(frames);
    var walk = await _rendererFor(packagePath, engine: arguments['engine'])
        .walk(
          CatalogWalk(
            entryId: entry.id,
            stops: stops,
            viewport: device == null
                ? CaptureViewport.panel
                : CaptureViewport.of(device),
            scope: arguments['scope'] as String?,
            mode: arguments['mode'] == 'time'
                ? WalkMode.time
                : WalkMode.playhead,
          ),
        );
    var cells = <FilmstripFrame>[];
    await for (var frame in walk.frames) {
      cells.add(
        FilmstripFrame(
          image: decodeTesterFrame(
            frame.pixels,
            width: frame.width,
            height: frame.height,
          ),
          t: frame.t,
          // The playhead's own units, from the duration the walk reported.
          ms: (frame.t * walk.durationMs).round(),
        ),
      );
    }
    var strip = composeFilmstrip(cells, output: output);

    return Artifact(
      kind: Artifact.png,
      // The whole motion rather than a moment in it, so the address has no `t`.
      address: addressFor(
        packagePath,
        file: motion.file,
        motion: motion.values,
      ),
      path: p.relative(strip.path, from: host.worktree.path),
      meta: {
        'motion': motion.values,
        'file': motion.file,
        'frames': cells.length,
        'durationMs': walk.durationMs,
        'bytes': strip.lengthSync(),
        'device': ?device?.id,
        'scope': ?walk.scope,
        if (walk.scopes.length > 1) 'scopes': walk.scopes,
      },
    );
  }

  /// The whole motion, as a file somebody can play.
  Future<Artifact> _video(Map<String, Object?> arguments) async {
    var (packagePath, motion, entry, catalog) = await _resolve(arguments);
    var fps = switch (arguments['fps']) {
      int value => value,
      String text when int.tryParse(text) != null => int.parse(text),
      _ => 30,
    }.clamp(1, 120);

    var device = _deviceOf(arguments);
    var knobs = PreviewsCore.parsePairs(arguments['knobs']);
    var axes = PreviewsCore.parsePairs(arguments['axes']);
    var output = p.join(
      host.workspace.appContext.appToolDirectory.path,
      'build',
      'motion',
      '${motion.values}${_settingSuffix(knobs, axes)}.mp4',
    );
    // The whole motion at `fps`, and the stops are not computed here: only the
    // running motion knows how long it is.
    var walk = await _rendererFor(packagePath, engine: arguments['engine'])
        .walk(
          CatalogWalk(
            entryId: entry.id,
            fps: fps,
            viewport: device == null
                ? CaptureViewport.panel
                : CaptureViewport.of(device),
            knobs: knobs,
            axes: axes,
            scope: arguments['scope'] as String?,
            mode: arguments['mode'] == 'time'
                ? WalkMode.time
                : WalkMode.playhead,
          ),
        );
    var video = await encodeWalk(walk, output: output, fps: fps);

    return Artifact(
      kind: Artifact.mp4,
      // The whole motion rather than a moment in it, so the address has no `t`.
      address: addressFor(
        packagePath,
        file: motion.file,
        motion: motion.values,
      ),
      path: p.relative(video.file.path, from: host.worktree.path),
      meta: {
        'motion': motion.values,
        'file': motion.file,
        'fps': video.fps,
        'frames': video.frames,
        'durationMs': video.durationMs,
        'renderMs': video.renderTime.inMilliseconds,
        'encodeMs': video.encodeTime.inMilliseconds,
        'bytes': video.file.lengthSync(),
        if (video.parts > 1) 'parts': video.parts,
        'device': ?device?.id,
        if (knobs.isNotEmpty) 'knobs': knobs,
        if (axes.isNotEmpty) 'axes': axes,
        'scope': ?video.scope,
        if (video.scopes.length > 1) 'scopes': video.scopes,
      },
    );
  }

  /// Renders the same moments three ways and compares the pixels.
  ///
  /// The check a clip cannot get from being watched. Two runs of the same
  /// stops say whether the render is reproducible at all; the same stops taken
  /// **backwards** say whether the pictures depend on the playhead alone,
  /// which is the property the word "scene" means and the one every
  /// frame-based renderer states as a rule for its users to follow. Here it is
  /// measured instead.
  ///
  /// Backwards rather than a second forward pass, because that is what an
  /// implicit animation, a spring or a scroll position cannot survive: walked
  /// the other way they arrive at each stop from the other side and settle
  /// somewhere else. A forward pass repeated would agree with itself and say
  /// nothing.
  Future<MotionVerifyResult> _verify(Map<String, Object?> arguments) async {
    var (packagePath, motion, entry, _) = await _resolve(arguments);
    var count = switch (arguments['stops']) {
      int value => value,
      String text when int.tryParse(text) != null => int.parse(text),
      _ => 9,
    }.clamp(2, 60);
    var stops = [for (var i = 0; i < count; i++) i / (count - 1)];
    var device = _deviceOf(arguments);
    var renderer = _rendererFor(packagePath, engine: arguments['engine']);

    Future<CatalogWalkResult> take(List<double> order) => renderer.walk(
      CatalogWalk(
        entryId: entry.id,
        stops: order,
        viewport: device == null
            ? CaptureViewport.panel
            : CaptureViewport.of(device),
        scope: arguments['scope'] as String?,
      ),
    );

    var first = await take(stops);
    var reference = await first.frames.toList();
    var again = await (await take(stops)).frames.toList();
    // Reversed back, so index i of both lists is the same stop.
    var backwards = (await (await take(
      stops.reversed.toList(),
    )).frames.toList()).reversed.toList();

    var repeatFailures = <double>{};
    var orderFailures = <double>{};
    for (var i = 0; i < reference.length; i++) {
      if (!_samePixels(reference[i], again[i])) repeatFailures.add(stops[i]);
      if (!_samePixels(reference[i], backwards[i])) orderFailures.add(stops[i]);
    }

    return MotionVerifyResult(
      motion: motion.values ?? '',
      file: motion.file,
      stops: stops.length,
      durationMs: first.durationMs,
      repeats: repeatFailures.isEmpty,
      orderFree: orderFailures.isEmpty,
      differingStops: {...repeatFailures, ...orderFailures}.toList()..sort(),
      scope: first.scope,
      scopes: first.scopes,
    );
  }

  static bool _samePixels(WalkFrame a, WalkFrame b) {
    if (a.width != b.width || a.height != b.height) return false;
    if (a.pixels.length != b.pixels.length) return false;
    for (var i = 0; i < a.pixels.length; i++) {
      if (a.pixels[i] != b.pixels[i]) return false;
    }
    return true;
  }

  /// What distinguishes one setting's clip from another's, in a filename.
  ///
  /// Renders of the same motion at different knobs are different videos, and
  /// they have to be different files: the whole point of injecting parameters
  /// is having all the clips at once, and a fixed name would leave whichever
  /// finished last. Sorted before hashing so the same setting written in a
  /// different order is the same file rather than a second one.
  ///
  /// A digest rather than the values themselves because a knob's value is
  /// arbitrary text — a sentence, a locale, a JSON object — and none of that
  /// belongs in a path. The values travel in `meta`, where they can be read.
  String _settingSuffix(Map<String, String> knobs, Map<String, String> axes) {
    if (knobs.isEmpty && axes.isEmpty) return '';
    var canonical = [
      for (var key in knobs.keys.toList()..sort()) 'k:$key=${knobs[key]}',
      for (var key in axes.keys.toList()..sort()) 'a:$key=${axes[key]}',
    ].join('\u0000');
    return '-${sha1.convert(utf8.encode(canonical)).toString().substring(0, 8)}';
  }

  /// The cold start, in one call.
  ///
  /// Writes three files, because a motion that renders needs all three: the
  /// stage says what there is, the values file says how it moves, and the
  /// preview entry mounts them. One element is already in them — a "New
  /// motion" that opens on a blank screen has not started anything.
  Future<Artifact> _new(Map<String, Object?> arguments) async {
    var name = _identifier(arguments['name']);
    if (name == null) {
      throw ArgumentError(
        '`name` must be lower snake case — `checkout`, not '
        '`${arguments['name']}`',
      );
    }
    var packagePath = _requestedPackages(arguments['package']).first;
    var directory = Directory(
      p.join(
        host.workspace.packageFor(packagePath).directory.path,
        directoryFor(packagePath),
      ),
    );
    var width = _int(arguments['width']) ?? 360;
    var height = _int(arguments['height']) ?? 640;
    var camel = _camel(name);

    var files = {
      '$name.stage.dart': emitStageFile(
        StageFile(
          name: '${camel}Stage',
          width: width.toDouble(),
          height: height.toDouble(),
          background: null,
          elements: [
            StageElementModel(
              target: 'first',
              x: 24,
              y: 80,
              width: (width - 48).toDouble(),
              height: 48,
            ),
          ],
        ),
        header:
            'The draft scene, owned by the Motion editor.\n\n'
            'Grow it with `fw run motion add-element`. Bind an element to a '
            'real widget when there is one to bind it to; until then the '
            'placeholder is the thing being animated.',
      ),
      '$name.motion.dart': _newValuesFile(camel),
      '$name.dart': _newEntryFile(name, camel),
    };

    var written = <String>[];
    for (var entry in files.entries) {
      var file = File(p.join(directory.path, entry.key));
      if (file.existsSync()) {
        throw StateError(
          '${p.relative(file.path, from: host.worktree.path)} already exists — '
          'pick another name, or delete it first',
        );
      }
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(entry.value);
      written.add(p.relative(file.path, from: host.worktree.path));
    }

    rescan(packagePath);
    track(packagePath);
    await _scans[packagePath];

    return Artifact(
      kind: Artifact.plainText,
      address: addressFor(
        packagePath,
        file: '$name.dart',
        motion: '${camel}Motion',
      ),
      text:
          'Wrote ${written.join(', ')}.\n'
          'One element, `first`. Look at it with '
          '`motion filmstrip --motion=${camel}Motion`, and grow it with '
          '`motion add-element --motion=${camel}Motion --target=…`.',
      meta: {'motion': '${camel}Motion', 'files': written},
    );
  }

  /// One placeholder onto a motion's draft stage.
  ///
  /// The stage is the only place the tool may create a target. The other place
  /// a target is named is your build method, and it does not touch that.
  /// Where a motion keeps its draft stage: the `.stage.dart` beside its entry.
  ///
  /// A convention rather than a declaration, and the same one everywhere — the
  /// action, the panel and `motion new` all derive it here so a motion cannot
  /// have two stages depending on who asked.
  String stagePathFor(String packagePath, String motionFile) => p.join(
    host.workspace.packageFor(packagePath).directory.path,
    motionFile.replaceFirst(RegExp(r'\.dart$'), '.stage.dart'),
  );

  /// The parsed stage, a failure saying why not, or null where there is no
  /// stage file at all — which is the ordinary shape of a motion whose targets
  /// only live in a build method.
  StageParseResult? readStage(String packagePath, String motionFile) {
    var file = File(stagePathFor(packagePath, motionFile));
    if (!file.existsSync()) return null;
    return parseStageFile(file.readAsStringSync());
  }

  /// Writes a stage back whole, and returns what the caller should say about
  /// it. The disk is the model: nothing is pushed into the guest, which picks
  /// the edit up through the ordinary reload.
  void writeStage(String packagePath, String motionFile, StageFile stage) =>
      File(stagePathFor(packagePath, motionFile))
          .writeAsStringSync(emitStageFile(stage));

  /// A target name nothing on [stage] is using, from a kind — `box`, `box2`.
  ///
  /// The panel adds without asking for a name, because a dialog per element is
  /// the wrong price for placing a rectangle; the name is a field on the
  /// element like any other and is changed where the rest of it is.
  static String freeTarget(StageFile stage, String kind) {
    if (!stage.hasTarget(kind)) return kind;
    for (var n = 2; ; n++) {
      if (!stage.hasTarget('$kind$n')) return '$kind$n';
    }
  }

  /// Where an element goes when nobody said: below the lowest one there is, so
  /// a bare add puts something you can see rather than something underneath
  /// the last one.
  static double belowEverything(StageFile stage) =>
      stage.elements.fold<double>(
        40,
        (lowest, each) =>
            each.y + each.height > lowest ? each.y + each.height : lowest,
      ) +
      16;

  Future<Artifact> _addElement(Map<String, Object?> arguments) async {
    var packagePath = _requestedPackages(arguments['package']).first;
    track(packagePath);
    await _scans[packagePath];

    var wanted = arguments['motion'] as String?;
    var motions = _listPackage(packagePath).motions;
    var motion = motions.firstWhereOrNull((each) => each.values == wanted);
    if (motion == null) {
      var known = motions.map((each) => each.values).nonNulls.join(', ');
      throw ArgumentError(
        'no motion named `$wanted` in $packagePath. '
        'Known: ${known.isEmpty ? '(none)' : known}',
      );
    }

    var target = _identifier(arguments['target']);
    if (target == null) {
      throw ArgumentError(
        '`target` must be a plain identifier — `cta`, not '
        '`${arguments['target']}`',
      );
    }

    var stagePath = stagePathFor(packagePath, motion.file);
    var stageFile = File(stagePath);
    var relative = p.relative(stagePath, from: host.worktree.path);
    if (!stageFile.existsSync()) {
      throw StateError(
        '`$wanted` has no draft stage: $relative does not exist. A motion '
        'whose targets only live in a build method has nothing for the tool '
        'to add to.',
      );
    }

    var parsed = parseStageFile(stageFile.readAsStringSync());
    switch (parsed) {
      case StageParseFailure failure:
        // Refuses rather than approximates. Nothing is written.
        throw StateError('$relative cannot be read: $failure');
      case StageFile stage:
        if (stage.hasTarget(target)) {
          throw ArgumentError(
            '`$target` is already on ${stage.name}. A target is named once.',
          );
        }
        var width = _int(arguments['width']) ?? 280;
        var height = _int(arguments['height']) ?? 48;
        var element = StageElementModel(
          target: target,
          kind: switch (arguments['kind']) {
            'text' => 'text',
            'circle' => 'circle',
            _ => 'box',
          },
          x: (_int(arguments['x']) ?? 24).toDouble(),
          y: (_int(arguments['y']) ?? belowEverything(stage)).toDouble(),
          width: width.toDouble(),
          height: height.toDouble(),
          label: arguments['label'] as String?,
        );
        var grown = stage.withElement(element);
        writeStage(packagePath, motion.file, grown);

        return Artifact(
          kind: Artifact.plainText,
          address: addressFor(
            packagePath,
            file: motion.file,
            motion: motion.values,
          ),
          text:
              'Added `$target` to ${stage.name} at '
              '${element.x.toInt()},${element.y.toInt()} '
              '(${element.width.toInt()} by ${element.height.toInt()}). '
              '${grown.elements.length} elements now. It has no lanes yet, so '
              'nothing about it moves until a property is tuned.',
          meta: {
            'motion': motion.values,
            'stage': relative,
            'target': target,
            'elements': grown.elements.length,
          },
        );
    }
  }

  String _newValuesFile(String camel) =>
      """
import 'package:flutter/animation.dart' show Curves;
import 'package:flutterware/motion.dart';

/// Tuned by the Motion editor. A source of truth, not a derivative — do not
/// regenerate, do not delete.
const ${camel}Motion = MotionValues(
  duration: Duration(milliseconds: 600),
  targets: {
    'first': {
      'opacity': [
        Seg<double>(
          start: Duration.zero,
          end: Duration(milliseconds: 320),
          from: 0,
          to: 1,
          curve: Curves.easeOut,
        ),
      ],
      'translateY': [
        Seg<double>(
          start: Duration.zero,
          end: Duration(milliseconds: 420),
          from: 16,
          to: 0,
          curve: Curves.easeOutCubic,
        ),
      ],
    },
  },
);
""";

  String _newEntryFile(String name, String camel) {
    var pascal = camel[0].toUpperCase() + camel.substring(1);
    return """
import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:flutterware/motion.dart';
import 'package:flutterware/previews.dart';

import '$name.motion.dart';
import '$name.stage.dart';

/// Written by `fw run motion new`. Yours from here.
///
/// It has only the draft stage, because there is nothing real to bind to yet.
/// Give the scope a `builder` when there is, and the studio's Draft/Real switch
/// appears on its own — the same motion drives both, so it is a rehearsal of
/// the screen rather than a second drawing of it.
@Preview(name: '$camel', group: 'Motion')
Widget $camel() => const _$pascal();

class _$pascal extends StatefulWidget {
  const _$pascal();

  @override
  State<_$pascal> createState() => _${pascal}State();
}

class _${pascal}State extends State<_$pascal> {
  final _controller = MotionController(autoplay: false);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _controller.progress = context.knobs.double('t', 1, min: 0, max: 1);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _controller.play(restart: true),
      child: Scaffold(
        backgroundColor: const Color(0xFFE9ECF0),
        body: MotionScope(
          motion: ${camel}Motion,
          stage: ${camel}Stage,
          controller: _controller,
          // Your screen goes here. Read the same targets the stage stands in
          // for — `m.target('first')` — and nothing else has to change.
          //
          // builder: (m) => MotionBox(m.target('first'), child: ...),
        ),
      ),
    );
  }
}
""";
  }

  static int? _int(Object? value) => switch (value) {
    int number => number,
    num number => number.round(),
    String text => int.tryParse(text),
    _ => null,
  };

  /// A plain lower-snake identifier, or null.
  ///
  /// Refuses rather than sanitising: a name the tool quietly changed is a name
  /// you cannot find again.
  static String? _identifier(Object? value) =>
      value is String && RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(value)
      ? value
      : null;

  static String _camel(String snake) {
    var parts = snake.split('_');
    return parts.first +
        parts
            .skip(1)
            .map((part) => part[0].toUpperCase() + part.substring(1))
            .join();
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
    // What the harness is generated from — see [_runnerFor].
    _entries[packagePath] = entry;
    return (packagePath, motion, entry, catalog);
  }

  /// The lane a motion is rendered on.
  ///
  /// The harness, and for a clip that is not a preference. A guest advances the
  /// playhead on its UI thread while its host writes whatever the rasteriser
  /// presents, and nothing joins the two — measured over six trials of one
  /// motion it rendered a *different* clip from an identical walk in four of
  /// them, frames offset by a stop. `CatalogRenderer.walk` refuses on that
  /// backend rather than offering a second, wrong implementation.
  ///
  /// The guest stays reachable for a single picture, where it is correct and
  /// is what the lane-parity check compares against.
  CatalogRenderer _rendererFor(String packagePath, {Object? engine}) {
    if (engine != null && engine != 'guest' && engine != 'harness') {
      throw ArgumentError.value(
        engine,
        'engine',
        'no such engine. Accepted: harness, guest',
      );
    }
    if (engine == 'guest') return _headless(packagePath);
    return TesterRenderer(runner: _runnerFor(packagePath));
  }

  /// The harness this plugin renders on, one per declared package.
  ///
  /// Its **own** runner rather than the previews plugin's, and its own build
  /// lane with it: two `TesterHost`s on one directory are two
  /// `frontend_server`s writing one dill, and the plugins sharing this lane
  /// keep out of each other's way by naming their artifacts apart.
  ///
  /// **One entry, not the catalog.** The generated harness imports every entry
  /// it is given, so reading the whole scan makes one clip pay a cold compile
  /// of every demo in the project — minutes, against the seconds the render
  /// takes. A walk renders one demo, so the harness holds one, and exporting
  /// the same demo again reuses its dill.
  PreviewTestRunner _runnerFor(String packagePath) => _runners.putIfAbsent(
    packagePath,
    () => PreviewTestRunner(
      packageRoot: p.join(host.worktree.path, packagePath),
      flutterSdkRoot: host.workspace.flutterSdk.root,
      read: () => (entries: [?_entries[packagePath]], canvases: const []),
      // The *preferred* lane, not a private claim: `takeBuildLane` hands it to
      // whoever locks it first and gives everybody else one of their own, so a
      // warm dill survives from one export to the next.
      buildDirectory: motionBuildRoot,
    ),
  );

  final _runners = <String, PreviewTestRunner>{};

  /// The entry the last resolve landed on, per package — what [_runnerFor]'s
  /// harness is generated from.
  final _entries = <String, CatalogEntry>{};

  /// Ends the harnesses this plugin started.
  ///
  /// **A `flutter_tester` is a child process, and an undisposed runner keeps
  /// one alive.** What that looks like is not a crash: the render finishes, the
  /// clip is written, and then `fw` simply never exits — which reads as a hang
  /// in the render and sent me looking there for an afternoon.
  @override
  void dispose() {
    for (var runner in _runners.values) {
      unawaited(runner.dispose());
    }
    _runners.clear();
    super.dispose();
  }

  HeadlessCatalog _headless(String packagePath) => HeadlessCatalog(
    dartExecutable: p.join(host.workspace.flutterSdk.root, 'bin', 'dart'),
    config: DaemonConfig.forPackage(
      appToolDirectory: host.workspace.appContext.appToolDirectory.path,
      packageRoot: host.workspace.packageFor(packagePath).directory.path,
      flutterSdkRoot: host.workspace.flutterSdk.root,
      // The catalog's roots, not this plugin's scan directory. A motion is
      // *rendered* through the previews catalog, and asking for a narrower
      // root does not narrow the catalog — it forks the compiler.
      roots: host.catalogRootsFor(packagePath),
      clock: host.projectClock,
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
      // A section rather than a heading line and its siblings: a package's
      // name is a section title everywhere else, and a text projection folds
      // one into the child that already names the package rather than
      // printing the package twice.
      for (var path in packages)
        ViewSection(path, [
          if (_errors[path] case var error?)
            ViewText('$error', tone: Tone.error)
          else if (_results[path] case var result?) ...[
            // Items rather than text, because a row that says where it is can
            // be searched and a line of prose cannot — `searchReport` walks
            // `ViewItem` and skips `ViewText`. The address is the one the
            // `list` action already hands out, under the same rule: a motion
            // whose values file is an anonymous expression names no place, so
            // it carries no address rather than a guessed one.
            ViewItems([
              for (var motion in result.motions)
                ViewItem(
                  motion.values ?? '<expression>',
                  detail:
                      '${motion.file}:${motion.line}, '
                      '${motion.targets.length} target'
                      '${motion.targets.length == 1 ? '' : 's'}',
                  address: motion.values == null
                      ? null
                      : addressFor(
                          path,
                          file: motion.file,
                          motion: motion.values,
                        ),
                ),
            ]),
            if (result.motions.isEmpty) const ViewText('No motions found.'),
            for (var diagnostic in result.diagnostics)
              ViewText(diagnostic, tone: Tone.warn),
          ] else
            const ViewText('Not scanned yet.', tone: Tone.neutral),
        ]),
    ]);
  }
}

PluginCore motionCoreFactory(PluginHost host) => MotionCore(host);
