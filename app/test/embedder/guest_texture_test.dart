import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware_app/src/embedder/guest_texture.dart';
// ignore: implementation_imports
import 'package:flutterware/src/offscreen_raster.dart';

/// The two things [GuestTexture] is for, and they pull in opposite directions:
/// no `TextureLayer` in the tree a `toImage` photographs, and nothing rebuilt
/// to achieve it.
///
/// The first keeps the studio alive — on Linux that layer is a segfault rather
/// than a wrong picture. The second keeps it watchable: a rebuilt `Texture` is
/// a new external texture, and the compositor resolves one to black for a
/// frame, which a human sees as a flicker on every click into a live preview.
///
/// Read after the raster and before the next pump, which is the moment the
/// notice has been lowered but nothing has repainted on it yet — so what is
/// measured is the tree the raster saw.
void main() {
  Widget panel() => const Center(
    child: SizedBox(width: 20, height: 20, child: GuestTexture(textureId: 7)),
  );

  /// External textures in the **layer** tree — what the raster actually walks,
  /// and not the same question as whether the render object is still there.
  int textureLayers() {
    var found = 0;
    void walk(Layer layer) {
      if (layer is TextureLayer) found++;
      if (layer is ContainerLayer) {
        for (var child = layer.firstChild; child != null;) {
          walk(child);
          child = child.nextSibling;
        }
      }
    }

    for (var view in RendererBinding.instance.renderViews) {
      if (view.debugLayer case var root?) walk(root);
    }
    return found;
  }

  TextureBox theTextureBox() {
    TextureBox? found;
    void walk(RenderObject node) {
      if (node is TextureBox) found = node;
      node.visitChildren(walk);
    }

    for (var view in RendererBinding.instance.renderViews) {
      walk(view);
    }
    return found!;
  }

  testWidgets('the guest leaves the layer tree for the frame a raster reads', (
    tester,
  ) async {
    await tester.pumpWidget(panel());
    expect(textureLayers(), 1);

    var done = OffscreenRaster.around(() async {});
    await tester.pump();
    await done;

    expect(textureLayers(), 0);
    await tester.pump();
    expect(
      textureLayers(),
      1,
      reason: 'and it comes straight back — the panel is live, not paused',
    );
  });

  testWidgets('nothing is destroyed to do it', (tester) async {
    // The anti-flicker property, pinned: the same `TextureBox` throughout. A
    // different one on the far side is a newly registered external texture,
    // and that is the black frame this widget exists in its current shape to
    // avoid.
    await tester.pumpWidget(panel());
    var before = theTextureBox();

    var done = OffscreenRaster.around(() async {});
    await tester.pump();
    await done;
    expect(theTextureBox(), same(before), reason: 'kept through the raster');

    await tester.pump();
    expect(theTextureBox(), same(before), reason: 'and after it');
  });

  testWidgets('it is the guest that goes, not the box around it', (
    tester,
  ) async {
    // A panel that collapses for one frame relayouts everything around it, and
    // on a hidden window that frame is the one the picture is taken from.
    await tester.pumpWidget(panel());
    var before = tester.getRect(find.byType(GuestTexture));

    var done = OffscreenRaster.around(() async {});
    await tester.pump();
    await done;

    expect(tester.getRect(find.byType(GuestTexture)), before);
  });
}
