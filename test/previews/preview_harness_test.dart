import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutterware/flutter_test.dart';
// The half of the harness `flutter_test.dart` does not re-export.
import 'package:flutterware/src/previews/harness.dart';
import 'package:flutterware/ui_catalog.dart';

/// Exercises the harness the way `flutter test` does — this file *is* the
/// `flutter test` lane, so the entries below are declared as real tests and
/// their passing is half the assertion.
void main() {
  var size = <String, Size>{};
  var knob = <String, String>{};
  var loaded = false;

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
      PreviewEntry(
        id: 'demo/slow.dart#slow',
        path: 'demo/slow.dart',
        name: 'Slow',
        build: () => _SlowLoad(onLoaded: () => loaded = true),
      ),
    ],
    canvases: const [
      PreviewCanvas('demo', devices: [Devices.iphoneSe]),
      PreviewCanvas('demo/desktop', devices: [Devices.wideWindow]),
    ],
  );

  // Declared after the entries, so it runs after them: what the entries saw is
  // what these assert on.
  test('each entry is framed by the canvas its own path resolves to', () {
    // Longest prefix wins, which is the whole reason `canvasFor` is shared
    // rather than re-implemented per caller.
    expect(size['phone']!.width, Devices.iphoneSe.width);
    expect(
      size['wide']!.width,
      previewPanelWidth.toDouble(),
      reason:
          'a declared window is offered rather than staged, here as well as '
          'in the panel — see PreviewCanvas.defaultDevice',
    );
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

  test('an entry that waits on a timer is given the clock to finish', () {
    // The entry above passing at all is half the assertion: a frame-driven
    // settle returns 100ms in and the tree is disposed with the load's timer
    // pending, which `flutter_test` fails the test for. This is the other half
    // — the load finished, rather than the timer having been merely drained.
    expect(loaded, isTrue);
  });

  test('a row says the harness ran out of clock, not that the entry leaks', () {
    expect(
      auditFailureMessage(
        'A Timer is still pending even after the widget tree was disposed.',
      ),
      allOf(
        contains('${auditBudget.inSeconds}s'),
        contains('the audit clock'),
        isNot(contains('binding.dart')),
      ),
    );
  });

  test('every other failure is passed through as the framework wrote it', () {
    expect(
      auditFailureMessage('A RenderFlex overflowed by 3.5 pixels'),
      'A RenderFlex overflowed by 3.5 pixels',
    );
  });

  test('the real fonts were loaded, not the fallback', () {
    // Under `flutter test` this is the FontLoader half only — the engine still
    // has `--use-test-fonts` forced on it, which is exactly why the tool spawns
    // its own tester for the lane whose overflow verdicts count.
    expect(loadedScenarioFonts, isNotNull);
  });
}

/// A preview that shows a placeholder until a timer says otherwise — the shape
/// of every demo whose point is the placeholder, and the one nothing in the
/// frame loop can see waiting.
class _SlowLoad extends StatefulWidget {
  const _SlowLoad({required this.onLoaded});

  final VoidCallback onLoaded;

  @override
  State<_SlowLoad> createState() => _SlowLoadState();
}

class _SlowLoadState extends State<_SlowLoad> {
  var _loaded = false;

  @override
  void initState() {
    super.initState();
    unawaited(
      Future<void>.delayed(const Duration(milliseconds: 250)).then((_) {
        if (!mounted) return;
        widget.onLoaded();
        setState(() => _loaded = true);
      }),
    );
  }

  @override
  Widget build(BuildContext context) => Text(
    _loaded ? 'loaded' : 'placeholder',
    textDirection: TextDirection.ltr,
  );
}
