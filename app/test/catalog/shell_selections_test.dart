import 'package:flutterware_app/src/catalog/catalog_session.dart';
import 'package:flutterware_app/src/catalog/shell_descriptor.dart';
import 'package:test/test.dart';

/// What each shell's axes are set to, which the host remembers rather than the
/// guest.
///
/// The guest keys selections by axis name alone — it is handed one shell's
/// values at a time and has no reason to know about the others — so keeping
/// them apart is the host's job.
void main() {
  const one = ShellDescriptor(
    path: 'demo/shell.dart',
    symbol: 'wrapInApp',
    axes: [
      ShellAxis(
        name: 'flavor',
        typeName: 'Flavor',
        defaultSource: 'Flavor.dev',
      ),
      ShellAxis(name: 'compact', typeName: 'bool', defaultSource: 'false'),
    ],
  );
  const two = ShellDescriptor(
    path: 'demo/other.dart',
    symbol: 'wrapInPlainApp',
    axes: [
      ShellAxis(
        name: 'flavor',
        typeName: 'Flavour',
        defaultSource: 'Flavour.plain',
      ),
    ],
  );

  late ShellSelections selections;
  setUp(() => selections = ShellSelections());

  test('every axis is named, so nothing is left to a leftover', () {
    // The nulls are the instruction: "back to the signature's default". Leaving
    // an axis out would leave whatever the guest had for that name in place.
    expect(selections.payloadFor(one), {'flavor': null, 'compact': null});
  });

  test('a choice is carried, and only for the shell it was made on', () {
    selections.choose(one.id, 'flavor', 'prod');
    expect(selections.payloadFor(one), {'flavor': 'prod', 'compact': null});
    expect(
      selections.payloadFor(two),
      {'flavor': null},
      reason: 'two shells naming an axis alike do not share its value',
    );
  });

  test('two shells can each hold their own value for one name', () {
    selections
      ..choose(one.id, 'flavor', 'prod')
      ..choose(two.id, 'flavor', 'fancy');
    expect(selections.chosen(one.id, 'flavor'), 'prod');
    expect(selections.chosen(two.id, 'flavor'), 'fancy');
  });

  test('a flag is held as a bool, not as a name', () {
    selections.choose(one.id, 'compact', true);
    expect(selections.payloadFor(one), {'flavor': null, 'compact': true});
  });

  test('choosing null is back to the default, not forgetting the axis', () {
    selections
      ..choose(one.id, 'flavor', 'prod')
      ..choose(one.id, 'flavor', null);
    expect(selections.payloadFor(one), {'flavor': null, 'compact': null});
  });

  test('an axis dropped from the signature drops out of the payload', () {
    // The payload is built from the shell as discovery last described it, so a
    // signature that lost an axis stops sending it without anyone tidying up.
    selections.choose(one.id, 'compact', true);
    const shrunk = ShellDescriptor(
      path: 'demo/shell.dart',
      symbol: 'wrapInApp',
      axes: [
        ShellAxis(
          name: 'flavor',
          typeName: 'Flavor',
          defaultSource: 'Flavor.dev',
        ),
      ],
    );
    expect(selections.payloadFor(shrunk), {'flavor': null});
  });

  test('a shell with no axes sends nothing', () {
    const bare = ShellDescriptor(path: 'demo/bare.dart', symbol: 'bare');
    expect(selections.payloadFor(bare), isEmpty);
  });
}
