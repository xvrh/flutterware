import 'package:flutterware_app/src/tui/terminal.dart';
import 'package:test/test.dart';

void main() {
  group('anchorRowAfterPrintAbove', () {
    test('region with room below just drifts down by the line count', () {
      // Region top at row 5, height 4, terminal 40 rows: plenty of room.
      expect(
        anchorRowAfterPrintAbove(
            originRow: 5, regionRows: 4, linesPrinted: 3, terminalLines: 40),
        8,
      );
    });

    test('region pins at the bottom once it reaches it', () {
      // maxOrigin = 40 - 4 = 36. originRow 35 + 10 lines would be 45.
      expect(
        anchorRowAfterPrintAbove(
            originRow: 35, regionRows: 4, linesPrinted: 10, terminalLines: 40),
        36,
      );
    });

    test('already pinned region stays pinned', () {
      expect(
        anchorRowAfterPrintAbove(
            originRow: 36, regionRows: 4, linesPrinted: 5, terminalLines: 40),
        36,
      );
    });

    test('zero lines printed leaves the anchor unchanged', () {
      expect(
        anchorRowAfterPrintAbove(
            originRow: 12, regionRows: 4, linesPrinted: 0, terminalLines: 40),
        12,
      );
    });

    test('terminal shorter than the region clamps the anchor to 0', () {
      // maxOrigin = 3 - 5 = -2; result must clamp up to 0.
      expect(
        anchorRowAfterPrintAbove(
            originRow: 0, regionRows: 5, linesPrinted: 2, terminalLines: 3),
        0,
      );
    });
  });
}
