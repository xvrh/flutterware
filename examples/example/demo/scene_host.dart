// The scene rendered where the app lives.
//
// This is what "the guest is the only renderer" means concretely: the editor
// sends the scene as *data* over a VM-service extension, and this app draws it
// with `SceneView` — its own theme, its own widgets, its own fonts — then
// reports back what the layout measured, which is where the editor's selection
// rectangles and drag targets come from.
//
// The app's part is small on purpose: declare the widgets a scene may place,
// and mount the host. Everything else is flutterware's.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutterware/scene.dart';
import 'package:flutterware/scene_authoring.dart';

import 'scene_externals.dart';

void main() {
  runApp(const SceneHostApp());
}

/// A scene and its motion, played from the file the editor wrote — the shape
/// an export walks.
///
/// The knob carries a path rather than the document itself: a scene is
/// kilobytes of JSON, and a walk asks for it once. Mounting `SceneView` with
/// a bound motion is what registers the playhead the harness drives, so every
/// stop of the clip is `evaluate(t)` and nothing else.
class ScenePlayerHost extends StatelessWidget {
  const ScenePlayerHost({super.key, required this.pairPath});

  final String pairPath;

  @override
  Widget build(BuildContext context) {
    if (pairPath.isEmpty) {
      return const _Waiting('scene player — no pair given');
    }
    var file = File(pairPath);
    if (!file.existsSync()) return _Waiting('no such pair: $pairPath');
    var pair = sceneFileFromJson(
      jsonDecode(file.readAsStringSync()) as Map<String, Object?>,
    );
    var motion = pair.motions.values.firstOrNull;
    // The pair came off disk as data, so its external nodes carry a label
    // and no generated class. This is what turns the label back into a
    // widget; a scene the app COMPILED needs none of it.
    bindExternals(pair.scene, sceneExternals);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: const Color(0xFF8C5A3C)),
      home: Align(
        alignment: Alignment.topLeft,
        child: SceneView.document(
          pair.scene,
          motion: motion == null ? null : BoundMotion.bind(motion, pair.scene),
        ),
      ),
    );
  }
}

class _Waiting extends StatelessWidget {
  const _Waiting(this.message);

  final String message;

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    home: ColoredBox(
      color: const Color(0xFF26282C),
      child: Center(
        child: Text(message, style: const TextStyle(color: Colors.white54)),
      ),
    ),
  );
}

/// The scene canvas, under this app's theme. Everything else — the
/// extension the editor calls, the view it asks for, the rects it wants back
/// — is [SceneCanvasHost]'s.
class SceneHostApp extends StatelessWidget {
  const SceneHostApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Scene host',
    debugShowCheckedModeBanner: false,
    // The app's own look — what the editor canvas inherits by construction.
    theme: ThemeData(colorSchemeSeed: const Color(0xFF8C5A3C)),
    home: SceneCanvasHost(externals: sceneExternals),
  );
}
