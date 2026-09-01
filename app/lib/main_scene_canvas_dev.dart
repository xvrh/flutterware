// Disposable spike: the composited canvas — the canvas toy's editor with the
// scene rendered by an embedder guest, composited into this window as an
// external texture. The question it answers: does drag feel instant through
// editor → data push → guest frame → texture, or is there unfixable lag?
//
// The guest is the example package's 'Scene canvas host' preview entry,
// booted by the same CatalogSession the previews and motion panels use.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import 'package:flutterware/scene.dart';
import 'package:flutterware/scene_authoring.dart';

import 'canvas_toy/drafts.dart';
import 'canvas_toy/main.dart';
import 'src/scene/editor.dart';
import 'src/embedder/embedded_engine.dart';
import 'src/embedder/guest_texture.dart';
import 'src/scene/motion_file.dart';
import 'src/scene/scene_file.dart';
import 'src/previews/catalog_session.dart';
import 'src/previews/compiler_daemon_client.dart';

const _appRootDefine = String.fromEnvironment('FLUTTERWARE_APP_ROOT');
const _sdkRootDefine = String.fromEnvironment('FLUTTER_SDK_ROOT');

Future<void> main({String? flutterSdkRoot, String? appRoot}) async {
  WidgetsFlutterBinding.ensureInitialized();
  var sdk = flutterSdkRoot ?? _sdkRootDefine;
  var app = appRoot ?? _appRootDefine;
  runApp(
    sdk.isEmpty || app.isEmpty
        ? const _MissingKnobs()
        : SceneCanvasDevApp(flutterSdkRoot: sdk, appRoot: app),
  );
}

class _MissingKnobs extends StatelessWidget {
  const _MissingKnobs();

  @override
  Widget build(BuildContext context) => const MaterialApp(
    home: Scaffold(
      body: Center(
        child: Text(
          'Needs flutterSdkRoot and appRoot — launch through flutterware '
          '(the SDK knob fills itself) and pass appRoot=<worktree>/app.',
        ),
      ),
    ),
  );
}

class SceneCanvasDevApp extends StatefulWidget {
  const SceneCanvasDevApp({
    super.key,
    required this.flutterSdkRoot,
    required this.appRoot,
  });

  final String flutterSdkRoot;
  final String appRoot;

  @override
  State<SceneCanvasDevApp> createState() => _SceneCanvasDevAppState();
}

class _SceneCanvasDevAppState extends State<SceneCanvasDevApp> {
  late final SceneDocument doc;
  late final editor = SceneEditor(doc);
  final status = ValueNotifier('guest: booting…');
  late final CatalogSession session;
  late final String _scenePath;
  late final String _motionPath;
  var _fileNote = '';
  var _sceneClassName = 'BannerScene';
  MotionDocument? _motion;

  var _inflight = false;
  var _dirty = false;
  var _everApplied = false;
  Timer? _retry;
  Size? _resized;

  @override
  void initState() {
    super.initState();
    installSceneFrameFlush();
    var worktree = p.normalize(p.join(widget.appRoot, '..'));
    var projectRoot = p.join(worktree, 'examples', 'example');
    _scenePath = p.join(projectRoot, 'demo', 'banner.scene.dart');
    _motionPath = p.join(projectRoot, 'demo', 'banner_intro.motion.dart');
    doc = _loadOrDraft();
    _motion = _loadMotion();
    session = CatalogSession(
      appPackageRoot: widget.appRoot,
      flutterSdkRoot: widget.flutterSdkRoot,
      projectRoot: projectRoot,
      worktreeRoot: worktree,
      connectToDaemon: CompilerDaemonClient.connect,
    )..addListener(_onSession);
    unawaited(session.start(width: 2048, height: 1000));
    doc.addListener(_push);
    editor.addListener(_push);
    // Until the guest's extension is registered (entry selected, first build),
    // pushes fail; retry until the first one lands.
    _retry = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (_everApplied) {
        _retry?.cancel();
      } else {
        _push();
      }
    });
  }

  /// Load the persisted scene through the parse door, or fall back to the
  /// hard-coded draft. Refusals are the collecting kind: all printed, and the
  /// file yields no document.
  SceneDocument _loadOrDraft() {
    var file = File(_scenePath);
    if (!file.existsSync()) {
      _fileNote = 'no ${p.basename(_scenePath)} yet — using the draft';
      return coffeeBannerDraft();
    }
    var parsed = parseSceneFile(file.readAsStringSync());
    if (parsed.ok) {
      _fileNote = 'loaded ${p.basename(_scenePath)} (${parsed.className})';
      _sceneClassName = parsed.className!;
      return parsed.doc!;
    }
    _fileNote =
        '${p.basename(_scenePath)}: ${parsed.refusals.length} refusal(s) — '
        'using the draft';
    for (var refusal in parsed.refusals) {
      print('scene refusal: $refusal');
    }
    return coffeeBannerDraft();
  }

  /// The motion beside the scene, through its own parse door — the pair is
  /// read together (targets resolve against [doc]). No file, or a refused
  /// one, falls back to the hard-coded draft intro so play always exists.
  MotionDocument? _loadMotion() {
    var file = File(_motionPath);
    if (!file.existsSync()) return coffeeIntroDraft();
    var parsed = parseMotionFile(
      file.readAsStringSync(),
      scene: doc,
      sceneClassName: _sceneClassName,
    );
    if (parsed.ok) {
      _fileNote += ' · ${p.basename(_motionPath)} (${parsed.className})';
      return parsed.doc!;
    }
    _fileNote +=
        ' · ${p.basename(_motionPath)}: ${parsed.refusals.length} '
        'refusal(s) — using the draft intro';
    for (var refusal in parsed.refusals) {
      print('motion refusal: $refusal');
    }
    return coffeeIntroDraft();
  }

  void _save() {
    var emitted = emitSceneFile(doc, className: 'BannerScene');
    // The door works both ways: never write a file the parser would refuse.
    var check = parseSceneFile(emitted);
    if (!check.ok) {
      setState(() => _fileNote = 'not saved — emit refused its own output');
      for (var refusal in check.refusals) {
        print('scene refusal: $refusal');
      }
      return;
    }
    File(_scenePath).writeAsStringSync(emitted);
    var nodes = doc.walk().length;
    setState(
      () => _fileNote = 'saved ${p.basename(_scenePath)} · $nodes nodes',
    );
  }

  void _onSession() {
    if (!mounted) return;
    if (session.phase == CatalogSessionPhase.ready &&
        session.wantedEntryId == null) {
      for (var entry in session.entries) {
        if (entry.symbol == 'sceneCanvasHost') {
          session.wantedEntryId = entry.id;
          break;
        }
      }
      if (session.wantedEntryId == null) {
        status.value = 'guest: no "Scene canvas host" entry in the catalog';
      }
    }
    setState(() {});
  }

  void _push() {
    if (_inflight) {
      _dirty = true;
      return;
    }
    _inflight = true;
    var clock = Stopwatch()..start();
    unawaited(
      session
          .callGuestExtension(
            'ext.fw.scene.apply',
            args: {
              'scene': jsonEncode(doc.toJson(selected: editor.selectionNames)),
            },
          )
          .then((reply) {
            var rtt = clock.elapsedMicroseconds / 1000;
            if (reply != null && reply['error'] == null) {
              _everApplied = true;
              var frameMs = (reply['frameMs'] as num?)?.toDouble();
              _applyRects((reply['rects'] as Map?)?.cast<String, dynamic>());
              status.value =
                  'guest ✓ ${rtt.toStringAsFixed(1)}ms rtt'
                  ' · ${frameMs?.toStringAsFixed(1)}ms frame';
            } else if (reply != null) {
              status.value = 'guest: ${reply['error']}';
            }
          })
          .catchError((Object e) {
            if (_everApplied) status.value = 'guest: push failed';
          })
          .whenComplete(() {
            _inflight = false;
            if (_dirty) {
              _dirty = false;
              _push();
            }
          }),
    );
  }

  /// The guest is the only renderer, so its laid-out rects are the editor's
  /// geometry: selection, hit targets and handles all read what it measured.
  void _applyRects(Map<String, dynamic>? rects) {
    if (rects == null) return;
    var changed = false;
    for (var (node, _) in doc.walk()) {
      var raw = rects[node.name];
      if (raw is List && raw.length == 4) {
        var rect = SceneRect(
          (raw[0] as num).toDouble(),
          (raw[1] as num).toDouble(),
          (raw[2] as num).toDouble(),
          (raw[3] as num).toDouble(),
        );
        if (node.measured != rect) {
          node.measured = rect;
          changed = true;
        }
      }
    }
    if (changed) doc.geometryEpoch.value++;
  }

  @override
  void dispose() {
    _retry?.cancel();
    doc.removeListener(_push);
    editor.removeListener(_push);
    session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Scene canvas (spike)',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF4A64D0)),
        visualDensity: VisualDensity.compact,
      ),
      home: Scaffold(
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: [
                  FilledButton.tonal(
                    onPressed: _save,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      minimumSize: const Size(0, 28),
                    ),
                    child: const Text('Save', style: TextStyle(fontSize: 12)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _fileNote,
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            if (_motion case var motion?) ...[
              MotionTransport(doc, motion),
              const Divider(height: 1),
            ],
            Expanded(
              child: AnimatedBuilder(
                animation: Listenable.merge([
                  doc.listenable,
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
                                status: status,
                                canvasContent: _guestCanvas(),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const VerticalDivider(width: 1),
                    SizedBox(width: 290, child: InspectorPanel(editor)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The artboard's picture is the guest's texture, sized to the artboard so
  /// editor coordinates and guest coordinates are the same space.
  Widget _guestCanvas() {
    var width = doc.root.width ?? 1024;
    var height = doc.root.height ?? 500;
    return SizedBox(
      width: width,
      height: height,
      child: AnimatedBuilder(
        animation: session,
        builder: (context, _) {
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
          var size = Size(width, height);
          if (_resized != size) {
            _resized = size;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              engine.resize((width * dpr).round(), (height * dpr).round(), dpr);
            });
          }
          return GuestTexture(textureId: engine.textureId!);
        },
      ),
    );
  }
}
