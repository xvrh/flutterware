import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware_app/src/session/action_shapes.generated.dart';
import 'package:flutterware_app/src/session/shape_extractor.dart';
import 'package:path/path.dart' as p;

import '../../tool/generate_capabilities.dart'
    show renderShapes, shapeRoots, shapeSources, shapesPath;

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
  test('action_shapes.generated.dart matches the result classes', () async {
    var extracted = await ShapeExtractor(
      packageRoots: [for (var root in shapeRoots) p.absolute(root)],
    ).extract([for (var source in shapeSources) p.absolute(source)]);

    expect(
      File(shapesPath).readAsStringSync(),
      renderShapes(extracted),
      reason:
          'The published result shapes no longer match the classes.\n'
          'Regenerate them:\n'
          '  cd app && dart run tool/generate_capabilities.dart',
    );
  }, timeout: const Timeout(Duration(minutes: 2)));

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

  test('a member kept off the wire is kept out of the document', () {
    // `@JsonKey(includeToJson: false)` says so in one word, and until it was
    // read the document listed three kinds of member no reply ever contains: a
    // declared field the producer keeps for itself (`ScenarioRunStep.root` —
    // "Not on the wire", says its own dartdoc), a convenience getter
    // (`imageFile`), and the `ProducesArtifacts` hook every result that carries
    // a picture now implements.
    var step = resultShapes['ScenarioRunStep']!;
    expect(step.fields.map((f) => f.name), isNot(contains('root')));
    expect(step.fields.map((f) => f.name), isNot(contains('imageFile')));
    // The getter case is the one that needs the accessor read as well as the
    // field: a computed member's field is synthetic and carries no metadata,
    // so a check that looked only at the field caught none of them.
    expect(
      resultShapes['CatalogInspectResult']!.fields.map((f) => f.name),
      isNot(contains('artifacts')),
    );
    // And what is sent is still described.
    expect(step.fields.map((f) => f.name), contains('image'));
  });

  group('a hand-written toJson', () {
    // `Artifact` is the most-returned result of all and writes its own map, so
    // for a while it published nothing. It is described now by reading that
    // map rather than its fields — which is the only honest way, since the two
    // disagree.
    var artifact = resultShapes['Artifact'];

    test('publishes the shape it writes', () {
      expect(artifact, isNotNull);
      expect(
        artifact!.fields.map((f) => f.name),
        containsAll(['kind', 'address', 'path', 'text', 'meta']),
      );
    });

    test('describes the key it sends, not the field it holds', () {
      // The whole reason the old rule refused to look: the field is an
      // `Address` and the wire carries `address.toString()`. Publishing
      // `address: Address` would be a schema for a response nobody sends.
      var address = artifact!.fields.firstWhere((f) => f.name == 'address');
      expect(address.type, 'String');
    });

    test('reads optionality off the `if`, not off the field type', () {
      // `if (path != null) 'path': path` — the condition is what decides
      // whether the key appears at all.
      expect(
        artifact!.fields.firstWhere((f) => f.name == 'path').optional,
        isTrue,
      );
      expect(
        artifact.fields.firstWhere((f) => f.name == 'kind').optional,
        isFalse,
      );
    });

    test('still refuses a toJson it cannot read', () {
      // The standard is unchanged; only the reach is. A `toJson` that builds
      // its map some other way is described by nothing rather than guessed at,
      // which is what `Address` — no `toJson` at all — demonstrates.
      expect(resultShapes.containsKey('Address'), isFalse);
    });
  });
}
