import 'package:flutterware/plugins.dart';
import 'package:path/path.dart' as p;

import '../../scene/discovery.dart';
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
  void rescan(String package) => _cache.invalidate(package);

  /// Discovery is a directory walk and a first line, so every surface that
  /// asks for status can afford it — which is what keeps `fw` and MCP from
  /// reporting "not computed" for a project that plainly has scenes.
  @override
  Future<void> computeAll() async {
    await Future.wait([for (var package in packages) _cache.load(package)]);
  }

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
    view: _view,
  );

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
