import 'dart:convert';
import 'dart:io';

import 'package:flutterware/plugins.dart';
import 'package:flutterware/scene_authoring.dart';
import 'package:path/path.dart' as p;

import '../../embedder/build_directory.dart';
import '../../previews/catalog_entry.dart';
import '../../previews/catalog_render.dart';
import '../../previews/devices.dart';
import '../../previews/discovery.dart';
import '../../previews/test_runner.dart';
import '../../previews/tester_renderer.dart';
import '../../scene/discovery.dart';
import '../../scene/export/video.dart';
import '../../scene/scene_file.dart';
import '../../utils/string/plural.dart';
import '../plugin_core.dart';
import '../plugin_host.dart';
import '../scan_cache.dart';

/// The registered id — also what `tool/flutterware.dart` declares.
const scenePluginId = 'flutterware.scene';

/// Where a package's scene files live when it declares no directory.
const defaultSceneDirectory = 'lib';

const _pluginDescription =
    'Scenes this project owns — a design and the motion animating it, in one '
    'tool-written file per scene, rendered by the app itself.';

/// Scenes listed by name before the rest become a count.
const _projectedScenes = 12;

/// What scene files a project has, and where.
///
/// Discovery is a directory walk and a first line: a scene file declares
/// itself with its marker, so nothing here compiles, analyses or boots.
/// Opening one — parsing it in full, refusing it with line numbers — is the
/// panel's job, over the same door `fw` would use.
class SceneCore extends PluginCore {
  SceneCore(super.host);

  List<String> get packages => host.packagePaths;

  /// Where this package's scenes are, per `tool/flutterware.dart`.
  String directoryFor(String path) {
    for (var config in host.packageConfigs) {
      if (config['path'] == path) {
        if (config['directory'] case String directory) return directory;
      }
    }
    return defaultSceneDirectory;
  }

  /// The absolute directory scanned for [package].
  String rootFor(String package) => p.join(
    host.workspace.packageFor(package).directory.path,
    directoryFor(package),
  );

  late final _cache = ScanCache<String, List<SceneEntry>>(
    scan: (package) async => discoverScenes(rootFor(package)),
    onChanged: notifyChanged,
  );

  /// The scenes of [package], or null when nothing has looked yet.
  List<SceneEntry>? scenesFor(String package) => _cache[package];

  bool isScanning(String package) => _cache.isScanning(package);

  String? failureFor(String package) => _cache.failureFor(package);

  /// Start (or reuse) the scan for [package] — what mounting the panel does.
  void track(String package) => _cache.track(package);

  /// Forget what was found, so the next look walks the directory again.
  ///
  /// Only forgets: something has to ask again afterwards, or a surface that
  /// reads the listing sits on its loading state forever. [reload] is the one
  /// to call when nobody else will ask.
  void rescan(String package) => _cache.invalidate(package);

  /// Walks the directory again now — what a file appearing on disk needs.
  Future<void> reload(String package) => _cache.reload(package);

  /// Discovery is a directory walk and a first line, so every surface that
  /// asks for status can afford it — which is what keeps `fw` and MCP from
  /// reporting "not computed" for a project that plainly has scenes.
  @override
  Future<void> computeAll() async {
    await Future.wait([for (var package in packages) _cache.load(package)]);
  }

  /// The preview entry that plays a scene from a file — the registration a
  /// project declares so its scenes can be exported with its own widgets and
  /// its own theme.
  static const playerEntrySymbol = 'scenePlayer';

  /// Renders a clip of [scene]'s motion.
  ///
  /// The harness lane, not the guest: a clip's frames must each be *of* the
  /// moment they claim, and only the tester can promise that — it parks the
  /// playhead and rasterises the tree that pump produced. The scene travels
  /// as a file because a walk asks for it once and a scene is kilobytes.
  Future<Artifact> exportVideo({
    required String package,
    required String scenePath,
    int fps = 30,
  }) async {
    var opened = parseSceneFile(File(scenePath).readAsStringSync());
    if (!opened.ok) {
      throw StateError(
        'that scene does not parse, so there is nothing to render:\n'
        '${opened.refusals.take(3).join('\n')}',
      );
    }
    if (opened.motions.isEmpty) {
      throw StateError(
        '${p.basename(scenePath)} has no motion — a clip of a still scene '
        'would be one frame repeated',
      );
    }
    var entry = _playerEntry(package);
    var pair =
        File(
          p.join(
            Directory.systemTemp.createTempSync('fw-scene').path,
            'pair.json',
          ),
        )..writeAsStringSync(
          jsonEncode(
            sceneFileToJson(
              opened.doc!,
              className: opened.className!,
              motions: opened.motions,
            ),
          ),
        );

    var output = p.join(
      host.workspace.appContext.appToolDirectory.path,
      'build',
      'scene',
      '${opened.className}.mp4',
    );
    // The whole motion at `fps`: only the running motion knows how long it
    // is, so the stops are not computed here.
    // The artboard's own size, not the panel's: a clip of a scene is the
    // scene, and rendering it in a viewport of another shape crops one edge
    // and letterboxes the other.
    var root = opened.doc!.root;
    var walk = await TesterRenderer(runner: _runnerFor(package, entry)).walk(
      CatalogWalk(
        entryId: entry.id,
        fps: fps,
        viewport: CaptureViewport(
          width: (root.width ?? 1024).round(),
          height: (root.height ?? 500).round(),
        ),
        knobs: {'pair': pair.path},
      ),
    );
    var video = await encodeWalk(walk, output: output, fps: fps);
    pair.parent.deleteSync(recursive: true);

    return Artifact(
      kind: Artifact.mp4,
      address: Address(
        worktree: host.worktree.name,
        plugin: host.id,
        segments: [package, p.basename(scenePath)],
      ),
      path: p.relative(video.file.path, from: host.worktree.path),
      meta: {
        'scene': opened.className,
        'size': [root.width, root.height],
        'motion': opened.motions.keys.first,
        'file': p.relative(scenePath, from: host.worktree.path),
        'fps': video.fps,
        'frames': video.frames,
        'durationMs': video.durationMs,
        'renderMs': video.renderTime.inMilliseconds,
        'encodeMs': video.encodeTime.inMilliseconds,
        'bytes': video.file.lengthSync(),
      },
    );
  }

  /// The project's scene-player entry, or a refusal naming what to declare.
  ///
  /// Scanned rather than asked of the previews plugin: an export must work
  /// whether or not that panel has ever been opened.
  CatalogEntry _playerEntry(String package) {
    var scan = CatalogScanner(projectRoot: p.join(host.worktree.path, package))
        .scan();
    for (var entry in scan.entries) {
      if (entry.symbol == playerEntrySymbol) return entry;
    }
    throw StateError(
      'this project declares no scene player, so a scene cannot be rendered '
      'with its widgets. Add a @Preview entry named `$playerEntrySymbol` '
      'taking a `pair` knob — see the example project.',
    );
  }

  /// The harness this plugin renders on, one per declared package — its own
  /// lane, because two hosts on one build directory are two
  /// `frontend_server`s writing one dill.
  PreviewTestRunner _runnerFor(String package, CatalogEntry entry) =>
      _runners.putIfAbsent(
        package,
        () => PreviewTestRunner(
          packageRoot: p.join(host.worktree.path, package),
          flutterSdkRoot: host.workspace.flutterSdk.root,
          // One entry, not the catalog: the generated harness imports every
          // entry it is given, so a clip would otherwise pay a cold compile
          // of every demo in the project.
          read: () => (entries: [entry], canvases: const []),
          buildDirectory: sceneBuildRoot,
        ),
      );

  final _runners = <String, PreviewTestRunner>{};

  @override
  PluginReport get report => PluginReport(
    id: host.id,
    label: host.label,
    description: _pluginDescription,
    status: _status,
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

  List<PluginAction> get _actions => [
    PluginAction(
      'list',
      'List',
      description:
          'The scenes this project has, with the class each declares and the '
          'motions beside it.',
      parameters: [_packageParameter],
    ),
    PluginAction(
      'video',
      'Video',
      description:
          "Renders a scene's motion to an mp4, drawn by the app itself — "
          'its theme, its widgets — one frame per moment on the harness '
          'lane, where a frame cannot be of a moment other than the one it '
          'was drawn for. Needs ffmpeg.',
      parameters: [
        _packageParameter,
        ActionParameter(
          'scene',
          'Scene',
          description: 'The scene file, by name or path.',
          required: true,
        ),
        ActionParameter('fps', 'Frames a second', description: 'Default 30.'),
      ],
    ),
  ];

  ActionParameter get _packageParameter => ActionParameter(
    'package',
    'Package',
    required: false,
    description: 'Which declared package; the first when omitted.',
    options: [for (var path in packages) ActionOption(path)],
  );

  @override
  Future<Object?> invoke(
    String actionId, {
    Map<String, Object?> arguments = const {},
  }) async {
    var package = switch (arguments['package']) {
      String named when packages.contains(named) => named,
      String named => throw ArgumentError.value(
        named,
        'package',
        'no such declared package. Declared: ${packages.join(', ')}',
      ),
      _ => packages.firstOrNull,
    };
    if (package == null) {
      throw StateError('this plugin is declared for no package');
    }
    switch (actionId) {
      case 'list':
        await _cache.load(package);
        return {
          'package': package,
          'scenes': [
            for (var scene in scenesFor(package) ?? const <SceneEntry>[])
              {
                'class': scene.className,
                'path': p.relative(scene.path, from: host.worktree.path),
              },
          ],
        };
      case 'video':
        return exportVideo(
          package: package,
          scenePath: _resolveScene(package, arguments['scene']),
          fps: switch (arguments['fps']) {
            int value => value,
            String text when int.tryParse(text) != null => int.parse(text),
            _ => 30,
          }.clamp(1, 120),
        );
      default:
        return super.invoke(actionId, arguments: arguments);
    }
  }

  /// A scene named by class, file name or path — refused by listing what
  /// this package actually has, which is the only useful answer to a typo.
  String _resolveScene(String package, Object? wanted) {
    var scenes = scenesFor(package) ?? discoverScenes(rootFor(package));
    if (wanted is String) {
      for (var scene in scenes) {
        if (scene.className == wanted ||
            scene.fileName == wanted ||
            scene.path == wanted ||
            p.relative(scene.path, from: host.worktree.path) == wanted) {
          return scene.path;
        }
      }
    }
    throw ArgumentError.value(
      wanted,
      'scene',
      scenes.isEmpty
          ? 'this package has no scenes'
          : 'no such scene. Found: ${scenes.map((s) => s.className).join(', ')}',
    );
  }

  Status get _status {
    var scanned = packages.where((p) => scenesFor(p) != null).toList();
    if (scanned.isEmpty) {
      return const Status.neutral('not computed');
    }
    var total = scanned.fold(0, (n, p) => n + scenesFor(p)!.length);
    return Status.neutral(total == 0 ? 'no scenes' : plural(total, 'scene'));
  }

  StatusBadge get _badge {
    var total = 0;
    for (var package in packages) {
      total += scenesFor(package)?.length ?? 0;
    }
    return total == 0 ? StatusBadge.none : StatusBadge.count(total);
  }

  Status _childStatus(String package) {
    if (failureFor(package) case var failure?) return Status.error(failure);
    var scenes = scenesFor(package);
    if (scenes == null) {
      return Status.neutral(isScanning(package) ? 'scanning…' : 'not computed');
    }
    return Status.neutral(
      scenes.isEmpty
          ? 'no scenes in ${directoryFor(package)}/'
          : plural(scenes.length, 'scene'),
    );
  }

  /// The inventory: every scene found, by package, with the class it
  /// declares — the same listing the panel draws, so `fw` and an agent read
  /// what the human reads.
  PluginView get _view {
    var sections = <ViewNode>[];
    for (var package in packages) {
      var scenes = scenesFor(package);
      if (scenes == null) continue;
      sections.add(
        ViewSection(package == '.' ? 'root' : package, [
          ViewItems([
            for (var scene in scenes.take(_projectedScenes))
              ViewItem(
                scene.className,
                detail: p.relative(scene.path, from: host.worktree.path),
              ),
          ], truncated: (scenes.length - _projectedScenes).clamp(0, 1 << 30)),
        ]),
      );
    }
    return PluginView(sections);
  }
}

PluginCore sceneCoreFactory(PluginHost host) => SceneCore(host);
