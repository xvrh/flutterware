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
import '../../scene/args_codegen.dart';
import '../../scene/args_generate.dart';
import '../../scene/discovery.dart';
import '../../scene/export/video.dart';
import '../../scene/group_file.dart';
import '../../scene/skeletons.dart';
import '../../scene/import/variables.dart';
import '../../scene/scene_file.dart';
import '../../scene/tokens_file.dart';
import '../../scene/workspace.dart';
import '../../utils/string/plural.dart';
import '../plugin_core.dart';
import '../plugin_host.dart';
import '../scan_cache.dart';

/// The registered id — also what `tool/flutterware.dart` declares.
const scenePluginId = 'flutterware.scene';

/// What a package's scan covers when it declares no directory: the whole
/// package. A group is a folder with a `scenes.dart` in it, wherever that
/// folder is.
const defaultSceneDirectory = '.';

const _pluginDescription =
    'Scenes this project owns — a design and the motion animating it, in one '
    'tool-written file per scene, grouped by folder and rendered by the app '
    'itself.';

/// Scenes listed by name before the rest become a count.
const _projectedScenes = 12;

/// One property of one scene reading a token — what a delete names and a
/// rename follows.
class SceneTokenReader {
  SceneTokenReader(this.scenePath, this.sceneClass, this.node, this.prop);

  final String scenePath;
  final String sceneClass;
  final String node;
  final String prop;

  @override
  String toString() => '$sceneClass · $node.$prop';
}

/// What scene groups, scenes and token libraries a project has, and where.
///
/// Discovery is a directory walk and a first line: a group's `scenes.dart`,
/// a scene file and a library file each declare themselves with a marker,
/// so nothing here compiles, analyses or boots. Opening a scene — parsing
/// it in full, refusing it with line numbers — is the panel's job, over the
/// same door `fw` would use.
class SceneCore extends PluginCore {
  SceneCore(super.host);

  List<String> get packages => host.packagePaths;

  /// Where this package is scanned, per `tool/flutterware.dart` — the whole
  /// package unless it narrows the scope.
  String directoryFor(String path) {
    for (var config in host.packageConfigs) {
      if (config['path'] == path) {
        if (config['directory'] case String directory) return directory;
      }
    }
    return defaultSceneDirectory;
  }

  /// The package's own root — what a catalog entry's path is relative to.
  String projectRootFor(String package) =>
      host.workspace.packageFor(package).directory.path;

  /// The absolute directory scanned for [package].
  String rootFor(String package) =>
      p.normalize(p.join(projectRootFor(package), directoryFor(package)));

  late final _cache = ScanCache<String, ScenePackageScan>(
    scan: (package) async {
      // Declarations first, then the vocabulary they generate, then the
      // scene files that spell it. A scene file names `DrinkBadgeArgs`,
      // whose class is written from the group's declaration of that widget
      // — so a scan that listed scenes without regenerating would hand the
      // panel files naming classes that no longer exist.
      var scan = discoverPackage(rootFor(package));
      _argsFor[package] = generateSceneArgsIn(rootFor(package), scan: scan);
      return scan;
    },
    onChanged: notifyChanged,
  );

  final _argsFor = <String, Map<String, SceneArgsResult>>{};

  /// What the last generation run for [group] had to say — the refusals its
  /// declaration or a library earned, and whether the vocabulary was
  /// rewritten. Null before the first scan.
  SceneArgsResult? argsResultFor(String package, SceneGroupEntry group) =>
      _argsFor[package]?[group.directory];

  /// What [group] declares: its widgets, its exports, its libraries. Read
  /// at the last scan, or now when nothing has scanned yet; empty when the
  /// declaration is refused, in which case [argsResultFor] says why.
  GroupVocabulary vocabularyFor(String package, SceneGroupEntry group) {
    if (argsResultFor(package, group) case var result?) {
      return result.vocabulary;
    }
    var scan = scanFor(package) ?? discoverPackage(rootFor(package));
    return readGroup(group, scan).vocabulary ?? GroupVocabulary.empty;
  }

  /// Everything found under [package], or null when nothing has looked yet.
  ScenePackageScan? scanFor(String package) => _cache[package];

  /// The scenes of [package] across its groups, or null when nothing has
  /// looked yet.
  List<SceneEntry>? scenesFor(String package) => scanFor(package)?.scenes;

  /// The group a scene file belongs to.
  SceneGroupEntry? groupFor(String package, String scenePath) =>
      (scanFor(package) ?? discoverPackage(rootFor(package))).groupOf(
        scenePath,
      );

  /// A group's folder as the catalog names it: relative to the package.
  String groupPathFor(String package, SceneGroupEntry group) =>
      p.relative(group.directory, from: projectRootFor(package));

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

  // --- Writing the folders -------------------------------------------------

  /// A new group: the folder, and the declaration skeleton in it. The
  /// folder is relative to the package. Refused, by message, when the
  /// folder already declares a group.
  Future<String> createGroup(String package, String folder) async {
    var directory = p.normalize(p.join(projectRootFor(package), folder));
    var declaration = File(p.join(directory, sceneGroupFileName));
    if (declaration.existsSync()) {
      throw StateError(
        '${p.relative(declaration.path, from: host.worktree.path)} '
        'already exists — that folder is a group',
      );
    }
    if (!p.isWithin(rootFor(package), directory) &&
        p.canonicalize(rootFor(package)) != p.canonicalize(directory)) {
      throw StateError(
        '$folder is outside the scanned scope '
        '(${directoryFor(package)}/) and would not be found',
      );
    }
    Directory(directory).createSync(recursive: true);
    declaration.writeAsStringSync(emitGroupSkeleton());
    await reload(package);
    return declaration.path;
  }

  /// A new library: `<name>.tokens.dart` in [folder], empty, the editor's
  /// own; attached to [attachTo] when given.
  Future<String> createLibrary(
    String package,
    String folder,
    String name, {
    SceneGroupEntry? attachTo,
  }) async {
    var directory = p.normalize(p.join(projectRootFor(package), folder));
    var file = File(p.join(directory, tokensFileNameFor(name)));
    if (file.existsSync()) {
      throw StateError(
        '${p.relative(file.path, from: host.worktree.path)} already exists',
      );
    }
    Directory(directory).createSync(recursive: true);
    file.writeAsStringSync(emitTokensSkeleton(tokensSymbolFor(file.path)));
    if (attachTo != null) {
      _attach(attachTo, file.path);
    }
    await reload(package);
    return file.path;
  }

  /// Lists [libraryPath] in [group]'s declaration and imports it there —
  /// the one edit the tool makes to a hand-written file.
  Future<void> attachLibrary(
    String package,
    SceneGroupEntry group,
    String libraryPath,
  ) async {
    _attach(group, libraryPath);
    await reload(package);
  }

  Future<void> detachLibrary(
    String package,
    SceneGroupEntry group,
    String libraryPath,
  ) async {
    var declaration = File(group.declarationPath);
    var edited = detachLibraryIn(
      declaration.readAsStringSync(),
      group.declarationPath,
      libraryPath,
      refuse: (reason) => throw StateError(reason),
    );
    if (edited != null) declaration.writeAsStringSync(edited);
    await reload(package);
  }

  void _attach(SceneGroupEntry group, String libraryPath) {
    var declaration = File(group.declarationPath);
    var edited = attachLibraryIn(
      declaration.readAsStringSync(),
      group.declarationPath,
      libraryPath,
      refuse: (reason) => throw StateError(reason),
    );
    if (edited != null) declaration.writeAsStringSync(edited);
  }

  // --- Tokens across the group ---------------------------------------------

  /// The groups listing the library at [libraryPath].
  List<SceneGroupEntry> groupsListing(String package, String libraryPath) {
    var scan = scanFor(package) ?? discoverPackage(rootFor(package));
    var wanted = p.canonicalize(libraryPath);
    return [
      for (var group in scan.groups)
        if (vocabularyFor(
          package,
          group,
        ).libraries.any((l) => p.canonicalize(l.entry.path) == wanted))
          group,
    ];
  }

  /// Every property reading [token] in every scene of every group listing
  /// [libraryPath], except the scene files in [except] — the open ones,
  /// whose editors know their own readers. Parsed fresh from disk, so a
  /// rename or a delete is judged against what the files say now.
  List<SceneTokenReader> tokenReaders(
    String package,
    String libraryPath,
    String token, {
    Set<String> except = const {},
  }) {
    var skip = {for (var e in except) p.canonicalize(e)};
    var readers = <SceneTokenReader>[];
    for (var group in groupsListing(package, libraryPath)) {
      var tokens = vocabularyFor(package, group).tokens;
      for (var scene in group.scenes) {
        if (skip.contains(p.canonicalize(scene.path))) continue;
        var parsed = parseSceneFile(
          File(scene.path).readAsStringSync(),
          tokens: tokens,
        );
        var doc = parsed.doc;
        if (doc == null) continue;
        for (var (node, _) in doc.walk()) {
          for (var e in node.bindings.entries) {
            var name = switch (e.value) {
              TokenRef(:var name) || StyleRef(:var name) => name,
              _ => null,
            };
            if (name == token) {
              readers.add(
                SceneTokenReader(scene.path, scene.className, node.name, e.key),
              );
            }
          }
        }
      }
    }
    return readers;
  }

  /// Rewrites every closed scene file reading [from] so it reads [to] —
  /// the half of a rename the open editors cannot do. [vocabulary] is the
  /// group's tokens as they will be once the library is written, so the
  /// rewritten file parses against them. Returns the files touched.
  List<String> renameTokenInFiles(
    String package,
    String libraryPath,
    String from,
    String to, {
    Set<String> except = const {},
  }) {
    var touched = <String>[];
    var skip = {for (var e in except) p.canonicalize(e)};
    for (var group in groupsListing(package, libraryPath)) {
      var before = vocabularyFor(package, group).tokens;
      var after = [
        for (var t in before)
          if (t.name == from) _renamedDecl(t, to) else t,
      ];
      for (var scene in group.scenes) {
        if (skip.contains(p.canonicalize(scene.path))) continue;
        var source = File(scene.path).readAsStringSync();
        var opened = SceneFile.open(
          scene.path,
          source,
          declaredArgs: vocabularyFor(package, group).declaredArgs,
          tokens: before,
        );
        var file = opened.file;
        if (file == null) continue;
        if (file.editor.readersOfToken(from).isEmpty) continue;
        file.editor.renameTokenRefs(from, to);
        file.editor.retokenize(after);
        var refusals = file.save(
          (path, text) => File(path).writeAsStringSync(text),
        );
        if (refusals.isEmpty) touched.add(scene.path);
      }
    }
    return touched;
  }

  static SceneTokenDecl _renamedDecl(SceneTokenDecl t, String name) =>
      t.style != null
      ? SceneTokenDecl.style(name, t.style!)
      : t.isExport
      ? SceneTokenDecl.export(name, t.type)
      : SceneTokenDecl(name, t.kind!, t.value!, modes: t.modes);

  // --- Rendering -----------------------------------------------------------

  /// The preview entry that plays a scene from a file — generated beside
  /// every group's declaration, so a scene is exported with its own
  /// widgets and its own wrapper.
  static const playerEntrySymbol = scenePlayerSymbol;

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
    var group = groupFor(package, scenePath);
    if (group == null) {
      throw StateError(
        '${p.basename(scenePath)} is in no group — a scene is rendered by '
        "its group's own entry, and no folder above it has a "
        '$sceneGroupFileName',
      );
    }
    var opened = parseSceneFile(
      File(scenePath).readAsStringSync(),
      tokens: vocabularyFor(package, group).tokens,
    );
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
    var entry = _playerEntry(package, group);
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
        'group': group.name,
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

  /// The group's scene-player entry, or a refusal naming what is missing.
  ///
  /// Scanned rather than asked of the previews plugin: an export must work
  /// whether or not that panel has ever been opened.
  CatalogEntry _playerEntry(String package, SceneGroupEntry group) {
    var scan = CatalogScanner(projectRoot: projectRootFor(package)).scan();
    var folder = groupPathFor(package, group);
    for (var entry in scan.entries) {
      if (entry.symbol == playerEntrySymbol &&
          isGroupHostEntry(entry.path, folder)) {
        return entry;
      }
    }
    throw StateError(
      'no scene player in $folder/ — the generated $sceneArgsFileName '
      'declares it; rescan the group',
    );
  }

  /// The harness this plugin renders on, one per declared package — its own
  /// lane, because two hosts on one build directory are two
  /// `frontend_server`s writing one dill.
  PreviewTestRunner _runnerFor(String package, CatalogEntry entry) =>
      _runners.putIfAbsent(
        package,
        () => PreviewTestRunner(
          packageRoot: projectRootFor(package),
          flutterSdkRoot: host.workspace.flutterSdk.root,
          // One entry, not the catalog: the generated harness imports every
          // entry it is given, so a clip would otherwise pay a cold compile
          // of every demo in the project.
          read: () => (entries: [entry], canvases: const []),
          buildDirectory: sceneBuildRoot,
        ),
      );

  final _runners = <String, PreviewTestRunner>{};

  // --- Report --------------------------------------------------------------

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
          'The scene groups this project has — each a folder with a '
          '$sceneGroupFileName — with the scenes in each, and the token '
          'libraries found.',
      parameters: [_packageParameter],
    ),
    PluginAction(
      'video',
      'Video',
      description:
          "Renders a scene's motion to an mp4, drawn by the app itself — "
          "its theme, its group's widgets — one frame per moment on the "
          'harness lane, where a frame cannot be of a moment other than '
          'the one it was drawn for. Needs ffmpeg.',
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
    PluginAction(
      'newGroup',
      'New group',
      description:
          'Makes a folder a scene group: writes its $sceneGroupFileName '
          'skeleton, which the next scan finds. The generated '
          '$sceneArgsFileName follows.',
      parameters: [
        _packageParameter,
        ActionParameter(
          'folder',
          'Folder',
          description: 'Relative to the package — lib/scenes/marketing.',
          required: true,
        ),
      ],
    ),
    PluginAction(
      'newLibrary',
      'New library',
      description:
          'Writes an empty token library — <name>$sceneTokensFileSuffix, '
          "the editor's own — and lists it in a group when one is named.",
      parameters: [
        _packageParameter,
        ActionParameter(
          'name',
          'Name',
          description: 'The library — Brand, store front.',
          required: true,
        ),
        ActionParameter(
          'folder',
          'Folder',
          description:
              "Relative to the package; the group's own folder when a group "
              'is named, lib/ otherwise.',
          required: false,
        ),
        ActionParameter(
          'group',
          'Attach to group',
          description: 'A group folder, relative to the package.',
          required: false,
        ),
      ],
    ),
    PluginAction(
      'importTokens',
      'Import tokens',
      description:
          "Writes a token library from a design file's variables — the "
          'JSON its REST API answers for local variables, saved to a file. '
          'Every variable becomes a Token with its modes; what cannot be one '
          'is refused by name. Replaces a library a previous import wrote; '
          'one the editor or a hand wrote is kept unless force is set.',
      parameters: [
        _packageParameter,
        ActionParameter(
          'file',
          'Variables JSON',
          description: 'The saved response, by path.',
          required: true,
        ),
        ActionParameter(
          'library',
          'Library',
          description:
              'The library file to write, relative to the package — '
              'lib/design/brand$sceneTokensFileSuffix. Default: '
              "imported$sceneTokensFileSuffix in the first group's folder.",
          required: false,
        ),
        ActionParameter(
          'force',
          'Replace a file not written by an import',
          kind: ActionParameterKind.boolean,
          required: false,
          description: 'Default false.',
        ),
      ],
    ),
  ];

  /// The import door: read, refuse, write, and rescan so the generated
  /// vocabulary follows. Returns what was written and what was not.
  Future<Map<String, Object?>> importTokens({
    required String package,
    required String jsonPath,
    String? library,
    bool force = false,
  }) async {
    var file = File(jsonPath);
    if (!file.existsSync()) {
      throw ArgumentError.value(jsonPath, 'file', 'no such file');
    }
    var imported = importVariables(file.readAsStringSync());
    if (imported.tokens.isEmpty) {
      throw ArgumentError.value(
        jsonPath,
        'file',
        'nothing to import: ${imported.refusals.join('; ')}',
      );
    }
    File target;
    if (library != null && library.isNotEmpty) {
      var path = p.isAbsolute(library)
          ? library
          : p.join(projectRootFor(package), library);
      if (!path.endsWith(sceneTokensFileSuffix)) {
        throw ArgumentError.value(
          library,
          'library',
          'a library file ends in $sceneTokensFileSuffix',
        );
      }
      target = File(p.normalize(path));
    } else {
      var scan = scanFor(package) ?? discoverPackage(rootFor(package));
      var folder = scan.groups.firstOrNull?.directory ?? rootFor(package);
      target = File(p.join(folder, 'imported$sceneTokensFileSuffix'));
    }
    if (target.existsSync() &&
        !force &&
        !isImportedTokensFile(target.readAsStringSync())) {
      throw StateError(
        '${p.relative(target.path, from: host.worktree.path)} was not written '
        'by an import — pass force to replace it',
      );
    }
    var symbol = tokensSymbolFor(target.path);
    var source = emitImportedTokens(
      imported,
      from: p.basename(jsonPath),
      symbol: symbol,
    );
    // The file the tool writes has to be one the tool reads: the parser is
    // the grader, before anything lands on disk.
    var check = parseTokensFile(source, symbol: symbol);
    if (!check.ok) {
      throw StateError(
        'the import produced a file its own reader refuses: '
        '${check.refusals.join('; ')}',
      );
    }
    target.parent.createSync(recursive: true);
    target.writeAsStringSync(source);
    await reload(package);
    // A library nobody lists is a library nobody reads. When it landed in a
    // group's own folder and that group does not list it yet, list it —
    // the one edit the tool makes to a hand-written file, and the one that
    // makes an import usable in one step.
    var listed = false;
    for (var group in scanFor(package)?.groups ?? const <SceneGroupEntry>[]) {
      if (vocabularyFor(package, group).libraries.any(
        (l) => p.canonicalize(l.entry.path) == p.canonicalize(target.path),
      )) {
        listed = true;
      }
    }
    if (!listed) {
      var owner = (scanFor(package)?.groups ?? const <SceneGroupEntry>[])
          .where((g) => p.isWithin(g.directory, target.path))
          .firstOrNull;
      if (owner != null) {
        _attach(owner, target.path);
        await reload(package);
      }
    }
    return {
      'path': p.relative(target.path, from: host.worktree.path),
      'symbol': symbol,
      'tokens': [
        for (var t in imported.tokens)
          {'name': t.name, 'type': t.decl.typeName, 'from': t.source},
      ],
      'modes': imported.modeNames,
      'refusals': [for (var r in imported.refusals) '$r'],
      'listedBy': [
        for (var group
            in (scanFor(package)?.groups ?? const <SceneGroupEntry>[]))
          if (vocabularyFor(package, group).libraries.any(
            (l) => p.canonicalize(l.entry.path) == p.canonicalize(target.path),
          ))
            groupPathFor(package, group),
      ],
    };
  }

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
        var scan = scanFor(package)!;
        return {
          'package': package,
          'scope': directoryFor(package),
          'groups': [
            for (var group in scan.groups)
              {
                'name': group.name,
                'folder': groupPathFor(package, group),
                'libraries': [
                  for (var l in vocabularyFor(package, group).libraries)
                    p.relative(l.entry.path, from: host.worktree.path),
                ],
                'widgets': [
                  for (var w in vocabularyFor(package, group).widgets) w.entry,
                ],
                'exports': [
                  for (var t in vocabularyFor(package, group).exports) t.name,
                ],
                'refusals': [
                  for (var r
                      in argsResultFor(package, group)?.refusals ??
                          const <SceneRefusal>[])
                    '$r',
                ],
                'scenes': [
                  for (var scene in group.scenes)
                    {
                      'class': scene.className,
                      'path': p.relative(scene.path, from: host.worktree.path),
                    },
                ],
              },
          ],
          'libraries': [
            for (var library in scan.libraries)
              {
                'symbol': library.symbol,
                'path': p.relative(library.path, from: host.worktree.path),
              },
          ],
          'strayScenes': scan.strayScenes,
        };
      case 'newGroup':
        var folder = _text(arguments['folder'], 'folder', 'a folder path');
        var path = await createGroup(package, folder);
        return {'path': p.relative(path, from: host.worktree.path)};
      case 'newLibrary':
        var name = _text(arguments['name'], 'name', 'a library name');
        var scan = scanFor(package) ?? discoverPackage(rootFor(package));
        SceneGroupEntry? group;
        if (arguments['group'] case String folder when folder.isNotEmpty) {
          var wanted = p.normalize(p.join(projectRootFor(package), folder));
          group = scan.groups
              .where(
                (g) => p.canonicalize(g.directory) == p.canonicalize(wanted),
              )
              .firstOrNull;
          if (group == null) {
            throw ArgumentError.value(
              folder,
              'group',
              scan.groups.isEmpty
                  ? 'this package has no groups'
                  : 'no such group. Found: '
                        '${scan.groups.map((g) => groupPathFor(package, g)).join(', ')}',
            );
          }
        }
        var folder = switch (arguments['folder']) {
          String f when f.isNotEmpty => f,
          _ => group == null ? 'lib' : groupPathFor(package, group),
        };
        var path = await createLibrary(package, folder, name, attachTo: group);
        return {
          'path': p.relative(path, from: host.worktree.path),
          'symbol': tokensSymbolFor(path),
          if (group != null) 'attachedTo': groupPathFor(package, group),
        };
      case 'importTokens':
        return importTokens(
          package: package,
          jsonPath: switch (arguments['file']) {
            String path when path.isNotEmpty =>
              p.isAbsolute(path) ? path : p.join(host.worktree.path, path),
            _ => throw ArgumentError.value(
              arguments['file'],
              'file',
              'the saved variables JSON, by path',
            ),
          },
          library: arguments['library'] as String?,
          force: switch (arguments['force']) {
            bool b => b,
            'true' => true,
            _ => false,
          },
        );
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

  static String _text(Object? value, String name, String what) =>
      switch (value) {
        String s when s.trim().isNotEmpty => s.trim(),
        _ => throw ArgumentError.value(value, name, what),
      };

  /// A scene named by class, file name or path — refused by listing what
  /// this package actually has, which is the only useful answer to a typo.
  String _resolveScene(String package, Object? wanted) {
    var scenes = scenesFor(package) ?? discoverPackage(rootFor(package)).scenes;
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
    var scanned = packages.where((p) => scanFor(p) != null).toList();
    if (scanned.isEmpty) {
      return const Status.neutral('not computed');
    }
    var total = scanned.fold(0, (n, p) => n + scanFor(p)!.scenes.length);
    var groups = scanned.fold(0, (n, p) => n + scanFor(p)!.groups.length);
    if (groups == 0) return const Status.neutral('no scene groups');
    return Status.neutral(
      '${plural(total, 'scene')} · ${plural(groups, 'group')}',
    );
  }

  StatusBadge get _badge {
    var total = 0;
    for (var package in packages) {
      total += scanFor(package)?.scenes.length ?? 0;
    }
    return total == 0 ? StatusBadge.none : StatusBadge.count(total);
  }

  Status _childStatus(String package) {
    if (failureFor(package) case var failure?) return Status.error(failure);
    var scan = scanFor(package);
    if (scan == null) {
      return Status.neutral(isScanning(package) ? 'scanning…' : 'not computed');
    }
    if (scan.groups.isEmpty) {
      return Status.neutral(
        scan.strayScenes == 0
            ? 'no scene groups'
            : '${plural(scan.strayScenes, 'scene file')} in no group',
      );
    }
    return Status.neutral(
      '${plural(scan.scenes.length, 'scene')} · '
      '${plural(scan.groups.length, 'group')}',
    );
  }

  /// The inventory: every group found, by package, with its scenes — the
  /// same listing the panel draws, so `fw` and an agent read what the human
  /// reads.
  PluginView get _view {
    var sections = <ViewNode>[];
    for (var package in packages) {
      var scan = scanFor(package);
      if (scan == null) continue;
      for (var group in scan.groups) {
        var scenes = group.scenes;
        sections.add(
          ViewSection('${package == '.' ? '' : '$package · '}${group.name}', [
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
      if (scan.libraries.isNotEmpty) {
        sections.add(
          ViewSection('${package == '.' ? '' : '$package · '}libraries', [
            ViewItems([
              for (var library in scan.libraries)
                ViewItem(
                  library.symbol,
                  detail: p.relative(library.path, from: host.worktree.path),
                ),
            ]),
          ]),
        );
      }
    }
    return PluginView(sections);
  }
}

PluginCore sceneCoreFactory(PluginHost host) => SceneCore(host);
