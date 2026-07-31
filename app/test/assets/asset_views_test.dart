import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware_app/src/assets/detail.dart';
import 'package:flutterware_app/src/assets/list.dart';
import 'package:flutterware_app/src/assets/model/asset_catalog.dart';
import 'package:flutterware_app/src/assets/model/asset_scan.dart';
import 'package:flutterware_app/src/assets/preview.dart';
import 'package:flutterware_app/src/ui/matched_text.dart';

/// The views, pumped with data that never came off a disk.
///
/// That is the property being asserted as much as any expectation below: an
/// `AssetFile` carries its length and a preview takes bytes, so these widgets
/// can be drawn — here, and in a catalog demo — with no project behind them.
void main() {
  AssetFile file(String key, {double? scale, int length = 400}) =>
      AssetFile(path: '/project/$key', key: key, scale: scale, length: length);

  ResolvedAsset asset(
    String key, {
    String? package,
    String? declaration,
    List<AssetFile>? files,
  }) => ResolvedAsset(
    key: key,
    package: package,
    packageRoot: '/project',
    declaration: declaration ?? key,
    files: files ?? [file(key)],
  );

  Future<void> pump(WidgetTester tester, Widget child) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: SizedBox(width: 900, child: child)),
    ),
  );

  group('the list', () {
    testWidgets('shows assets, sizes and variant counts', (tester) async {
      await pump(
        tester,
        AssetListView(
          own: [
            asset(
              'assets/images/logo.png',
              files: [
                file('assets/images/logo.png', length: 663),
                file('assets/images/2.0x/logo.png', scale: 2, length: 1840),
              ],
            ),
          ],
          fromPackages: const [],
          problems: const [],
          selected: null,
          onSelect: (_) {},
        ),
      );

      expect(find.text('logo.png'), findsOneWidget);
      expect(find.text('assets/images'), findsOneWidget);
      expect(find.textContaining('2.4 kB'), findsOneWidget);
      expect(
        find.text('1 variant'),
        findsOneWidget,
        reason: 'One variant beside the main file.',
      );
    });

    testWidgets('reports a tap as a selection', (tester) async {
      String? selected;
      await pump(
        tester,
        AssetListView(
          own: [asset('assets/logo.png')],
          fromPackages: const [],
          problems: const [],
          selected: null,
          onSelect: (key) => selected = key,
        ),
      );

      await tester.tap(find.text('logo.png'));
      expect(selected, 'assets/logo.png');
    });

    testWidgets('keeps a dependency collapsed until asked', (tester) async {
      await pump(
        tester,
        AssetListView(
          own: const [],
          fromPackages: [
            AssetOwner(
              package: 'brand',
              assets: [
                asset('packages/brand/assets/mark.png', package: 'brand'),
              ],
            ),
          ],
          problems: const [],
          selected: null,
          onSelect: (_) {},
        ),
      );

      expect(find.text('package:brand'), findsOneWidget);
      expect(find.text('mark.png'), findsNothing);

      await tester.tap(find.text('package:brand'));
      await tester.pump();

      expect(find.text('mark.png'), findsOneWidget);
    });

    testWidgets('filters by key', (tester) async {
      await pump(
        tester,
        AssetListView(
          own: [asset('assets/logo.png'), asset('assets/banner.jpg')],
          fromPackages: const [],
          problems: const [],
          selected: null,
          onSelect: (_) {},
        ),
      );

      await tester.enterText(find.byType(TextField), 'banner');
      await tester.pump();

      expect(find.text('banner.jpg'), findsOneWidget);
      expect(find.text('logo.png'), findsNothing);
    });

    testWidgets('lights the characters the filter matched', (tester) async {
      await pump(
        tester,
        AssetListView(
          own: [asset('assets/images/logo.png')],
          fromPackages: const [],
          problems: const [],
          selected: null,
          onSelect: (_) {},
        ),
      );

      await tester.enterText(find.byType(TextField), 'lg');
      await tester.pump();

      var name = tester.widget<Text>(
        find
            .descendant(
              of: find.byType(MatchedText),
              matching: find.byType(Text),
            )
            .first,
      );
      var spans = (name.textSpan! as TextSpan).children!.cast<TextSpan>();
      var lit = [
        for (var span in spans)
          if (span.style?.backgroundColor != null) span.text,
      ];
      expect(
        lit,
        ['l', 'g'],
        reason:
            'The subsequence that matched, not a substring — `lg` matches '
            '`logo.png` and no substring search would light anything.',
      );
    });

    testWidgets('says what an empty package means', (tester) async {
      await pump(
        tester,
        AssetListView(
          own: const [],
          fromPackages: const [],
          problems: const [],
          selected: null,
          onSelect: (_) {},
        ),
      );

      expect(find.textContaining('declares no assets'), findsOneWidget);
    });

    testWidgets('shows a problem with what is wrong with it', (tester) async {
      await pump(
        tester,
        AssetListView(
          own: const [],
          fromPackages: const [],
          problems: [
            AssetProblem(
              kind: AssetProblemKind.missingFile,
              package: null,
              packageRoot: '/project',
              declaration: 'assets/gone.png',
            ),
          ],
          selected: null,
          onSelect: (_) {},
        ),
      );

      expect(find.text('assets/gone.png'), findsOneWidget);
      expect(find.text('Declared, and not on disk.'), findsOneWidget);
    });
  });

  group('the detail', () {
    var logo = asset(
      'assets/images/logo.png',
      declaration: 'assets/images/',
      files: [
        file('assets/images/logo.png', length: 663),
        file('assets/images/2.0x/logo.png', scale: 2, length: 1840),
        file('assets/images/3.0x/logo.png', scale: 3, length: 3120),
      ],
    );

    Widget detail({
      AssetFile? shown,
      ValueChanged<AssetFile>? onDensity,
      Object? error,
    }) => AssetDetailView(
      asset: logo,
      file: shown ?? logo.main,
      bytes: error == null ? _png : null,
      error: error,
      dimensions: const Size(48, 48),
      background: PreviewBackground.checker,
      onBackground: (_) {},
      zoom: 1,
      onZoom: (_) {},
      onDensity: onDensity ?? (_) {},
    );

    testWidgets('says where the asset came from', (tester) async {
      await pump(tester, detail());

      // The declaration is the answer to "why is this in my bundle", and for a
      // directory declaration it is not derivable from the path.
      expect(find.text('assets/images/'), findsOneWidget);
      expect(find.text('48 × 48'), findsOneWidget);
      expect(find.text('663 B'), findsOneWidget);
    });

    testWidgets('offers one density per file, and reports the pick', (
      tester,
    ) async {
      AssetFile? picked;
      await pump(tester, detail(onDensity: (file) => picked = file));

      expect(find.text('2×'), findsWidgets);
      await tester.tap(find.text('3×').first);
      expect(picked?.scale, 3);
    });

    testWidgets('offers no zoom for a thing that has no size', (tester) async {
      var specimen = asset('assets/fonts/Roboto.ttf');
      await pump(
        tester,
        AssetDetailView(
          asset: specimen,
          file: specimen.main,
          bytes: _png,
          error: null,
          dimensions: null,
          background: PreviewBackground.checker,
          onBackground: (_) {},
          zoom: 1,
          onZoom: (_) {},
          onDensity: (_) {},
        ),
      );

      expect(find.text('Zoom'), findsNothing);
      expect(find.text('100%'), findsNothing);
    });

    testWidgets('zoom reads as magnification, not as a density', (
      tester,
    ) async {
      await pump(tester, detail());

      // `2×` next to the density switcher's `2×` would be the same thing said
      // twice about two different things.
      expect(find.text('100%'), findsOneWidget);
      expect(find.text('Density'), findsOneWidget);
      expect(find.text('Zoom'), findsOneWidget);
    });

    testWidgets('an unreadable file says so instead of drawing', (
      tester,
    ) async {
      await pump(tester, detail(error: 'PathNotFoundException'));

      expect(find.textContaining('Could not read this file'), findsOneWidget);
    });
  });

  group('the preview', () {
    testWidgets('draws a raster', (tester) async {
      await pump(
        tester,
        AssetPreview(bytes: _png, kind: AssetKind.image, name: 'logo.png'),
      );
      await tester.pumpAndSettle();

      expect(find.byType(Image), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a magnified asset is clipped to its pane', (tester) async {
      await pump(
        tester,
        SizedBox(
          height: 120,
          child: AssetPreview(
            bytes: _png,
            kind: AssetKind.image,
            name: 'logo.png',
            zoom: 8,
          ),
        ),
      );
      await tester.pump();

      // `Transform.scale` does not clip: at 8× a large raster painted straight
      // over the sidebar and the metadata beneath it.
      var viewer = tester.widget<InteractiveViewer>(
        find.byType(InteractiveViewer),
      );
      expect(viewer.clipBehavior, isNot(Clip.none));
      expect(
        viewer.panEnabled,
        isTrue,
        reason: 'Magnifying without panning shows the middle and nothing else.',
      );
    });

    testWidgets('says when a kind has no preview', (tester) async {
      await pump(
        tester,
        AssetPreview(
          bytes: _png,
          kind: AssetKind.media,
          name: 'assets/chime.mp3',
        ),
      );

      expect(find.textContaining('No preview'), findsOneWidget);
    });

    testWidgets('falls back when JSON is not an animation', (tester) async {
      await pump(
        tester,
        AssetPreview(
          bytes: Uint8List.fromList(utf8.encode('{"not":"lottie"}')),
          kind: AssetKind.data,
          name: 'assets/config.json',
        ),
      );
      await tester.pumpAndSettle();

      // Most `.json` files are not animations, so this is the ordinary path
      // rather than an error.
      expect(find.textContaining('No preview'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('reports a font it cannot load', (tester) async {
      await pump(
        tester,
        AssetPreview(
          bytes: _png,
          kind: AssetKind.font,
          name: 'assets/fonts/Broken.ttf',
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Not a usable font file'), findsOneWidget);
    });
  });
}

/// The 48×48 fixture from `examples/example`.
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAADAAAAAwCAIAAADYYG7QAAAARklEQVR42u3YMQ0AIAwAwepgI/hE'
  'Ro1ioB5YoMklL+Dmj7H2VwVQa9DM8yQgICAgICAgICAgICAgICAgICAgICAgJx/osgK8LWl1SxSv'
  '2QAAAABJRU5ErkJggg==',
);
