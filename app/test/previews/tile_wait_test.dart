import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware_app/src/previews/catalog_entry.dart';
import 'package:flutterware_app/src/previews/catalog_view.dart';
import 'package:flutterware_app/src/ui/startup_progress.dart';
import 'package:flutterware_app/src/previews/preview_sheet.dart';

/// A page of empty frames says nothing about whether the first picture is two
/// seconds away or forty, and the store has always known which — a cold harness
/// compiles the whole catalog and takes tens of seconds, where a warm one is a
/// message and a frame. These are the rules that put that on screen.
///
/// The no-spinner rule survives all of it. A shimmer is a surface treatment
/// rather than a control, so a hundred and fifty of them read as one page
/// loading where a hundred and fifty spinners read as a hundred and fifty
/// problems — and the queued tile, which is seconds away, gets no treatment at
/// all.
void main() {
  group('what the page says about its own pass', () {
    test('nothing while the harness is still being compiled', () {
      // The pass opens the instant the page asks for pictures, which on a cold
      // harness is tens of seconds before any picture can be made. Left to
      // speak, it read "Rendering the previews · 1 / 55" through a compile in
      // which nothing rendered at all.
      expect(
        renderPassTask(busy: true, warm: false, done: 1, total: 55),
        isNull,
      );
    });

    test('the count once the harness is up', () {
      expect(
        renderPassTask(busy: true, warm: true, done: 1, total: 55),
        const StartupTask('Rendering the previews', done: 1, total: 55),
      );
    });

    test('nothing for a single picture', () {
      // A hover on a warm harness, which is well under a second.
      expect(renderPassTask(busy: true, warm: true, done: 0, total: 1), isNull);
    });

    test('nothing when nothing is being rendered', () {
      expect(
        renderPassTask(busy: false, warm: true, done: 9, total: 9),
        isNull,
        reason: 'a progress surface that outlives its progress is chrome',
      );
    });
  });

  CatalogEntry entry(String symbol) => CatalogEntry(
    path: 'demo/a.dart',
    symbol: symbol,
    annotation: "Preview(name: '$symbol')",
    name: symbol,
  );

  var entries = [entry('alpha'), entry('beta'), entry('gamma')];

  Widget sheet({
    PreviewTileWait? Function(CatalogEntry entry)? waitOf,
    bool animate = false,
  }) => MaterialApp(
    home: Scaffold(
      body: PreviewSheet(
        sections: [
          PreviewSheetSection(
            label: 'Demos',
            entries: entries,
            pictureRatio: 0.75,
          ),
        ],
        screenOf: (_) => const Size(400, 300),
        waitOf: waitOf,
        animate: animate,
      ),
    ),
  );

  // The painter is the shimmer: every waiting tile that has a treatment is
  // painting one, and a tile that has none is painting nothing.
  Finder shimmers() => find.byWidgetPredicate(
    (widget) =>
        widget is CustomPaint &&
        widget.painter.runtimeType.toString().contains('Shimmer'),
  );

  testWidgets('a queued tile is a plain reserved box', (tester) async {
    await tester.pumpWidget(
      sheet(waitOf: (_) => PreviewTileWait.queued, animate: true),
    );
    expect(
      shimmers(),
      findsNothing,
      reason: 'seconds away is not news, and a treatment for it is noise',
    );
  });

  testWidgets('a compiling tile shimmers', (tester) async {
    await tester.pumpWidget(
      sheet(waitOf: (_) => PreviewTileWait.compiling, animate: true),
    );
    expect(shimmers(), findsNWidgets(entries.length));
  });

  testWidgets('nothing waiting draws nothing', (tester) async {
    await tester.pumpWidget(sheet());
    expect(shimmers(), findsNothing);
  });

  testWidgets('one ticker for the sheet, stopped when nothing is pending', (
    tester,
  ) async {
    // A hundred and fifty controllers is a hundred and fifty tickers, on
    // exactly the frames where the thing being waited for wants every core.
    await tester.pumpWidget(
      sheet(waitOf: (_) => PreviewTileWait.compiling, animate: true),
    );
    expect(
      tester.binding.transientCallbackCount,
      1,
      reason: 'one controller at the sheet, read down the tree',
    );
    await tester.pumpWidget(sheet(waitOf: (_) => PreviewTileWait.compiling));
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('the tile being rendered is marked, and it is not a selection', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PreviewSheet(
            sections: [
              PreviewSheetSection(
                label: 'Demos',
                entries: entries,
                pictureRatio: 0.75,
              ),
            ],
            screenOf: (_) => const Size(400, 300),
            selectedId: entries.first.id,
            waitOf: (entry) => entry.id == entries[1].id
                ? PreviewTileWait.rendering
                : PreviewTileWait.queued,
            animate: true,
          ),
        ),
      ),
    );
    // The mark is the shimmer plus a hairline; the selection is two pixels of
    // the same colour over a tinted fill. Only the marked one paints.
    expect(shimmers(), findsOneWidget);
  });
}
