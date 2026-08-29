@Timeout(Duration(minutes: 4))
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:flutterware_app/src/embedder/build_directory.dart';
import 'package:flutterware_app/src/previews/catalog_render.dart';
import 'package:flutterware_app/src/previews/devices.dart';
import 'package:flutterware_app/src/previews/discovery.dart';
import 'package:flutterware_app/src/previews/test_runner.dart';
import 'package:flutterware_app/src/previews/tester_renderer.dart';
import 'package:path/path.dart' as p;

/// End-to-end: the real `examples/example` package, a real `flutter_tester`,
/// real knobs and real axes. Slow (a cold harness compile), so everything is
/// exercised in one warm sequence rather than one test per assertion.
///
/// `demo/input.dart#keyboards` is the fixture because it declares both halves
/// of the question in the same render: a `focus` picker the *entry* asked for
/// while it built, and the `dark` and `locale` axes the *shell* around it
/// declared. A demo with only knobs would leave the axis path untested and
/// look green.
void main() {
  test('reads what an entry declares, and turns it', () async {
    var flutterRoot = Platform.environment['FLUTTER_ROOT'];
    expect(
      flutterRoot,
      isNotNull,
      reason: 'flutter test always sets FLUTTER_ROOT',
    );
    var repoRoot = Directory.current.parent.path;
    var packageRoot = p.join(repoRoot, 'examples', 'example');

    var scan = CatalogScanner(projectRoot: packageRoot).scan();
    var keyboards = scan.entries.singleWhere(
      (entry) => entry.id == 'demo/input.dart#keyboards',
    );

    var buildDirectory = claimBuildDirectory(
      packageRoot,
      root: comparisonBuildRoot,
    );
    var runner = PreviewTestRunner(
      packageRoot: packageRoot,
      flutterSdkRoot: flutterRoot!,
      read: () => (entries: [keyboards], canvases: const []),
      buildDirectory: buildDirectory,
    );
    var renderer = TesterRenderer(runner: runner);
    try {
      var declared = await renderer.render(
        CatalogRender(entryId: keyboards.id, wantKnobs: true, wantAxes: true),
      );

      // A knob exists because the demo *asked* for it while it built, so this
      // is evidence the entry really rendered rather than that a file was
      // parsed.
      expect(
        declared.knobs!.knobs.single.name,
        'focus',
        reason: 'the entry declares one picker',
      );
      expect(declared.knobs!.knobs.single.value, 'Phone');
      expect(
        declared.knobs!.knobs.single.options,
        containsAll(['Phone', 'Email']),
      );
      // And an axis because the shell *around* it did — a different scope, and
      // the reason both are asked for in one render.
      expect(declared.axes!.shellId, 'app');
      expect(
        declared.axes!.axes.map((axis) => axis.name),
        containsAll(['dark', 'locale']),
      );

      // Turned, and read back off the build the turn produced. Both at once,
      // because a shell rebuild changes what the demo is handed and applying
      // them in the wrong order is exactly what would not show up when they
      // are tested apart.
      var turned = await renderer.render(
        CatalogRender(
          entryId: keyboards.id,
          knobs: const {'focus': 'Email'},
          axes: const {'dark': 'true', 'locale': 'Français'},
          wantKnobs: true,
          wantAxes: true,
        ),
      );
      expect(turned.knobs!.knobs.single.value, 'Email');
      var byName = {for (var axis in turned.axes!.axes) axis.name: axis.value};
      expect(byName['dark'], isTrue);
      expect(byName['locale'], 'Français');

      // A name nobody declared is refused, naming what *is* declared — the
      // same words the guest refuses it in, because both lanes resolve values
      // through `catalog_values.dart`. Silently ignoring one produces a
      // picture that looks right and is not.
      await expectLater(
        renderer.render(
          CatalogRender(entryId: keyboards.id, knobs: const {'focos': 'Email'}),
        ),
        throwsA(
          isA<ArgumentError>().having(
            (e) => '${e.message}',
            'message',
            allOf(contains('no such knob'), contains('focus')),
          ),
        ),
      );
      await expectLater(
        renderer.render(
          CatalogRender(entryId: keyboards.id, axes: const {'darkk': 'true'}),
        ),
        throwsA(
          isA<ArgumentError>().having(
            (e) => '${e.message}',
            'message',
            allOf(contains('no such axis'), contains('dark')),
          ),
        ),
      );
      // And a value of the wrong kind, which only the declaration can judge.
      await expectLater(
        renderer.render(
          CatalogRender(entryId: keyboards.id, knobs: const {'focus': 'Fax'}),
        ),
        throwsA(isA<ArgumentError>()),
      );

      // What this lane cannot answer it refuses by name rather than answering
      // empty: a caller told "no logs" when it means "not on this engine"
      // goes looking in the demo.
      await expectLater(
        renderer.render(CatalogRender(entryId: keyboards.id, wantLogs: true)),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('cannot answer `logs`'),
          ),
        ),
      );

      // A picture, framed and written where it was asked for — and cropped to
      // one widget, which is the path that proves the tree and the frame came
      // off the same render: the crop is resolved host-side against the tree
      // this lane reported, then cut out of the frame it drew.
      var shots = Directory.systemTemp.createTempSync('fw_render_shot');
      addTearDown(() => shots.deleteSync(recursive: true));
      var whole = await renderer.render(
        CatalogRender(
          entryId: keyboards.id,
          screenshot: p.join(shots.path, 'whole.png'),
        ),
      );
      var wholeImage = img.decodePng(whole.screenshot!.readAsBytesSync())!;
      expect(wholeImage.width, CaptureViewport.panel.width);
      expect(wholeImage.height, CaptureViewport.panel.height);

      var cropped = await renderer.render(
        CatalogRender(
          entryId: keyboards.id,
          screenshot: p.join(shots.path, 'one.png'),
          cropNode: 'Phone',
        ),
      );
      var croppedImage = img.decodePng(cropped.screenshot!.readAsBytesSync())!;
      expect(croppedImage.width, lessThan(wholeImage.width));
      expect(croppedImage.height, lessThan(wholeImage.height));

      // **A device is staged, not refused.** Asked on a phone, the entry must
      // render there — and the evidence has to be something only the *screen*
      // could have changed, because a knob read back proves the request
      // arrived and nothing about the surface it arrived on. This entry
      // declares its picker either way; what a 375-wide phone does that a
      // 900×700 rectangle does not is overflow.
      var onPhone = await renderer.render(
        CatalogRender(
          entryId: keyboards.id,
          viewport: CaptureViewport.of(deviceById('iphone-se')!),
          wantKnobs: true,
        ),
      );
      expect(onPhone.knobs!.knobs.single.name, 'focus');
      var phone = CaptureViewport.of(deviceById('iphone-se')!);
      expect(onPhone.stagedOn!.width, phone.width);
      expect(onPhone.stagedOn!.height, phone.height);
      expect(onPhone.stagedOn!.pixelRatio, phone.pixelRatio);
      // And the rectangle is not the phone, so the assertion above is about
      // the request rather than about whatever the surface happens to be.
      expect(declared.stagedOn!.width, CaptureViewport.panel.width);
      expect(declared.stagedOn!.pixelRatio, 1);
    } finally {
      await runner.dispose();
      releaseBuildDirectory(
        packageRoot,
        buildDirectory,
        root: comparisonBuildRoot,
      );
    }
  });
}
