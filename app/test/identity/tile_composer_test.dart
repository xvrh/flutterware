import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware_app/src/identity/tile_composer.dart';
import 'package:flutterware_app/src/identity/tile_slot.dart';

/// Composing the tile a project's icon rides in.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// A flat square of [colour], as PNG bytes — a project icon whose pixels are
  /// trivially identifiable once composited.
  Future<List<int>> square(ui.Color colour, {int size = 256}) async {
    var recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawRect(
      ui.Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()),
      ui.Paint()..color = colour,
    );
    var image = await recorder.endRecording().toImage(size, size);
    var data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  }

  test('the project icon lands in the slot', () async {
    var png = await TileComposer.compose(
      Uint8List.fromList(await square(const ui.Color(0xFFFF0000))),
      size: 512,
    );
    expect(png, isNotNull);

    var codec = await ui.instantiateImageCodec(png!);
    var tile = (await codec.getNextFrame()).image;
    expect(tile.width, 512);
    expect(tile.height, 512);

    var pixels = await tile.toByteData();
    // The slot's centre, mapped from tile units into this render.
    var scale = 512 / tileCanvas;
    var x = ((tileChipLeft + tileChipSize / 2) * scale).round();
    var y = ((tileChipTop + tileChipSize / 2) * scale).round();
    var offset = (y * 512 + x) * 4;
    expect(
      pixels!.getUint8(offset),
      greaterThan(200),
      reason: 'the red square should be showing through the slot',
    );
    expect(pixels.getUint8(offset + 1), lessThan(60));

    // And the wordmark's side of the tile is still the dark tile, not the icon.
    var left = ((tileChipLeft / 2) * scale).round();
    var tileOffset = (y * 512 + left) * 4;
    expect(pixels.getUint8(tileOffset), lessThan(80));
  });

  test('an icon that will not decode still yields a tile', () async {
    // A truncated PNG: the window should keep its own mark rather than fail.
    var png = await TileComposer.compose(
      Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0, 0, 0]),
      size: 256,
    );
    expect(png, isNotNull);
    var codec = await ui.instantiateImageCodec(png!);
    expect((await codec.getNextFrame()).image.width, 256);
  });

  /// The asset the composer draws on has to be in the bundle, and a rename in
  /// `generate.dart` would break that silently at runtime.
  test('the base tile asset is committed', () {
    expect(File('assets/fw_tile_base.png').existsSync(), isTrue);
  });
}
