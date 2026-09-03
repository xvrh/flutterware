import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../address/address_scope.dart';
import '../../embedder/embedded_engine.dart';
import '../../embedder/guest_texture.dart';
import '../../previews/catalog_session.dart';
import '../../previews/compiler_daemon_client.dart';

import 'package:flutterware/scene_authoring.dart';

import '../../scene/discovery.dart';
import '../../scene/autosave.dart';
import '../../scene/editor.dart';
import '../../scene/guest.dart';
import '../../scene/scene_file.dart';
import '../../scene/playback.dart';
import '../../scene/ui/workspace_view.dart';
import '../../scene/watch.dart';
import '../../scene/workspace.dart';
import '../../ui/action_button.dart';
import '../../ui/count_badge.dart';
import '../../ui/design/design.dart';
import '../../ui/empty_state.dart';
import '../../ui/loading_state.dart';
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
    _watchDirectory();
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
    if (file == null || package == null) return;
    _guest?.dispose();
    _guest = SceneGuest(widget.plugin.sessionFor(package), file.editor);
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
    _workspace = null;
    _note = '';
  }

  void _open(SceneEntry entry) {
    var opened = SceneFile.open(
      entry.path,
      File(entry.path).readAsStringSync(),
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
      _workspace = SceneWorkspace(file, resolveNested: _resolveNested);
      _guest = SceneGuest(widget.plugin.sessionFor(_package!), file.editor);
      _note = '';
    });
    _autosave.bind(_workspace);
  }

  /// Starts (or re-points) the watch on the package's scene directory.
  void _watchDirectory() {
    var package = _package;
    if (package == null) return;
    var directory = _core.rootFor(package);
    if (_watching == directory && _watcher?.isWatching == true) return;
    _watcher?.dispose();
    _watching = directory;
    _watcher = SceneWatcher(directory: directory, onChanged: _onDiskChanged)
      ..start();
  }

  /// Scene files moved on disk. The listing is refreshed either way; an open
  /// file is adopted when this editor has nothing of its own to lose, and
  /// held otherwise.
  void _onDiskChanged(Set<String> paths) {
    if (!mounted) return;
    var package = _package;
    if (package != null) _core.rescan(package);
    var workspace = _workspace;
    if (workspace == null) {
      setState(() {});
      return;
    }
    var adopted = <String>[];
    var refused = <String>[];
    var held = <String>[];
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
      var refusals = file.adopt(source);
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
  /// `<snake_name>.scene.dart` in the package's scene directory, and opens
  /// it. The emitter writes it, so a file made here is canonical from its
  /// first byte.
  void _createScene(
    String package,
    String className,
    double width,
    double height,
  ) {
    var root = FrameNode('root')
      ..width = width
      ..height = height
      ..fill = const SceneColor(0xFFFFFFFF);
    var source = emitSceneFile(SceneDocument(root), className: className);
    var dir = p.join(
      widget.plugin.host.worktree.path,
      package,
      _core.directoryFor(package),
    );
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

  /// A nested scene is another scene file of the same package, found by the
  /// class it declares. Opened fresh here; the workspace keeps the one copy
  /// it already holds, so edits inside a child are not lost to a re-resolve.
  SceneFile? _resolveNested(SceneNode node) {
    if (node is! SceneRefNode) return null;
    var package = _package;
    if (package == null) return null;
    for (var entry in _core.scenesFor(package) ?? const <SceneEntry>[]) {
      if (entry.className != node.sceneClassName) continue;
      var opened = SceneFile.open(
        entry.path,
        File(entry.path).readAsStringSync(),
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
    if (workspace == null || package == null) return;
    if (_guest?.editor == workspace.editor) return;
    _guest?.dispose();
    _guest = SceneGuest(widget.plugin.sessionFor(package), workspace.editor);
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
    // Both are cheap when nothing moved, and doing them here rather than only
    // where the workspace is assigned is what makes them survive a hot
    // reload — the panel's state object outlives one, its fields do not.
    _autosave.bind(_workspace);
    _watchDirectory();
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
    var scenes = _core.scenesFor(package);
    if (scenes == null) return const LoadingState(title: 'Looking for scenes');
    var colors = context.colors;
    var type = context.type;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FwPanelHeader(
          'Scenes',
          subtitle: ['$package/${_core.directoryFor(package)}'],
          badge: scenes.isEmpty ? null : CountBadge(scenes.length),
          trailing: _NewSceneButton(
            taken: {for (var s in scenes) s.className},
            onCreate: (className, width, height) =>
                _createScene(package, className, width, height),
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
        if (scenes.isEmpty)
          Expanded(
            child: EmptyState(
              icon: Icons.movie_filter_outlined,
              title: 'No scenes here',
              message:
                  'A scene file is one this tool writes, marked in its first '
                  'line. None under ${_core.directoryFor(package)}/ yet.',
            ),
          )
        else
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: FwSpacing.xs),
              children: [
                for (var scene in scenes)
                  Tappable(
                    onTap: () => _open(scene),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: FwSpacing.xl,
                        vertical: FwSpacing.md,
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
                                  style: type.caption.copyWith(
                                    color: colors.mut2,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
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
  Widget _guestPane(BuildContext context, Matrix4 view, Size pane) {
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
        guest?.setView(view);
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
    required this.note,
    required this.saveState,
    required this.onBack,
    required this.onCrumb,
    required this.onSave,
  });

  final SceneWorkspace workspace;
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
          // The breadcrumb: one crumb today, a drill-in path once a nested
          // scene can be entered. The last is where you are, so it is not a
          // link.
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
