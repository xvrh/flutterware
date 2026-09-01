import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutterware/scene.dart';
import 'package:path/path.dart' as p;

import '../../address/address_scope.dart';
import '../../../canvas_toy/main.dart';
import '../../embedder/embedded_engine.dart';
import '../../embedder/guest_texture.dart';
import '../../previews/catalog_session.dart';
import '../../previews/compiler_daemon_client.dart';
import '../../scene/discovery.dart';
import '../../scene/guest.dart';
import '../../scene/ui/inspector.dart';
import '../../scene/ui/shortcuts.dart';
import '../../scene/workspace.dart';
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

class _ScenePanelState extends State<_ScenePanel> {
  String? _tracked;
  String? _package;

  /// The open file, and the guest rendering it. Null until a scene is
  /// picked: booting a guest is expensive and a listing needs none.
  SceneWorkspace? _workspace;
  SceneGuest? _guest;
  String _note = '';

  SceneCore get _core => widget.plugin.core;

  String? _resolve() =>
      AddressScope.segment(context, 0) ?? _core.packages.firstOrNull;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _package = _resolve();
    _retrack();
  }

  void _retrack() {
    var wanted = _package;
    if (wanted == _tracked) return;
    _tracked = wanted;
    _close();
    if (wanted != null) _core.track(wanted);
  }

  void _close() {
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
      _workspace = SceneWorkspace(file);
      _guest = SceneGuest(widget.plugin.sessionFor(_package!), file.editor);
      _note =
          'open · ${file.className}'
          '${file.motions.isEmpty ? '' : ' · ${file.motions.keys.join(', ')}'}';
    });
  }

  void _save() {
    var file = _workspace!.active;
    var refusals = file.save(
      (path, source) => File(path).writeAsStringSync(source),
    );
    setState(() {
      _note = refusals.isEmpty
          ? 'saved ${p.basename(file.path)} · ${file.scene.walk().length} nodes'
          : 'not saved — emit refused its own output (${refusals.first})';
    });
  }

  @override
  void dispose() {
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
    if (scenes == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (scenes.isEmpty) {
      return Center(
        child: Text(
          'No scenes in ${_core.directoryFor(package)}/ — a scene file is one '
          'this tool writes, marked in its first line.',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_note.isNotEmpty)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              _note,
              style: const TextStyle(fontSize: 12, color: Colors.redAccent),
            ),
          ),
        Expanded(
          child: ListView(
            children: [
              // A plain tappable row rather than a ListTile: the shell paints
              // the panel's background itself, and a ListTile inside that
              // hides its own ink.
              for (var scene in scenes)
                InkWell(
                  onTap: () => _open(scene),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.movie_filter_outlined, size: 16),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                scene.className,
                                style: const TextStyle(fontSize: 13),
                              ),
                              Text(
                                p.relative(
                                  scene.path,
                                  from: widget.plugin.host.worktree.path,
                                ),
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey,
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              IconButton(
                iconSize: 16,
                visualDensity: VisualDensity.compact,
                tooltip: 'Back to the scenes',
                icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(_close),
              ),
              // The breadcrumb: one crumb today, a drill-in path once a
              // nested scene can be entered.
              for (var (index, crumb) in workspace.crumbs.indexed) ...[
                if (index > 0) const Text(' › '),
                TextButton(
                  onPressed: () => setState(() => workspace.goTo(index)),
                  child: Text(
                    crumb.file.className,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
              const SizedBox(width: 8),
              FilledButton.tonal(
                onPressed: _save,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  minimumSize: const Size(0, 28),
                ),
                child: Text(
                  workspace.active.isDirty ? 'Save •' : 'Save',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _note,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        if (workspace.active.motions.values.firstOrNull case var motion?) ...[
          MotionTransport(workspace.active.scene, motion),
          const Divider(height: 1),
        ],
        Expanded(
          child: AnimatedBuilder(
            animation: Listenable.merge([
              workspace.active.scene.listenable,
              editor.listenable,
            ]),
            builder: (context, _) => Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: EditorShortcuts(
                    editor,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(width: 230, child: TreePanel(editor)),
                        const VerticalDivider(width: 1),
                        Expanded(
                          child: CanvasArea(
                            editor,
                            status: _guest?.status,
                            canvasContent: _guestCanvas(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const VerticalDivider(width: 1),
                SizedBox(width: 290, child: SceneInspector(editor)),
              ],
            ),
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
