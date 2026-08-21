import 'dart:ui' as ui;

import 'package:flutter/material.dart';
// ignore: implementation_imports
import 'package:flutterware/src/inspect/node.dart';

import '../inspect/node_highlight.dart';
import '../ui/design/design.dart';
import '../ui/theme.dart';

/// The picture, and the caption that goes with it.
///
/// The caption is tied to the decoded frame rather than to the bytes. It used
/// to be tied to `image != null`, and that misreported for as long as
/// the decode took: `Image.memory` resolves *asynchronously*, and a
/// `RenderImage` with nothing to draw yet takes `constraints.smallest` — zero,
/// under the loose constraints this column hands it. So the caption drew,
/// slid up to where the picture should have been, and described a picture that
/// was not on screen. Measured on macOS: 103ms against a painting app, and
/// unbounded against one that is not painting — a hidden or occluded window
/// schedules no frame, so the decoded picture had nothing to arrive on. That is
/// the state a Studio is in for the whole of an agent's drive session.
///
/// Handing it an already-decoded [ui.Image] removes the window rather than
/// narrowing it: there is no moment where this widget has bytes and no picture.
class RunScreenPicture extends StatelessWidget {
  const RunScreenPicture({
    super.key,
    required this.picture,
    required this.undecodable,
    required this.loading,
    required this.highlight,
    required this.tree,
    required this.canvas,
  });

  final ui.Image? picture;

  /// The app answered with bytes that are not an image. Worth its own word:
  /// silence here reads as "no picture yet", which is the one thing it is not.
  final bool undecodable;

  final bool loading;

  /// The hovered node's id — see [RunScreenPicture.highlight].
  final ValueNotifier<String?> highlight;

  /// The tree the picture was read with. **The same reading**, which is what
  /// makes a rect over a still picture exact here: the catalog's overlay has
  /// to prefer the guest's own last frame over the tree's rect, because there
  /// the picture is live and the tree is of the build it was read from. This
  /// picture is a photograph of that build.
  final InspectTree? tree;

  /// What the picture frames, in the app's logical pixels — see
  /// [canvasOf].
  final InspectLayout? canvas;

  /// The box the picture frames, in the app's own logical pixels — the
  /// [canvas] every rect is scaled against.
  ///
  /// The topmost rect in the tree, and that is not a guess. The screenshot
  /// RPC is handed the size `getLayoutExplorerNode` reads off the root — which
  /// is a `RenderView` and reports none, so the size that reaches it is the
  /// first *child* that does, the app's own bounds. The guest walk gives its
  /// first `layout` to the same node, because `_layoutOf` answers only for a
  /// `RenderBox` and everything above that one is the view. So the picture
  /// shows exactly this rect, and every other rect in the tree is inside it.
  static InspectLayout? canvasOf(InspectTree? tree) {
    InspectLayout? find(InspectNode node) {
      if (node.layout case var layout?) return layout;
      for (var child in node.children) {
        if (find(child) case var layout?) return layout;
      }
      return null;
    }

    var root = tree?.root;
    return root == null ? null : find(root);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: context.colors.panel,
      alignment: Alignment.topCenter,
      padding: const EdgeInsets.all(FwSpacing.md),
      // Shrink-wrapped and top-aligned so the caption sits *under the
      // picture*, not at the bottom of whatever height the pane happens to
      // have. `Expanded` put it a screen away from what it describes.
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (picture case var picture?) ...[
            Flexible(
              child: Stack(
                fit: StackFit.passthrough,
                children: [
                  RawImage(
                    image: picture,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.medium,
                  ),
                  Positioned.fill(
                    child: IgnorePointer(
                      child: _Highlight(
                        highlight: highlight,
                        tree: tree,
                        canvas: canvas,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Gap(FwSpacing.sm),
            Text(
              'rendered by the app — platform views will not appear',
              textAlign: TextAlign.center,
              style: context.type.micro.copyWith(color: context.colors.mut3),
            ),
          ] else
            Text(
              switch ((loading, undecodable)) {
                // Never the empty string: a pane that draws nothing is
                // indistinguishable from a pane that is not there, and beside
                // the grip it reads as an unexplained rule down the page.
                (true, _) => 'Taking a picture…',
                (_, true) =>
                  'The app answered with a picture that decodes to nothing.',
                _ => 'No picture yet',
              },
              textAlign: TextAlign.center,
              style: context.type.caption.copyWith(color: context.colors.mut2),
            ),
        ],
      ),
    );
  }
}

/// The hovered node's box, over the picture.
///
/// The rect is scaled here rather than under a `FittedBox`. The catalog
/// paints into a surface that *is* the guest's logical size, so its painter
/// needs no transform — but this picture is the app shrunk into a third of a
/// pane, and scaling the painter would take the label down with it to three
/// points. So the host does what the painter's contract says the host does:
/// decides which rect, in the coordinates the painter draws in.
///
/// Width and height scale independently. They are the same number whenever
/// the picture frames the canvas, which is the case this is built for; if
/// something ever letterboxes the render, a box covering the same *fraction*
/// of the picture is a better wrong answer than one that has slid off it.
class _Highlight extends StatelessWidget {
  const _Highlight({
    required this.highlight,
    required this.tree,
    required this.canvas,
  });

  final ValueNotifier<String?> highlight;
  final InspectTree? tree;
  final InspectLayout? canvas;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: highlight,
    builder: (context, hovered, _) {
      // **Hover only, never the selection** — the rule the catalog's overlay
      // arrived at and for its reason: a box that stays after you choose
      // something is a box you then need a way to dismiss. What a selection
      // leaves behind is the detail pane, not a rectangle.
      var node = hovered == null ? null : tree?.nodeAt(hovered);
      // An offstage node wears the rect it had the last time it was on a
      // screen. Hovering its row lights the row and leaves the picture alone.
      if (node?.offstage ?? false) node = null;
      var layout = node?.layout;
      if (layout == null || canvas == null) return const SizedBox.shrink();
      return LayoutBuilder(
        builder: (context, constraints) => CustomPaint(
          painter: NodeHighlightPainter(
            rect: scale(layout, canvas!, constraints.biggest),
            label: node?.type,
            color: context.colors.accent,
          ),
        ),
      );
    },
  );

  /// [box] in the app's logical pixels, as a rect in a picture of [canvas]
  /// drawn at [size].
  static Rect? scale(InspectLayout box, InspectLayout canvas, Size size) {
    if (canvas.width <= 0 || canvas.height <= 0) return null;
    var x = size.width / canvas.width;
    var y = size.height / canvas.height;
    return Rect.fromLTWH(
      (box.x - canvas.x) * x,
      (box.y - canvas.y) * y,
      box.width * x,
      box.height * y,
    );
  }
}
