import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware/src/scenarios/fonts.dart';

void main() {
  // Plain `test`, not `testWidgets`: both lanes load fonts *outside* any test —
  // the harness at startup, `runScenarios` before it declares — so there is no
  // FakeAsync around the real bundle read, and a widget test would put one
  // there and hang on it.
  var binding = TestWidgetsFlutterBinding.ensureInitialized();

  setUp(resetScenarioFontsForTest);

  test('loads once, however many lanes ask', () async {
    var first = await loadScenarioFonts();
    var second = await loadScenarioFonts();

    // The same list, not an equal one: two lanes in one process must await the
    // first load rather than each doing their own.
    expect(identical(first, second), isTrue);
  });

  test('nothing has loaded until something does', () async {
    expect(loadedScenarioFonts, isNull);
    await loadScenarioFonts();
    expect(loadedScenarioFonts, isNotNull);
  });

  test('registers every family the manifest declares', () async {
    _serveBundle(binding, {
      'FontManifest.json': jsonEncode([
        {'family': 'Fixture', 'fonts': <Object>[]},
        {'family': 'Other', 'fonts': <Object>[]},
      ]),
    });

    expect(await loadScenarioFonts(), ['Fixture', 'Other']);
  });

  test('a bundle with no manifest is a project with no fonts', () async {
    // A suite that passes today may not start failing because its bundle
    // carries no `FontManifest.json` — there is nothing to load, which is not
    // the same as something going wrong.
    _serveBundle(binding, const {});

    expect(await loadScenarioFonts(), isEmpty);
  });
}

/// Answers asset loads from [assets] and refuses everything else, the way a
/// bundle missing a key does.
void _serveBundle(
  TestWidgetsFlutterBinding binding,
  Map<String, String> assets,
) {
  binding.defaultBinaryMessenger.setMockMessageHandler('flutter/assets', (
    message,
  ) async {
    var key = utf8.decode(message!.buffer.asUint8List());
    var value = assets[key];
    if (value == null) return null;
    return ByteData.sublistView(utf8.encode(value));
  });
  addTearDown(() {
    binding.defaultBinaryMessenger.setMockMessageHandler(
      'flutter/assets',
      null,
    );
    rootBundle.clear();
  });
  // `rootBundle` caches by key, and this process has a real bundle behind it.
  rootBundle.clear();
}
