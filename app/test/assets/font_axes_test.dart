// The fvar reader, against fonts built byte by byte.
//
// A synthetic font rather than a bundled one on purpose: the licences that
// let a variable face be redistributed are not the ones a test fixture wants
// to carry, and a hand-built table exercises the malformed cases a real file
// never contains.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware_app/src/assets/model/font_axes.dart';

/// An sfnt with one table in its directory.
Uint8List _font(
  String tag,
  List<int> table, {
  String sfnt = '\x00\x01\x00\x00',
}) {
  var head = ByteData(12 + 16);
  for (var (i, c) in sfnt.codeUnits.indexed) {
    head.setUint8(i, c);
  }
  head.setUint16(4, 1);
  for (var (i, c) in tag.codeUnits.indexed) {
    head.setUint8(12 + i, c);
  }
  head.setUint32(12 + 8, 28);
  head.setUint32(12 + 12, table.length);
  return Uint8List.fromList([...head.buffer.asUint8List(), ...table]);
}

/// An fvar table holding [axes] as (tag, min, default, max).
List<int> _fvar(
  List<(String, double, double, double)> axes, {
  int axisSize = 20,
}) {
  var b = ByteData(16 + axes.length * axisSize);
  b.setUint16(0, 1); // major
  b.setUint16(2, 0); // minor
  b.setUint16(4, 16); // axesArrayOffset
  b.setUint16(8, axes.length);
  b.setUint16(10, axisSize);
  for (var (i, a) in axes.indexed) {
    var at = 16 + i * axisSize;
    for (var (j, c) in a.$1.codeUnits.indexed) {
      b.setUint8(at + j, c);
    }
    b.setInt32(at + 4, (a.$2 * 65536).round());
    b.setInt32(at + 8, (a.$3 * 65536).round());
    b.setInt32(at + 12, (a.$4 * 65536).round());
  }
  return b.buffer.asUint8List();
}

void main() {
  test('reads every axis with its own range', () {
    var axes = readFontAxes(
      _font('fvar', _fvar([('wght', 100, 400, 900), ('wdth', 62.5, 100, 125)])),
    );
    expect(axes.map((a) => a.tag), ['wght', 'wdth']);
    expect(axes.first.min, 100);
    expect(axes.first.def, 400);
    expect(axes.first.max, 900);
    expect(axes.last.min, 62.5, reason: 'Fixed 16.16 carries a fraction');
    expect(axes.first.label, 'Weight');
  });

  test('a bigger axis record is read, its extra bytes skipped', () {
    // The spec fixes 20 and allows more; a reader that assumed 20 would walk
    // into the middle of the second axis.
    var axes = readFontAxes(
      _font(
        'fvar',
        _fvar([('wght', 1, 400, 1000), ('slnt', -10, 0, 0)], axisSize: 24),
      ),
    );
    expect(axes.map((a) => a.tag), ['wght', 'slnt']);
    expect(axes.last.min, -10, reason: 'a negative axis is ordinary');
  });

  test('a static face, a collection and a truncated file all read as none', () {
    expect(readFontAxes(_font('glyf', [0, 0, 0, 0])), isEmpty);
    expect(
      readFontAxes(
        _font('fvar', _fvar([('wght', 100, 400, 900)]), sfnt: 'ttcf'),
      ),
      isEmpty,
      reason: 'a collection needs a face index nobody passed',
    );
    expect(readFontAxes(Uint8List.fromList([0, 1, 0, 0])), isEmpty);
    var short = _font('fvar', _fvar([('wght', 100, 400, 900)]));
    expect(readFontAxes(short.sublist(0, short.length - 8)), isEmpty);
  });

  test('an axis whose range is a contradiction is left out', () {
    // Clamping would put the handle somewhere the face never goes.
    var axes = readFontAxes(
      _font('fvar', _fvar([('wght', 900, 400, 100), ('wdth', 50, 100, 200)])),
    );
    expect(axes.map((a) => a.tag), ['wdth']);
  });
}
