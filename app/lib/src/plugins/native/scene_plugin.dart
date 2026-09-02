import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../address/address_scope.dart';
import '../../embedder/embedded_engine.dart';
import '../../embedder/guest_texture.dart';
import '../../previews/catalog_session.dart';
import '../../previews/compiler_daemon_client.dart';

import 'package:flutterware/scene_authoring.dart';

import '../../scene/discovery.dart';
import '../../scene/editor.dart';
import '../../scene/guest.dart';
import '../../scene/playback.dart';
import '../../scene/ui/workspace_view.dart';
import '../../scene/workspace.dart';
import '../../ui/action_button.dart';
import '../../ui/count_badge.dart';
import '../../ui/design/design.dart';
import '../../ui/empty_state.dart';
import '../../ui/loading_state.dart';
import '../../ui/panel_header.dart';
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
    with TickerProviderStateMixin {
  String? _tracked;
  String? _package;

  /// The open file, and the guest rendering it. Null until a scene is
  /// picked: booting a guest is expensive and a listing needs none.
  SceneWorkspace? _workspace;
  SceneGuest? _guest;
  String _note = '';

  /// One playback per file that has a motion, made the first time that file
  /// is the active one — the nested scene entered later gets its own.
  final _playbacks = <String, ScenePlayback>{};

  ScenePlayback? _playbackFor(SceneFile file) {
    var motion = file.motions.keys.firstOrNull;
    if (motion == null) return null;
    return _playbacks.putIfAbsent(
      file.path,
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
    if (file == null || package == null) return;
    _guest?.dispose();
    _guest = SceneGuest(widget.plugin.sessionFor(package), file.editor);
    // The new engine started at the session's default size; forget the
    // old one's, or the artboard draws at half scale in a texture nobody
    // resized.
    _resized = null;
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
  }

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
    _resized = null;
  }

  /// Writes every dirty file the workspace holds — the one on screen and any
  /// nested scene edited on the way here — so a drill-in never leaves work
  /// behind in a file the breadcrumb no longer shows.
  void _save() {
    var workspace = _workspace!;
    var saved = <String>[];
    var refused = <String>[];
    for (var file in workspace.dirtyFiles.toList()) {
      var refusals = file.save(
        (path, source) => File(path).writeAsStringSync(source),
      );
      if (refusals.isEmpty) {
        saved.add(p.basename(file.path));
      } else {
        refused.add('${p.basename(file.path)}: ${refusals.first}');
      }
    }
    setState(() {
      _note = refused.isNotEmpty
          ? 'not saved — emit refused its own output (${refused.join('; ')})'
          : saved.isEmpty
          ? 'nothing to save'
          : 'saved ${saved.join(', ')}';
    });
  }

  @override
  void dispose() {
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
          note: _note,
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
            playback: _playbackFor(workspace.active),
            content: _guestCanvas(),
            status: _guest?.status,
            onEnterNested: (node) => setState(() {
              workspace.enter(node);
              _syncGuest();
            }),
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
  Widget _guestCanvas() {
    var scene = _workspace!.active.scene;
    var width = scene.root.width ?? 1024;
    var height = scene.root.height ?? 500;
    return SizedBox(
      width: width,
      height: height,
      child: AnimatedBuilder(
        animation: widget.plugin.sessionFor(_package!),
        builder: (context, _) {
          var session = widget.plugin.sessionFor(_package!);
          var engine = session.engine;
          if (engine == null ||
              engine.phase != EmbeddedEnginePhase.running ||
              engine.textureId == null) {
            return Container(
              color: const Color(0xFF26282C),
              alignment: Alignment.center,
              child: Text(
                session.phase == CatalogSessionPhase.error
                    ? 'session error'
                    : 'booting the guest… (${session.busyWith ?? 'starting'})',
                style: const TextStyle(color: Colors.white54),
              ),
            );
          }
          var dpr = MediaQuery.of(context).devicePixelRatio;
          if (_resized != Size(width, height)) {
            _resized = Size(width, height);
            WidgetsBinding.instance.addPostFrameCallback((_) {
              engine.resize((width * dpr).round(), (height * dpr).round(), dpr);
            });
          }
          return GuestTexture(textureId: engine.textureId!);
        },
      ),
    );
  }

  Size? _resized;
}

/// Back, the breadcrumb, Save, and what the panel last did.
class _Header extends StatelessWidget {
  const _Header({
    required this.workspace,
    required this.note,
    required this.onBack,
    required this.onCrumb,
    required this.onSave,
  });

  final SceneWorkspace workspace;
  final String note;
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
          FwActionButton(
            label: workspace.anyDirty ? 'Save •' : 'Save',
            primary: workspace.anyDirty,
            tooltip: workspace.dirtyFiles.length > 1
                ? 'Write ${workspace.dirtyFiles.length} scene files (⌘S)'
                : 'Write the scene file (⌘S)',
            onPressed: () async => onSave(),
          ),
          Expanded(
            child: Text(
              note,
              style: type.caption.copyWith(color: colors.mut2),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
