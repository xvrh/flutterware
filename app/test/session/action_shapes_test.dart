import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware_app/src/session/action_shapes.generated.dart';
import 'package:flutterware_app/src/session/shape_extractor.dart';
import 'package:path/path.dart' as p;

import '../../tool/generate_capabilities.dart'
    show renderShapes, shapeSources, shapesPath;

/// The published shape of every action result has to be the shape the classes
/// actually have.
///
/// `docs/capabilities.md` and MCP's `flutterware_actions` both read the
/// generated file, and a generated file nobody re-derives is just a
/// hand-maintained schema with extra steps — the exact thing typed results were
/// chosen to avoid. So this re-runs the extraction against the source and fails
/// when the two disagree.
///
/// It costs a few seconds: resolving a library that transitively imports
/// Flutter is the price of reading types rather than guessing them. That is
/// the whole test suite's slowest single test and still worth it.
void main() {
  test(
    'action_shapes.generated.dart matches the result classes',
    () async {
      var extracted = await ShapeExtractor(
        packageRoot: p.absolute('lib'),
      ).extract([for (var source in shapeSources) p.absolute(source)]);

      expect(
        File(shapesPath).readAsStringSync(),
        renderShapes(extracted),
        reason:
            'The published result shapes no longer match the classes.\n'
            'Regenerate them:\n'
            '  cd app && dart run tool/generate_capabilities.dart',
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test('every shape is reachable by the name an action reports', () {
    // `PluginAction.returnsName` is the key a renderer looks up, so a shape
    // filed under anything else is a shape nobody finds.
    for (var entry in resultShapes.entries) {
      expect(entry.value.type, entry.key);
    }
  });

  test('optionality survives extraction', () {
    // The property that decided this design over deriving shapes from sample
    // output: a sample cannot tell "absent because nothing to say" from
    // "absent because we did not look".
    var description = resultShapes['CatalogEntryDescription']!;
    var byName = {for (var field in description.fields) field.name: field};

    expect(byName['id']!.optional, isFalse);
    expect(byName['knobs']!.optional, isTrue);
    expect(
      byName['knobs']!.shape,
      isNotNull,
      reason: 'nested types are walked',
    );
  });

  test('the wire name wins over the Dart field name', () {
    // `CatalogKnob.defaultValue` is `@JsonKey(name: 'default')`. A document
    // that published `defaultValue` would describe a key nobody sends.
    var knob = resultShapes['CatalogKnob']!;
    expect(knob.fields.map((f) => f.name), contains('default'));
    expect(knob.fields.map((f) => f.name), isNot(contains('defaultValue')));
  });

  test('a hand-written toJson publishes no shape', () {
    // `Artifact` maps an `Address` to a string, so its fields are not its
    // keys. Publishing them would be a schema for a response nobody sends.
    expect(resultShapes.containsKey('Artifact'), isFalse);
  });
}
