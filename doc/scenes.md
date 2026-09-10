# Scenes

> Scenes are new and still changing. The editor works, but the file format and
> the Dart API may move between releases.

Design animated graphics in the studio, with your app's own widgets and
theme, and play them in your app or export them to video: an onboarding
animation, a promo banner, the video for a store listing.

A scene is a design (shapes, text, images, your widgets) plus the motion that
animates it, stored in one Dart file per scene. The studio's editor writes the
file, and your app renders it.

## Turn it on

```dart
// tool/flutterware.dart
fw.use(Scene(packages: [.new(app)]));
```

Scenes live in folders. A folder holds scenes when it has a `scenes.dart` in
it, which says what those scenes may use:

- **widgets**: widgets from your app a scene can place, with the arguments the
  editor can change,
- **libraries**: token files (`*.tokens.dart`) with the colours, numbers and
  text styles your designs share,
- **wrap**: what the canvas is mounted under, usually your app's theme.

Create the first scene from the studio's **New scene** button, or:

```shell
fw run scene newScene --name='Promo banner' --folder=demo
```

This writes the scene file, and the folder's `scenes.dart` if it doesn't exist
yet.

## The editor

- A canvas with the scene's layers, and a properties panel that shows where
  each value comes from, whether it was set on the layer or taken from a
  token.
- A timeline that animates the scene's values over time.
- Token libraries edited on their own page. `fw run scene importTokens` merges
  in the variables exported from a design tool.

Changes are saved as you go. A scene file edited outside the studio is picked
up again.

## Use it in your app

A scene file holds a Dart class named after the scene, so your app shows it
with `SceneView`:

```dart
import 'package:flutterware/scene.dart';

import 'promo_banner.scene.dart';

Widget build(BuildContext context) => SceneView(PromoBanner());
```

## Export to video

```shell
fw run scene video --scene=PromoBanner --fps=60
```

Renders the scene's motion to an MP4, one frame per moment, drawn by your app.
`--scene` takes the scene's class name. It needs `ffmpeg` on the machine, and a
scene with no motion is refused, since its video would be one frame.

## Reference

[`flutterware.scene` in the capabilities reference](../docs/capabilities.md#flutterwarescene).
