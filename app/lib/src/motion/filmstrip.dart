import 'dart:io';

import 'package:image/image.dart' as img;

/// One frame of a filmstrip, and where on the playhead it was taken.
class FilmstripFrame {
  FilmstripFrame({required this.file, required this.t, required this.ms});

  final File file;
  final double t;
  final int ms;
}

/// Lays [frames] out as a single contact sheet and writes it to [output].
///
/// One image of N moments, rather than N images. This is what makes an
/// animation affordable for an agent to look at: the alternative is N separate
/// artifacts, each of which costs a tool call to fetch and a good deal of
/// context to hold, for a comparison that is only meaningful when they are side
/// by side. A person opening it gets the same thing a contact sheet has always
/// been for.
///
/// Frames go left to right in playhead order, each labelled with its `t` and
/// its milliseconds — the two units the panel and the values file are written
/// in, so a frame that looks wrong can be found in the file without arithmetic.
File composeFilmstrip(
  List<FilmstripFrame> frames, {
  required String output,
  int cellWidth = 320,
  bool dark = false,
}) {
  if (frames.isEmpty) {
    throw ArgumentError.value(frames, 'frames', 'nothing to compose');
  }

  const gutter = 8;
  const labelHeight = 20;
  var ground = dark ? img.ColorRgb8(18, 20, 26) : img.ColorRgb8(244, 245, 247);
  var ink = dark ? img.ColorRgb8(236, 238, 241) : img.ColorRgb8(32, 36, 40);

  var cells = <img.Image>[];
  for (var frame in frames) {
    var decoded = img.decodePng(frame.file.readAsBytesSync());
    if (decoded == null) {
      throw StateError('frame at t=${frame.t} is not a readable PNG');
    }
    // Scaled down, never up: a frame rendered small and enlarged is a blurrier
    // frame, and the sheet is for judging timing rather than pixels.
    cells.add(
      decoded.width <= cellWidth
          ? decoded
          : img.copyResize(decoded, width: cellWidth),
    );
  }

  var cellHeight = cells.fold(
    0,
    (tallest, cell) => cell.height > tallest ? cell.height : tallest,
  );
  var width =
      cells.fold(0, (sum, cell) => sum + cell.width) +
      gutter * (cells.length + 1);
  var height = cellHeight + labelHeight + gutter * 2;

  var sheet = img.Image(width: width, height: height);
  img.fill(sheet, color: ground);

  var x = gutter;
  for (var (index, cell) in cells.indexed) {
    img.compositeImage(sheet, cell, dstX: x, dstY: gutter);
    var frame = frames[index];
    img.drawString(
      sheet,
      // Both units, because the panel shows one and the values file holds the
      // other, and reading a filmstrip is how you decide which to change.
      't=${_shortT(frame.t)}  ${frame.ms}ms',
      font: img.arial14,
      x: x + 2,
      y: gutter + cellHeight + 3,
      color: ink,
    );
    x += cell.width + gutter;
  }

  var file = File(output);
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(img.encodePng(sheet));
  return file;
}

/// `0.417`, not `0.4166666666666667` — a label somebody reads.
String _shortT(double t) =>
    t.toStringAsFixed(3).replaceFirst(RegExp(r'\.?0+$'), '');

/// The playhead positions [count] frames should be taken at.
///
/// Both ends included. A filmstrip whose first frame is not `t = 0` cannot
/// show what a motion starts from, and one whose last is not `t = 1` cannot
/// show where it lands — which are the two frames anybody looks at first.
List<double> filmstripStops(int count) {
  if (count <= 1) return const [1];
  return [for (var i = 0; i < count; i++) i / (count - 1)];
}
