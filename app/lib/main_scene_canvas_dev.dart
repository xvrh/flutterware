// Disposable spike: the composited canvas — the canvas toy's editor with the
// scene rendered by an embedder guest, composited into this window as an
// external texture. The question it answers: does drag feel instant through
// editor → data push → guest frame → texture, or is there unfixable lag?
//
// The guest is the example package's 'Scene canvas host' preview entry,
// booted by the same CatalogSession the previews and motion panels use.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import 'canvas_toy/main.dart';
import 'canvas_toy/model.dart';
import 'src/embedder/embedded_engine.dart';
import 'src/embedder/guest_texture.dart';
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
  final doc = coffeeBannerDraft();
  final status = ValueNotifier('guest: booting…');
  late final CatalogSession session;

  var _inflight = false;
  var _dirty = false;
  var _everApplied = false;
  Timer? _retry;
  Size? _resized;

  @override
  void initState() {
    super.initState();
    var worktree = p.normalize(p.join(widget.appRoot, '..'));
    session = CatalogSession(
      appPackageRoot: widget.appRoot,
      flutterSdkRoot: widget.flutterSdkRoot,
      projectRoot: p.join(worktree, 'examples', 'example'),
      worktreeRoot: worktree,
      connectToDaemon: CompilerDaemonClient.connect,
    )..addListener(_onSession);
    unawaited(session.start(width: 2048, height: 1000));
    doc.addListener(_push);
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
            args: {'scene': jsonEncode(doc.toJson())},
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
        var rect = Rect.fromLTWH(
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
        body: AnimatedBuilder(
          animation: doc,
          builder: (context, _) => Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(width: 230, child: TreePanel(doc)),
              const VerticalDivider(width: 1),
              Expanded(
                child: CanvasArea(
                  doc,
                  status: status,
                  canvasContent: _guestCanvas(),
                ),
              ),
              const VerticalDivider(width: 1),
              SizedBox(width: 290, child: InspectorPanel(doc)),
            ],
          ),
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
