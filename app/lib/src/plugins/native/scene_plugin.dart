import '../../assets/model/font_axes.dart';

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../address/address_scope.dart';
import '../../embedder/embedded_engine.dart';
import '../../embedder/guest_texture.dart';
import '../../previews/catalog_session.dart';
import '../../previews/compiler_daemon_client.dart';

import 'package:flutterware/scene_authoring.dart';

import '../../scene/args_generate.dart';
import '../../scene/discovery.dart';
import '../../scene/externals_file.dart';
import '../../scene/group_file.dart';
import '../../scene/autosave.dart';
import '../../scene/editor.dart';
import '../../scene/guest.dart';
import '../../scene/import/variables.dart';
import '../../scene/scene_file.dart';
import '../../scene/playback.dart';
import '../../scene/tokens_file.dart';
import '../../scene/tokens_library.dart';
import '../../scene/ui/tokens_host.dart';
import '../../scene/ui/workspace_view.dart';
import '../../scene/watch.dart';
import '../../scene/workspace.dart';
import '../../ui/action_button.dart';
import '../../ui/count_badge.dart';
import '../../ui/design/design.dart';
import '../../ui/empty_state.dart';
import '../../ui/loading_state.dart';
import '../../ui/context_menu.dart';
import '../../ui/menu.dart';
import '../../ui/panel_header.dart';
import '../../ui/picker.dart';
import '../../ui/popover.dart';
import '../../ui/tappable.dart';
import '../native_plugin.dart';
import 'no_packages.dart';
import 'scene_core.dart';

export 'scene_core.dart' show SceneCore, scenePluginId;

/// The GUI half of the scene editor.
///
/// Milestone 4 of the graduation plan: the editor's real home. The panels it
/// mounts are still the spike's — they are rebuilt on the design system one
/// at a time from here, which is the whole point of landing the home first.
class ScenePlugin extends NativePlugin<SceneCore> {
  ScenePlugin(super.core);

  final _sessions = <String, CatalogSession>{};

  /// The live guest for [package], booted on first ask — which is a scene
  /// being opened, never the panel merely being looked at.
  CatalogSession sessionFor(String package) =>
      _sessions.putIfAbsent(package, () {
        var session = CatalogSession(
          appPackageRoot: host.workspace.appContext.appToolDirectory.path,
          flutterSdkRoot: host.workspace.flutterSdk.root,
          projectRoot: p.join(host.worktree.path, package),
          worktreeRoot: host.worktree.path,
          connectToDaemon: CompilerDaemonClient.connect,
        );
        unawaitedStart(session);
        return session;
      });

  void unawaitedStart(CatalogSession session) {
    session.start(width: 2048, height: 1000).ignore();
  }

  @override
  void dispose() {
    for (var session in _sessions.values) {
      session.dispose();
    }
    super.dispose();
  }

  @override
  Widget buildPanel(BuildContext context) => _ScenePanel(this);
}

class _ScenePanel extends StatefulWidget {
  const _ScenePanel(this.plugin);

  final ScenePlugin plugin;

  @override
  State<_ScenePanel> createState() => _ScenePanelState();
}

class _ScenePanelState extends State<_ScenePanel>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  String? _tracked;
  String? _package;

  /// The open file, and the guest rendering it. Null until a scene is
  /// picked: booting a guest is expensive and a listing needs none.
  SceneWorkspace? _workspace;
  SceneGuest? _guest;

  /// The group the open file belongs to — what it is parsed against and
  /// which folder's host the guest boots.
  SceneGroupEntry? _group;

  /// The libraries opened here, by path — one document per file, shared by
  /// every scene of every group that lists it, kept across scene opens so
  /// an unsaved edit survives switching scenes.
  final _libraries = <String, TokensLibrary>{};

  /// The library at [path], read once and kept; null when it does not
  /// parse, with the reason in the note.
  TokensLibrary? _libraryAt(String path) {
    var canonical = p.canonicalize(path);
    if (_libraries[canonical] case var open?) return open;
    var opened = TokensLibrary.open(path, File(path).readAsStringSync());
    if (!opened.ok) {
      _note = '${p.basename(path)}: ${opened.refusals.first}';
      return null;
    }
    return _libraries[canonical] = opened.library!;
  }

  /// The group's libraries as live documents, in the declaration's order.
  List<TokensLibrary> _groupLibraries() {
    var package = _package;
    var group = _group;
    if (package == null || group == null) return const [];
    return [
      for (var l in _core.vocabularyFor(package, group).libraries)
        ?_libraryAt(l.entry.path),
    ];
  }

  /// The vocabulary the open file is parsed against — the libraries as
  /// they are NOW, unsaved edits included, then the exports.
  List<SceneTokenDecl> _liveTokens(List<TokensLibrary> libraries) => [
    for (var l in libraries) ...l.tokens,
    ..._vocabulary().exports,
  ];

  /// The doors the token surfaces need past this one file.
  SceneTokensHost _tokensHost(SceneWorkspace workspace) {
    var package = _package!;
    var group = _group!;
    Set<String> openPaths() => {for (var f in workspace.openFiles) f.path};
    List<String> elsewhere(String name) {
      var library = workspace.libraryOf(name);
      if (library == null) return const [];
      return [
        for (var file in workspace.openFiles)
          if (!identical(file, workspace.active))
            for (var (node, prop) in file.editor.readersOfToken(name))
              '${file.className} · ${node.name}.$prop',
        for (var r in _core.tokenReaders(
          package,
          library.path,
          name,
          except: openPaths(),
        ))
          '$r',
      ];
    }

    return SceneTokensHost(
      libraries: workspace.libraries,
      onNewLibrary: () async {
        try {
          var path = await _core.createLibrary(
            package,
            _core.groupPathFor(package, group),
            group.name,
            attachTo: group,
          );
          if (_libraryAt(path) case var library?) {
            workspace.addLibrary(library);
          }
          setState(() => _note = '');
        } on Object catch (e) {
          setState(() => _note = '$e');
        }
      },
      rename: (name, wanted) {
        var library = workspace.libraryOf(name);
        if (library == null) {
          throw ArgumentError("\"$name\" is the app's — rename it in the app");
        }
        var taken = workspace.tokenNames..remove(name);
        if (library.nameProblem(wanted, renaming: name, taken: taken)
            case var problem?) {
          throw ArgumentError(problem);
        }
        // Readers first, the library after: an editor holds an alias
        // through the gap, and the closed files are rewritten against the
        // vocabulary as it will be.
        for (var file in workspace.openFiles) {
          file.editor.renameTokenRefs(name, wanted);
        }
        library.rename(name, wanted, taken: taken);
        var touched = _core.renameTokenInFiles(
          package,
          library.path,
          name,
          wanted,
          except: openPaths(),
        );
        if (touched.isNotEmpty) {
          setState(() {
            _note = 'renamed in ${touched.map(p.basename).join(', ')} too';
          });
        }
      },
      deleteProblem: (name) {
        var others = elsewhere(name);
        return others.isEmpty ? null : 'read by ${others.join(', ')}';
      },
      delete: (name) => workspace.libraryOf(name)?.delete(name),
      readersElsewhere: elsewhere,
      importInto: (path) async {
        var library = workspace.libraryAt(path);
        if (library == null) return;
        var json = await _pickVariables();
        if (json == null) return;
        try {
          var note = library.merge(
            importVariables(json.readAsStringSync()),
            from: p.basename(json.path),
          );
          setState(() => _note = 'Imported ${note.from}: ${note.summary}');
        } on Object catch (e) {
          setState(() => _note = '$e');
        }
      },
    );
  }

  /// The design file's variables JSON, chosen by hand; null when the
  /// picker was backed out of.
  Future<File?> _pickVariables() async {
    var picked = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'Variables JSON', extensions: ['json']),
      ],
    );
    return picked == null ? null : File(picked.path);
  }

  String _note = '';

  /// One playback per motion opened, by file and name — a playback owns a
  /// ticker, so it is made once and kept.
  final _playbacks = <String, ScenePlayback>{};

  /// There is no save button: the workspace is written when the editor goes
  /// quiet. See [SceneAutosave] for what makes that safe.
  late final _autosave = SceneAutosave(
    write: (path, source) => File(path).writeAsStringSync(source),
    onChanged: _redraw,
  );

  /// The save state moved. Deferred when a build is running, because [build]
  /// is one of the places that binds the autosaver and a write it flushes on
  /// the way in must not call `setState` inside that frame.
  void _redraw() {
    if (!mounted) return;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    } else {
      setState(() {});
    }
  }

  /// Watches the package's scene directory, so a file written by an agent or
  /// arriving with a branch reaches the editor rather than waiting for a
  /// reopen.
  SceneWatcher? _watcher;
  String? _watching;

  ScenePlayback _playbackFor(SceneFile file, String motion) {
    // A motion deleted or renamed leaves a playback bound to a name the
    // editor no longer has; it is dropped the next time any motion of the
    // file is asked for, so a rename back does not revive a stale binding.
    _playbacks.removeWhere((key, playback) {
      var stale =
          key.startsWith('${file.path}#') &&
          !file.editor.motions.containsKey(playback.motionName);
      if (stale) playback.dispose();
      return stale;
    });
    return _playbacks.putIfAbsent(
      '${file.path}#$motion',
      () => ScenePlayback(file.editor, motion, vsync: this),
    );
  }

  void _disposePlaybacks() {
    for (var playback in _playbacks.values) {
      playback.dispose();
    }
    _playbacks.clear();
  }

  SceneCore get _core => widget.plugin.core;

  String? _resolve() =>
      AddressScope.segment(context, 0) ?? _core.packages.firstOrNull;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  /// Leaving the app writes what is owed rather than waiting out the quiet
  /// period. Nobody expects to tab away and come back to unwritten work.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _autosave.flush();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _package = _resolve();
    _retrack();
  }

  /// A config rebuild hands this panel a new plugin, and with it a new
  /// session map: the guest has to move to the new session or it pushes to
  /// a disposed one while the canvas draws the other.
  @override
  void didUpdateWidget(_ScenePanel old) {
    super.didUpdateWidget(old);
    if (old.plugin == widget.plugin) return;
    var package = _package;
    // The new core has computed nothing; the old one's scan is gone with it.
    if (package != null) _core.track(package);
    var file = _workspace?.active;
    var group = _group;
    if (file == null || package == null || group == null) return;
    _guest?.dispose();
    _guest = SceneGuest(
      widget.plugin.sessionFor(package),
      file.editor,
      groupDirectory: _core.groupPathFor(package, group),
    );
    // The new engine started at the session's default size; forget the
    // old one's, or the artboard draws at half scale in a texture nobody
    // resized.
    _paneRendered = null;
  }

  void _retrack() {
    var wanted = _package;
    if (wanted == _tracked) return;
    _tracked = wanted;
    _close();
    if (wanted != null) _core.track(wanted);
  }

  void _close() {
    _disposePlaybacks();
    _autosave.bind(null);
    _guest?.dispose();
    _guest = null;
    _workspace?.dispose();
    _workspace = null;
    _group = null;
    _note = '';
  }

  void _open(SceneEntry entry) {
    var package = _package!;
    var group = _core.groupFor(package, entry.path);
    if (group == null) {
      setState(() {
        _close();
        _note =
            '${entry.fileName} is in no group — no folder above it has a '
            '$sceneGroupFileName';
      });
      return;
    }
    _group = group;
    var libraries = _groupLibraries();
    var opened = SceneFile.open(
      entry.path,
      File(entry.path).readAsStringSync(),
      declaredArgs: _declaredArgs(),
      tokens: _liveTokens(libraries),
      modes: {for (var l in libraries) ...l.modes}.toList()..sort(),
    );
    if (!opened.ok) {
      setState(() {
        _close();
        _note =
            '${entry.fileName}: ${opened.refusals.length} refusal(s) — '
            '${opened.refusals.first}';
      });
      return;
    }
    var file = opened.file!;
    setState(() {
      _guest?.dispose();
      _workspace?.dispose();
      _workspace = SceneWorkspace(
        file,
        resolveNested: _resolveNested,
        libraries: libraries,
        tokensFor: _liveTokens,
      );
      _guest = SceneGuest(
        widget.plugin.sessionFor(package),
        file.editor,
        groupDirectory: _core.groupPathFor(package, group),
      );
      _note = '';
    });
    _autosave.bind(_workspace);
  }

  /// Starts (or re-points) the watch on the package's scanned scope — scene
  /// files, group declarations and libraries alike.
  void _watchDirectory(String package) {
    var directory = _core.rootFor(package);
    if (_watching == directory && _watcher?.isWatching == true) return;
    _watcher?.dispose();
    _watching = directory;
    _watcher = SceneWatcher(directory: directory, onChanged: _onDiskChanged)
      ..start();
  }

  /// Scene files, a declaration or a library moved on disk. The listing is
  /// refreshed either way; an open file is adopted when this editor has
  /// nothing of its own to lose, and held otherwise.
  void _onDiskChanged(Set<String> paths) {
    if (!mounted) return;
    var package = _package ?? _resolve();
    // reload, not rescan: forgetting the listing without asking again leaves
    // every surface reading it on "Looking for scenes" for good.
    if (package != null) unawaited(_core.reload(package));
    var workspace = _workspace;
    if (workspace == null) {
      setState(() {});
      return;
    }
    var adopted = <String>[];
    var refused = <String>[];
    var held = <String>[];
    // A library that moved on disk: our own write comes back as an event,
    // an edit somebody else made is adopted when this editor has nothing
    // to lose, and held otherwise — the scene files' rule.
    for (var library in workspace.libraries.toList()) {
      if (!paths.contains(p.canonicalize(library.path))) continue;
      String source;
      try {
        source = File(library.path).readAsStringSync();
      } on FileSystemException {
        continue;
      }
      if (library.matchesDisk(source)) {
        _autosave.resume(library.path);
        continue;
      }
      if (library.isDirty) {
        held.add(library.fileName);
        _autosave.suspend(
          library.path,
          '${library.fileName} changed on disk — save to keep yours',
        );
        continue;
      }
      var refusals = library.adopt(source);
      if (refusals.isEmpty) {
        adopted.add(library.fileName);
        _autosave.resume(library.path);
      } else {
        refused.add('${library.fileName}: ${refusals.first}');
      }
    }
    for (var file in workspace.openFiles.toList()) {
      if (!paths.contains(p.canonicalize(file.path))) continue;
      String source;
      try {
        source = File(file.path).readAsStringSync();
      } on FileSystemException {
        // Deleted, or caught mid-write. The editor keeps what it has, and the
        // next event says what the file settled on.
        continue;
      }
      // Our own automatic write, arriving back as an event.
      if (file.matchesDisk(source)) {
        _autosave.resume(file.path);
        continue;
      }
      if (file.isDirty) {
        held.add(p.basename(file.path));
        _autosave.suspend(
          file.path,
          '${p.basename(file.path)} changed on disk — save to keep yours',
        );
        continue;
      }
      var refusals = file.adopt(
        source,
        declaredArgs: _declaredArgs(),
        tokens: _tokens(),
      );
      if (refusals.isEmpty) {
        adopted.add(p.basename(file.path));
        _autosave.resume(file.path);
      } else {
        refused.add('${p.basename(file.path)}: ${refusals.first}');
      }
    }
    if (adopted.isNotEmpty) workspace.resolveInstances(workspace.active);
    setState(() {
      _note = refused.isNotEmpty
          ? 'on disk and unreadable — ${refused.join('; ')}'
          : held.isNotEmpty
          ? '${held.join(', ')} changed on disk'
          : adopted.isNotEmpty
          ? 'reloaded ${adopted.join(', ')} from disk'
          : _note;
    });
  }

  /// Writes an empty scene — one root frame of the size asked for — as
  /// `<snake_name>.scene.dart` in [group]'s folder, and opens it. The
  /// emitter writes it, so a file made here is canonical from its first
  /// byte.
  void _createScene(
    String package,
    SceneGroupEntry group,
    String className,
    double width,
    double height,
  ) {
    var root = FrameNode(name: 'root')
      ..width = width
      ..height = height
      ..fill = const SceneColor(0xFFFFFFFF);
    var source = emitSceneFile(SceneDocument(root), className: className);
    var dir = group.directory;
    var path = p.join(dir, '${_snake(className)}.scene.dart');
    if (File(path).existsSync()) {
      setState(() => _note = '${p.basename(path)} already exists');
      return;
    }
    Directory(dir).createSync(recursive: true);
    File(path).writeAsStringSync(source);
    _core.rescan(package);
    _core.track(package);
    _open(SceneEntry(path: path, className: className, age: DateTime.now()));
  }

  static String _snake(String className) => className
      .replaceAllMapped(RegExp('([a-z0-9])([A-Z])'), (m) => '${m[1]}_${m[2]}')
      .toLowerCase();

  /// What the open file's group declares — the widgets an inspector reads
  /// a type and a default from, the tokens a parse checks `tokens.x`
  /// against.
  GroupVocabulary _vocabulary() {
    var package = _package;
    var group = _group;
    return package == null || group == null
        ? GroupVocabulary.empty
        : _core.vocabularyFor(package, group);
  }

  List<ExternalWidgetDecl> _externals() => _vocabulary().widgets;

  /// The variable axes of a family this package declares, read out of the
  /// font file. Cached for the session: a font file does not change under a
  /// running editor, and opening one per panel rebuild would.
  final _axesByPackage = <String, Map<String, List<FontAxis>>>{};

  List<FontAxis> _fontAxes(String family) {
    var package = _package;
    if (package == null) return const [];
    var root = _core.projectRootFor(package);
    return (_axesByPackage[root] ??= readPackageFontAxes(root))[family] ??
        const [];
  }

  Map<String, Set<String>> _declaredArgs() => _vocabulary().declaredArgs;

  /// The tokens as the open workspace holds them, or the scan's when
  /// nothing is open.
  List<SceneTokenDecl> _tokens() => switch (_workspace) {
    var w? => _liveTokens(w.libraries),
    null => _vocabulary().tokens,
  };

  /// A nested scene is another scene file of the same group, found by the
  /// class it declares. Opened fresh here; the workspace keeps the one copy
  /// it already holds, so edits inside a child are not lost to a re-resolve.
  SceneFile? _resolveNested(SceneNode node) {
    if (node is! SceneRefNode) return null;
    var group = _group;
    if (group == null) return null;
    for (var entry in group.scenes) {
      if (entry.className != node.sceneClassName) continue;
      var opened = SceneFile.open(
        entry.path,
        File(entry.path).readAsStringSync(),
        declaredArgs: _declaredArgs(),
        tokens: _tokens(),
        modes: _workspace?.modeNames ?? const [],
      );
      if (!opened.ok) {
        setState(() {
          _note =
              '${entry.fileName}: ${opened.refusals.length} refusal(s) — '
              '${opened.refusals.first}';
        });
        return null;
      }
      return opened.file;
    }
    return null;
  }

  /// The guest draws the active file — the one the breadcrumb ends on. A
  /// drill-in or a step back swaps which editor it pushes, and the artboard
  /// size with it.
  void _syncGuest() {
    var workspace = _workspace;
    var package = _package;
    var group = _group;
    if (workspace == null || package == null || group == null) return;
    if (_guest?.editor == workspace.editor) return;
    _guest?.dispose();
    _guest = SceneGuest(
      widget.plugin.sessionFor(package),
      workspace.editor,
      groupDirectory: _core.groupPathFor(package, group),
    );
    _paneRendered = null;
  }

  /// Writes every dirty file the workspace holds — the one on screen and any
  /// nested scene edited on the way here — so a drill-in never leaves work
  /// behind in a file the breadcrumb no longer shows.
  /// ⌘S. The files are written without it, so this is for the two things an
  /// automatic write will not do: write now rather than in a moment, and
  /// overwrite a version that arrived on disk while you were working.
  void _save() {
    if (_workspace == null) return;
    setState(_autosave.flush);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _resizeSettle?.cancel();
    // Before the playbacks and the guest: closing the panel is the last
    // moment the pending write can still happen.
    _autosave.dispose();
    _watcher?.dispose();
    _disposePlaybacks();
    _guest?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var package = _package ?? _resolve();
    if (package == null) {
      return const NoPackagesConfigured(icon: Icons.movie_filter_outlined);
    }
    // The surface that reads the listing is the one that asks for it. Doing
    // it here rather than only when the address changes is what keeps a scan
    // that never started — or one something invalidated — from leaving this
    // panel on its loading state for good. All three are cheap when nothing
    // moved, and doing them here is also what carries them through a hot
    // reload: the panel's state object outlives one, its fields do not.
    _core.track(package);
    _autosave.bind(_workspace);
    _watchDirectory(package);
    return AnimatedBuilder(
      animation: widget.plugin,
      builder: (context, _) {
        var workspace = _workspace;
        if (workspace == null) return _listing(package);
        return _editor(workspace);
      },
    );
  }

  Widget _listing(String package) {
    var scan = _core.scanFor(package);
    if (scan == null) return const LoadingState(title: 'Looking for scenes');
    var colors = context.colors;
    var type = context.type;
    var scope = _core.directoryFor(package);
    var libraries = scan.libraries;
    // Which groups list which library — from the vocabularies, so an
    // unlisted library is visibly unused rather than lost.
    var listedBy = <String, List<SceneGroupEntry>>{};
    for (var group in scan.groups) {
      for (var l in _core.vocabularyFor(package, group).libraries) {
        (listedBy[p.canonicalize(l.entry.path)] ??= []).add(group);
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FwPanelHeader(
          'Scenes',
          subtitle: [scope == '.' ? package : '$package/$scope'],
          badge: scan.scenes.isEmpty ? null : CountBadge(scan.scenes.length),
          trailing: Row(
            spacing: FwSpacing.sm,
            children: [
              _NewLibraryButton(
                groups: scan.groups,
                defaultFolder: 'lib',
                folderOf: (group) => _core.groupPathFor(package, group),
                onCreate: (name, folder, group) =>
                    _createLibrary(package, folder, name, attachTo: group),
              ),
              _NewGroupButton(
                taken: {for (var g in scan.groups) g.name},
                onCreate: (folder) => _createGroup(package, folder),
              ),
            ],
          ),
        ),
        if (_note.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: FwSpacing.xl,
              vertical: FwSpacing.sm,
            ),
            child: Text(_note, style: type.body.copyWith(color: colors.red)),
          ),
        if (scan.groups.isEmpty && libraries.isEmpty)
          Expanded(
            child: EmptyState(
              icon: Icons.movie_filter_outlined,
              title: 'No scene groups',
              message:
                  'A scene group is a folder with a $sceneGroupFileName in '
                  'it; its scenes are the .scene.dart files below. None '
                  'under ${scope == '.' ? 'this package' : '$scope/'} yet — '
                  'New group writes one.',
            ),
          )
        else
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: FwSpacing.xs),
              children: [
                for (var group in scan.groups)
                  ..._groupSection(package, group, libraries),
                if (libraries.isNotEmpty || scan.groups.isNotEmpty)
                  _sectionTitle(
                    'Libraries',
                    libraries.isEmpty
                        ? 'none yet — a library is a *$sceneTokensFileSuffix '
                              'the editor owns'
                        : null,
                  ),
                for (var library in libraries)
                  _libraryRow(
                    package,
                    library,
                    listedBy[p.canonicalize(library.path)] ?? const [],
                    scan.groups,
                  ),
                if (scan.strayScenes > 0)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      FwSpacing.xl,
                      FwSpacing.lg,
                      FwSpacing.xl,
                      FwSpacing.sm,
                    ),
                    child: Text(
                      '${scan.strayScenes} scene file'
                      '${scan.strayScenes == 1 ? '' : 's'} outside any group '
                      '— not scenes the tool knows',
                      style: type.caption.copyWith(color: colors.mut2),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _sectionTitle(String title, String? caption) => Padding(
    padding: const EdgeInsets.fromLTRB(
      FwSpacing.xl,
      FwSpacing.lg,
      FwSpacing.xl,
      FwSpacing.xs,
    ),
    child: Row(
      spacing: FwSpacing.sm,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(title, style: context.type.bodyStrong),
        if (caption != null)
          Expanded(
            child: Text(
              caption,
              style: context.type.caption.copyWith(color: context.colors.mut2),
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
    ),
  );

  /// One group: its folder as the title, what it sees in a line, its
  /// refusals in red, its scenes beneath, and New scene at its right edge.
  List<Widget> _groupSection(
    String package,
    SceneGroupEntry group,
    List<SceneLibraryEntry> libraries,
  ) {
    var colors = context.colors;
    var type = context.type;
    var vocabulary = _core.vocabularyFor(package, group);
    var refusals = _core.argsResultFor(package, group)?.refusals ?? const [];
    var sees = [
      _count(vocabulary.libraries.length, 'library', 'libraries'),
      _count(vocabulary.widgets.length, 'widget', 'widgets'),
      _count(vocabulary.exports.length, 'export', 'exports'),
    ].join(' · ');
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(
          FwSpacing.xl,
          FwSpacing.lg,
          FwSpacing.xl,
          FwSpacing.xs,
        ),
        child: Row(
          spacing: FwSpacing.md,
          children: [
            Icon(Icons.folder_outlined, size: FwIconSize.md, color: colors.mut),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    spacing: FwSpacing.sm,
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(group.name, style: type.bodyStrong),
                      // The path, when it says more than the name does.
                      if (_core.groupPathFor(package, group) != group.name)
                        Text(
                          _core.groupPathFor(package, group),
                          style: type.caption.copyWith(color: colors.mut2),
                        ),
                    ],
                  ),
                  Text(sees, style: type.caption.copyWith(color: colors.mut2)),
                ],
              ),
            ),
            _NewSceneButton(
              taken: {for (var s in group.scenes) s.className},
              onCreate: (className, width, height) =>
                  _createScene(package, group, className, width, height),
            ),
          ],
        ),
      ),
      for (var refusal in refusals)
        Padding(
          padding: const EdgeInsets.fromLTRB(
            FwSpacing.xl + FwIconSize.md + FwSpacing.md,
            0,
            FwSpacing.xl,
            FwSpacing.xs,
          ),
          child: Text(
            '$refusal',
            style: type.caption.copyWith(color: colors.red),
          ),
        ),
      if (group.scenes.isEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(
            FwSpacing.xl + FwIconSize.md + FwSpacing.md,
            FwSpacing.xs,
            FwSpacing.xl,
            FwSpacing.sm,
          ),
          child: Text(
            'No scenes in this folder yet.',
            style: type.caption.copyWith(color: colors.mut2),
          ),
        ),
      for (var scene in group.scenes)
        Tappable(
          onTap: () => _open(scene),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              FwSpacing.xl + FwIconSize.md + FwSpacing.md,
              FwSpacing.sm,
              FwSpacing.xl,
              FwSpacing.sm,
            ),
            child: Row(
              spacing: FwSpacing.md,
              children: [
                Icon(
                  Icons.movie_filter_outlined,
                  size: FwIconSize.md,
                  color: colors.mut,
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(scene.className, style: type.body),
                      Text(
                        p.relative(
                          scene.path,
                          from: widget.plugin.host.worktree.path,
                        ),
                        style: type.caption.copyWith(color: colors.mut2),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
    ];
  }

  static String _count(int n, String one, String many) =>
      '$n ${n == 1 ? one : many}';

  /// One library: its symbol, its file, who lists it, and a menu to attach
  /// it to a group or detach it.
  Widget _libraryRow(
    String package,
    SceneLibraryEntry library,
    List<SceneGroupEntry> listedBy,
    List<SceneGroupEntry> groups,
  ) {
    var colors = context.colors;
    var type = context.type;
    var listing = {for (var g in listedBy) p.canonicalize(g.directory)};
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        FwSpacing.xl,
        FwSpacing.sm,
        FwSpacing.xl,
        FwSpacing.sm,
      ),
      child: Row(
        spacing: FwSpacing.md,
        children: [
          Icon(Icons.style_outlined, size: FwIconSize.md, color: colors.mut),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(library.symbol, style: type.body),
                Text(
                  '${p.relative(library.path, from: widget.plugin.host.worktree.path)}'
                  ' · ${listedBy.isEmpty ? 'listed by no group' : 'listed by ${listedBy.map((g) => g.name).join(', ')}'}',
                  style: type.caption.copyWith(
                    color: listedBy.isEmpty ? colors.warningText : colors.mut2,
                  ),
                ),
              ],
            ),
          ),
          Tooltip(
            message: 'Attach to a group, or detach',
            child: Builder(
              builder: (context) => Tappable(
                onTap: () {
                  var box = context.findRenderObject()! as RenderBox;
                  var at = box.localToGlobal(Offset(0, box.size.height));
                  showContextMenu(context, at, [
                    const MenuHeader('Groups'),
                    for (var group in groups)
                      if (listing.contains(p.canonicalize(group.directory)))
                        MenuItem(
                          'Detach from ${group.name}',
                          icon: Icons.link_off,
                          onSelected: () =>
                              _detachLibrary(package, group, library),
                        )
                      else
                        MenuItem(
                          'Attach to ${group.name}',
                          icon: Icons.link,
                          onSelected: () =>
                              _attachLibrary(package, group, library),
                        ),
                    if (groups.isEmpty)
                      const MenuItem('No groups to attach to'),
                    const MenuDivider(),
                    MenuItem(
                      'Import variables…',
                      icon: Icons.download_outlined,
                      shortcut: "a design file's JSON",
                      onSelected: () => _importInto(package, library.path),
                    ),
                  ]);
                },
                borderRadius: BorderRadius.circular(context.radii.radiusSmall),
                child: Padding(
                  padding: const EdgeInsets.all(FwSpacing.xs),
                  child: Icon(
                    Icons.more_horiz,
                    size: FwIconSize.md,
                    color: colors.ink,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// From the package page: the library on disk, merged through the core
  /// — the panel has no document open for it there.
  Future<void> _importInto(String package, String libraryPath) async {
    var json = await _pickVariables();
    if (json == null) return;
    try {
      var report = await _core.importTokens(
        package: package,
        jsonPath: json.path,
        library: libraryPath,
      );
      setState(
        () => _note =
            'Imported ${p.basename(json.path)} into ${report['symbol']}: '
            '${report['added']} added · ${report['updated']} updated · '
            '${report['unchanged']} unchanged · '
            '${(report['kept']! as List).length} kept',
      );
    } on Object catch (e) {
      setState(() => _note = '$e');
    }
  }

  Future<void> _createGroup(String package, String folder) async {
    try {
      await _core.createGroup(package, folder);
      setState(() => _note = '');
    } on Object catch (e) {
      setState(() => _note = '$e');
    }
  }

  Future<void> _createLibrary(
    String package,
    String folder,
    String name, {
    SceneGroupEntry? attachTo,
  }) async {
    try {
      await _core.createLibrary(package, folder, name, attachTo: attachTo);
      setState(() => _note = '');
    } on Object catch (e) {
      setState(() => _note = '$e');
    }
  }

  Future<void> _attachLibrary(
    String package,
    SceneGroupEntry group,
    SceneLibraryEntry library,
  ) async {
    try {
      await _core.attachLibrary(package, group, library.path);
      setState(() => _note = '');
    } on Object catch (e) {
      setState(() => _note = '$e');
    }
  }

  Future<void> _detachLibrary(
    String package,
    SceneGroupEntry group,
    SceneLibraryEntry library,
  ) async {
    try {
      await _core.detachLibrary(package, group, library.path);
      setState(() => _note = '');
    } on Object catch (e) {
      setState(() => _note = '$e');
    }
  }

  Widget _editor(SceneWorkspace workspace) {
    var editor = workspace.editor;
    // ⌘S above every scope, so it saves from the canvas, the timeline and a
    // field alike; the scopes below bind nothing that shadows it.
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyS, meta: true): _save,
      },
      child: _editorBody(workspace, editor),
    );
  }

  Widget _editorBody(SceneWorkspace workspace, SceneEditor editor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(
          workspace: workspace,
          groupName: _group?.name,
          note: _autosave.note.isNotEmpty ? _autosave.note : _note,
          saveState: _autosave.state,
          onBack: () => setState(_close),
          onCrumb: (index) => setState(() {
            workspace.goTo(index);
            _syncGuest();
          }),
          onSave: _save,
        ),
        Container(height: 1, color: context.colors.line),
        Expanded(
          child: SceneWorkspaceView(
            key: ValueKey(workspace.active.path),
            editor,
            packageRoot: _core.rootFor(_package!),
            externals: _externals(),
            axesFor: _fontAxes,
            tokens: _tokensHost(workspace),
            playbackFor: (motion) => _playbackFor(workspace.active, motion),
            sceneClassName: workspace.active.className,
            status: _guest?.status,
            onEnterNested: (node) => setState(() {
              workspace.enter(node);
              _syncGuest();
            }),
            pane: _guestPane,
            canvasTrailing: [
              // The guest is another process on the catalog daemon's
              // kernel: a change to the app's widgets, or to SceneView
              // itself, reaches it through a reload and nothing else.
              Tooltip(
                message: 'Hot reload the guest',
                child: Tappable(
                  onTap: () async {
                    await widget.plugin.sessionFor(_package!).reload();
                    // The reload remounts the host with no scene in hand;
                    // nothing else would push until the next edit.
                    _guest?.push();
                  },
                  borderRadius: BorderRadius.circular(
                    context.radii.radiusSmall,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(FwSpacing.xs),
                    child: Icon(
                      Icons.refresh,
                      size: FwIconSize.md,
                      color: context.colors.ink,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// The artboard's picture is the guest's texture, sized to the artboard so
  /// editor coordinates and guest coordinates are one space.
  /// The trailing edge of a pane resize: a window being dragged is a
  /// stream of sizes, and a guest resized on every one of them spends its
  /// frames on surfaces it never shows.
  Timer? _resizeSettle;

  /// What the guest was last asked to render: the pane, in logical pixels.
  Size? _paneRendered;

  /// The guest's texture, the size of the pane, drawn under the artboard.
  ///
  /// The guest renders the artboard through [view] itself — a zoomed
  /// artboard is rasterised at the zoom, so the picture is crisp at any
  /// magnification and never costs more than the pane's pixels. The view
  /// reaches it after the gesture settles; until the render lands, the
  /// texture is drawn through the difference between the view it shows and
  /// the view the canvas is at, so panning follows the pointer and the
  /// picture snaps crisp at rest.
  Widget _guestPane(
    BuildContext context,
    Matrix4 view,
    Size pane,
    Size artboard,
  ) {
    var session = widget.plugin.sessionFor(_package!);
    var guest = _guest;
    return AnimatedBuilder(
      animation: Listenable.merge([session, ?guest?.rendered]),
      builder: (context, _) {
        var engine = session.engine;
        if (engine == null ||
            engine.phase != EmbeddedEnginePhase.running ||
            engine.textureId == null) {
          return Center(
            child: Text(
              session.phase == CatalogSessionPhase.error
                  ? 'session error'
                  : 'booting the guest… (${session.busyWith ?? 'starting'})',
              style: context.type.caption.copyWith(color: context.colors.mut2),
            ),
          );
        }
        var dpr = MediaQuery.of(context).devicePixelRatio;
        if (_paneRendered != pane) {
          _paneRendered = pane;
          _resizeSettle?.cancel();
          _resizeSettle = Timer(const Duration(milliseconds: 120), () {
            _resizeSettle = null;
            if (!mounted || _paneRendered != pane) return;
            engine.resize(
              (pane.width * dpr).round(),
              (pane.height * dpr).round(),
              dpr,
            );
          });
        }
        guest?.setView(view, artboard: artboard);
        var shown = guest?.rendered.value ?? Matrix4.identity();
        var delta = view.clone()..multiply(Matrix4.inverted(shown));
        return Transform(
          transform: delta,
          child: SizedBox(
            width: pane.width,
            height: pane.height,
            child: GuestTexture(textureId: engine.textureId!),
          ),
        );
      },
    );
  }
}

/// Back, the breadcrumb, Save, and what the panel last did.
class _Header extends StatelessWidget {
  const _Header({
    required this.workspace,
    required this.groupName,
    required this.note,
    required this.saveState,
    required this.onBack,
    required this.onCrumb,
    required this.onSave,
  });

  final SceneWorkspace workspace;

  /// The folder the open file belongs to — the first crumb.
  final String? groupName;
  final String note;
  final SceneSaveState saveState;
  final VoidCallback onBack;
  final ValueChanged<int> onCrumb;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    var type = context.type;
    var crumbs = workspace.crumbs;
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: FwSpacing.md),
      child: Row(
        spacing: FwSpacing.sm,
        children: [
          Tooltip(
            message: 'Back to the scenes',
            child: Tappable(
              onTap: onBack,
              borderRadius: BorderRadius.circular(context.radii.radiusSmall),
              child: Padding(
                padding: const EdgeInsets.all(FwSpacing.xs),
                child: Icon(
                  Icons.arrow_back,
                  size: FwIconSize.md,
                  color: colors.ink,
                ),
              ),
            ),
          ),
          // The breadcrumb: the group, then the file, then every nested
          // scene entered since. The last is where you are, so it is not a
          // link; the group is a word, since back is the way to it.
          if (groupName case var name?) ...[
            Text(name, style: type.body.copyWith(color: colors.mut2)),
            Text('›', style: type.body.copyWith(color: colors.mut3)),
          ],
          for (var (index, crumb) in crumbs.indexed) ...[
            if (index > 0)
              Text('›', style: type.body.copyWith(color: colors.mut3)),
            if (index == crumbs.length - 1)
              Text(crumb.file.className, style: type.bodyStrong)
            else
              Tappable(
                onTap: () => onCrumb(index),
                borderRadius: BorderRadius.circular(context.radii.radiusSmall),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: FwSpacing.xs,
                    vertical: FwSpacing.xxs,
                  ),
                  child: Text(
                    crumb.file.className,
                    style: type.body.copyWith(color: colors.accentDark),
                  ),
                ),
              ),
          ],
          const Gap(FwSpacing.xs),
          // No save button. The file is written when the editor goes quiet,
          // so what belongs here is what happened, not a thing to press —
          // except when the file moved underneath, which is the one case a
          // person has to settle.
          if (saveState == SceneSaveState.conflicted)
            FwActionButton(
              label: 'Save anyway',
              primary: true,
              tooltip: 'The file changed on disk. Write yours over it (⌘S)',
              onPressed: () async => onSave(),
            )
          else
            Tooltip(
              message: saveState == SceneSaveState.refused
                  ? 'Nothing was written. The work is still here.'
                  : 'Saved as you work (⌘S writes now)',
              child: Text(
                switch (saveState) {
                  SceneSaveState.pending => 'Saving…',
                  SceneSaveState.refused => 'Not saved',
                  _ => 'Saved',
                },
                style: type.caption.copyWith(
                  color: saveState == SceneSaveState.refused
                      ? colors.red
                      : colors.mut2,
                ),
              ),
            ),
          Expanded(
            child: Text(
              note,
              style: type.caption.copyWith(
                color: saveState == SceneSaveState.refused
                    ? colors.red
                    : colors.mut2,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// "New scene": a name and an artboard size, in a popover off the header.
class _NewSceneButton extends StatefulWidget {
  const _NewSceneButton({required this.taken, required this.onCreate});

  final Set<String> taken;
  final void Function(String className, double width, double height) onCreate;

  @override
  State<_NewSceneButton> createState() => _NewSceneButtonState();
}

class _NewSceneButtonState extends State<_NewSceneButton> {
  final _name = TextEditingController();
  var _size = _sizes.first;

  static const _sizes = [
    (label: 'Banner 1024 × 500', width: 1024.0, height: 500.0),
    (label: 'Square 1080 × 1080', width: 1080.0, height: 1080.0),
    (label: 'Phone 390 × 844', width: 390.0, height: 844.0),
    (label: 'Badge 200 × 64', width: 200.0, height: 64.0),
  ];

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  String? get _refusal {
    var name = _name.text.trim();
    if (name.isEmpty) return null;
    if (!RegExp(r'^[A-Z][A-Za-z0-9]*$').hasMatch(name)) {
      return 'A class name: capital first, letters and digits';
    }
    if (widget.taken.contains(name)) return 'There is a $name already';
    return null;
  }

  @override
  Widget build(BuildContext context) => Popover(
    anchor: (context, controller) => FwActionButton(
      label: 'New scene',
      tooltip: 'A scene file with an empty artboard',
      onPressed: () async => controller.open(),
    ),
    side: PopoverSide.bottom,
    align: PopoverAlign.end,
    content: (context, controller) => _form(context, controller),
  );

  Widget _form(BuildContext context, PopoverController controller) {
    var colors = context.colors;
    return Container(
      width: 280,
      padding: const EdgeInsets.all(FwSpacing.lg),
      decoration: BoxDecoration(
        color: colors.panel,
        border: Border.all(color: colors.line),
        borderRadius: BorderRadius.circular(context.radii.radius),
        boxShadow: context.elevation.sm,
      ),
      child: StatefulBuilder(
        builder: (context, rebuild) {
          var refusal = _refusal;
          var name = _name.text.trim();
          void create() {
            if (name.isEmpty || refusal != null) return;
            controller.close();
            widget.onCreate(name, _size.width, _size.height);
            _name.clear();
          }

          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: FwSpacing.md,
            children: [
              Text('New scene', style: context.type.bodyStrong),
              TextField(
                controller: _name,
                autofocus: true,
                decoration: const InputDecoration(hintText: 'PromoBadge'),
                onChanged: (_) => rebuild(() {}),
                onSubmitted: (_) => create(),
              ),
              if (refusal != null)
                Text(
                  refusal,
                  style: context.type.caption.copyWith(color: colors.red),
                ),
              FwPicker<int>(
                choices: [
                  for (var (i, size) in _sizes.indexed)
                    FwChoice(value: i, label: size.label),
                ],
                selected: _sizes.indexOf(_size),
                onChanged: (i) => rebuild(() => _size = _sizes[i]),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: FwActionButton(
                  label: 'Create',
                  primary: true,
                  onPressed: name.isEmpty || refusal != null
                      ? null
                      : () async => create(),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// "New group": a folder, in a popover off the header. The folder gets a
/// `scenes.dart` skeleton and is a group from then on.
class _NewGroupButton extends StatefulWidget {
  const _NewGroupButton({required this.taken, required this.onCreate});

  final Set<String> taken;
  final void Function(String folder) onCreate;

  @override
  State<_NewGroupButton> createState() => _NewGroupButtonState();
}

class _NewGroupButtonState extends State<_NewGroupButton> {
  final _folder = TextEditingController(text: 'lib/scenes/');

  @override
  void dispose() {
    _folder.dispose();
    super.dispose();
  }

  String? get _refusal {
    var folder = _folder.text.trim();
    if (folder.isEmpty || folder == 'lib/scenes/') return null;
    if (folder.startsWith('/') || folder.contains('..')) {
      return 'A folder inside the package';
    }
    if (widget.taken.contains(p.basename(folder))) {
      return 'There is a ${p.basename(folder)} group already';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) => Popover(
    anchor: (context, controller) => FwActionButton(
      label: 'New group',
      tooltip: 'A folder for scenes, with its $sceneGroupFileName',
      onPressed: () async => controller.open(),
    ),
    side: PopoverSide.bottom,
    align: PopoverAlign.end,
    content: (context, controller) => _form(context, controller),
  );

  Widget _form(BuildContext context, PopoverController controller) {
    var colors = context.colors;
    return Container(
      width: 300,
      padding: const EdgeInsets.all(FwSpacing.lg),
      decoration: BoxDecoration(
        color: colors.panel,
        border: Border.all(color: colors.line),
        borderRadius: BorderRadius.circular(context.radii.radius),
        boxShadow: context.elevation.sm,
      ),
      child: StatefulBuilder(
        builder: (context, rebuild) {
          var refusal = _refusal;
          var folder = _folder.text.trim();
          var ready =
              folder.isNotEmpty && folder != 'lib/scenes/' && refusal == null;
          void create() {
            if (!ready) return;
            controller.close();
            widget.onCreate(folder.replaceAll(RegExp(r'/+$'), ''));
            _folder.text = 'lib/scenes/';
          }

          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: FwSpacing.md,
            children: [
              Text('New group', style: context.type.bodyStrong),
              Text(
                'A folder, relative to the package. Its name is the '
                "group's; its scenes are the files below it.",
                style: context.type.caption.copyWith(color: colors.mut2),
              ),
              TextField(
                controller: _folder,
                autofocus: true,
                style: context.type.mono,
                decoration: const InputDecoration(
                  hintText: 'lib/scenes/marketing',
                ),
                onChanged: (_) => rebuild(() {}),
                onSubmitted: (_) => create(),
              ),
              if (refusal != null)
                Text(
                  refusal,
                  style: context.type.caption.copyWith(color: colors.red),
                ),
              Align(
                alignment: Alignment.centerRight,
                child: FwActionButton(
                  label: 'Create',
                  primary: true,
                  onPressed: ready ? () async => create() : null,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// "New library": a name, a folder, and optionally the group to list it
/// in. The file is the editor's own from its first byte.
class _NewLibraryButton extends StatefulWidget {
  const _NewLibraryButton({
    required this.groups,
    required this.defaultFolder,
    required this.folderOf,
    required this.onCreate,
  });

  final List<SceneGroupEntry> groups;
  final String defaultFolder;

  /// A group's folder relative to the package — what the folder field
  /// takes when a group is picked.
  final String Function(SceneGroupEntry group) folderOf;
  final void Function(String name, String folder, SceneGroupEntry? attachTo)
  onCreate;

  @override
  State<_NewLibraryButton> createState() => _NewLibraryButtonState();
}

class _NewLibraryButtonState extends State<_NewLibraryButton> {
  final _name = TextEditingController();
  late final _folder = TextEditingController(text: widget.defaultFolder);
  int? _group;

  @override
  void dispose() {
    _name.dispose();
    _folder.dispose();
    super.dispose();
  }

  String? get _refusal {
    var name = _name.text.trim();
    if (name.isEmpty) return null;
    if (!RegExp(r'^[A-Za-z][A-Za-z0-9 _-]*$').hasMatch(name)) {
      return 'A name: letters and digits';
    }
    var folder = _folder.text.trim();
    if (folder.startsWith('/') || folder.contains('..')) {
      return 'A folder inside the package';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) => Popover(
    anchor: (context, controller) => FwActionButton(
      label: 'New library',
      tooltip: 'A token library the editor owns',
      onPressed: () async => controller.open(),
    ),
    side: PopoverSide.bottom,
    align: PopoverAlign.end,
    content: (context, controller) => _form(context, controller),
  );

  Widget _form(BuildContext context, PopoverController controller) {
    var colors = context.colors;
    return Container(
      width: 300,
      padding: const EdgeInsets.all(FwSpacing.lg),
      decoration: BoxDecoration(
        color: colors.panel,
        border: Border.all(color: colors.line),
        borderRadius: BorderRadius.circular(context.radii.radius),
        boxShadow: context.elevation.sm,
      ),
      child: StatefulBuilder(
        builder: (context, rebuild) {
          var refusal = _refusal;
          var name = _name.text.trim();
          var ready = name.isNotEmpty && refusal == null;
          void create() {
            if (!ready) return;
            controller.close();
            var group = _group == null ? null : widget.groups[_group!];
            widget.onCreate(
              name,
              _folder.text.trim().isEmpty ? '.' : _folder.text.trim(),
              group,
            );
            _name.clear();
          }

          var file = name.isEmpty ? '' : tokensFileNameFor(name);
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: FwSpacing.md,
            children: [
              Text('New library', style: context.type.bodyStrong),
              TextField(
                controller: _name,
                autofocus: true,
                decoration: const InputDecoration(hintText: 'Brand'),
                onChanged: (_) => rebuild(() {}),
                onSubmitted: (_) => create(),
              ),
              TextField(
                controller: _folder,
                style: context.type.mono,
                decoration: const InputDecoration(hintText: 'lib/design'),
                onChanged: (_) => rebuild(() {}),
                onSubmitted: (_) => create(),
              ),
              if (file.isNotEmpty)
                Text(
                  '${_folder.text.trim()}/$file · ${tokensSymbolFor(file)}',
                  style: context.type.caption.copyWith(color: colors.mut2),
                ),
              if (widget.groups.isNotEmpty)
                FwPicker<int>(
                  choices: [
                    const FwChoice(value: -1, label: 'Listed by no group yet'),
                    for (var (i, g) in widget.groups.indexed)
                      FwChoice(value: i, label: 'List in ${g.name}'),
                  ],
                  selected: _group ?? -1,
                  onChanged: (i) => rebuild(() {
                    _group = i < 0 ? null : i;
                    if (i >= 0) {
                      _folder.text = widget.folderOf(widget.groups[i]);
                    }
                  }),
                ),
              if (refusal != null)
                Text(
                  refusal,
                  style: context.type.caption.copyWith(color: colors.red),
                ),
              Align(
                alignment: Alignment.centerRight,
                child: FwActionButton(
                  label: 'Create',
                  primary: true,
                  onPressed: ready ? () async => create() : null,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
