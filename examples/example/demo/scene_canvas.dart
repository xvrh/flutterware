import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

import 'scene_host.dart';

/// The scene renderer as a preview entry, so the studio's embedder machinery
/// can boot it — the composited-canvas spike's guest half. Bare: the window
/// is the artboard, and the mounting panel owns the pipe.
@Preview(name: 'Scene canvas host')
Widget sceneCanvasHost() => const SceneHostApp(bare: true);
