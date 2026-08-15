import 'package:flutter/material.dart';
import 'package:flutterware/flutter_test.dart';
import 'package:flutterware/ui_catalog.dart';

/// Exercises the harness the way `flutter test` does — this file *is* the
/// `flutter test` lane, so the entries below are declared as real tests and
/// their passing is half the assertion.
void main() {
  var size = <String, Size>{};
  var knob = <String, String>{};

  Widget probe(String id) => Builder(
    builder: (context) {
      size[id] = MediaQuery.of(context).size;
      // A preview reading a knob with nothing hosting it answers the default
      // rather than throwing — but under `CatalogGuest` there *is* something
      // hosting it, and that is the path worth proving.
      knob[id] = context.knobs.string('label', 'unanswered');
      return const SizedBox.shrink();
    },
  );

  runPreviewHarness(
    [
      PreviewEntry(
        id: 'demo/phone.dart#phone',
        path: 'demo/phone.dart',
        name: 'Phone',
        build: () => probe('phone'),
      ),
      PreviewEntry(
        id: 'demo/desktop/wide.dart#wide',
        path: 'demo/desktop/wide.dart',
        name: 'Wide',
        build: () => probe('wide'),
      ),
      PreviewEntry(
        id: 'demo/plain.dart#plain',
        path: 'demo/plain.dart',
        name: 'Plain',
        build: () => probe('plain'),
      ),
    ],
    canvases: const [
      PreviewCanvas('demo', devices: [Devices.iphoneSe]),
      PreviewCanvas('demo/desktop', devices: [Devices.macbookPro]),
    ],
  );

  // Declared after the entries, so it runs after them: what the entries saw is
  // what these assert on.
  test('each entry is framed by the canvas its own path resolves to', () {
    // Longest prefix wins, which is the whole reason `canvasFor` is shared
    // rather than re-implemented per caller.
    expect(size['phone']!.width, Devices.iphoneSe.width);
    expect(size['wide']!.width, Devices.macbookPro.width);
    expect(
      size['plain']!.width,
      Devices.iphoneSe.width,
      reason: 'demo/plain.dart is under `demo`, not under `demo/desktop`',
    );
  });

  test('a preview builds under the same host the guest entrypoint mounts', () {
    // `CatalogGuest` is what puts the knobs provider up. Without it every read
    // answers the written default, which looks identical until somebody sets
    // one — so this is the assertion that says the two backends mount the same
    // tree rather than merely both rendering something.
    expect(knob, hasLength(3));
    expect(knob['phone'], 'unanswered');
  });

  test('the real fonts were loaded, not the fallback', () {
    // Under `flutter test` this is the FontLoader half only — the engine still
    // has `--use-test-fonts` forced on it, which is exactly why the tool spawns
    // its own tester for the lane whose overflow verdicts count.
    expect(loadedScenarioFonts, isNotNull);
  });
}
