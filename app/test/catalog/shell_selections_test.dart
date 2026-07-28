import 'package:flutterware_app/src/catalog/catalog_session.dart';
import 'package:test/test.dart';

/// What each shell's axes are set to, which the host remembers rather than the
/// guest.
///
/// The host is the only side that knows selections at all before a shell has
/// built — which shell an entry uses is something only the guest can say, and
/// only once it has rendered. So everything known is sent every time, filed
/// under the shell it belongs to, and the guest picks out the sub-map for
/// whichever shell it turns out to be building.
void main() {
  const one = 'app';
  const two = 'plain';

  late ShellSelections selections;
  setUp(() => selections = ShellSelections());

  test('nothing chosen sends nothing', () {
    expect(selections.payload(), isEmpty);
  });

  test('a choice is carried, filed under the shell it was made on', () {
    selections.choose(one, 'flavor', 'Production');
    expect(selections.payload(), {
      one: {'flavor': 'Production'},
    });
  });

  test('two shells can each hold their own value for one name', () {
    selections
      ..choose(one, 'flavor', 'Production')
      ..choose(two, 'flavor', 'Fancy');
    expect(selections.chosen(one, 'flavor'), 'Production');
    expect(selections.chosen(two, 'flavor'), 'Fancy');
    expect(selections.payload(), {
      one: {'flavor': 'Production'},
      two: {'flavor': 'Fancy'},
    });
  });

  test('every shell goes in one payload, not only the one on screen', () {
    // The whole reason the payload is nested: the host cannot know which of
    // these the next entry will use, so both travel and the guest chooses.
    selections
      ..choose(one, 'compact', true)
      ..choose(two, 'loudness', 'Loud');
    expect(selections.payload().keys, [one, two]);
  });

  test('a flag is held as a bool, not as a label', () {
    selections.choose(one, 'compact', true);
    expect(selections.payload(), {
      one: {'compact': true},
    });
  });

  test('choosing null is carried, because it means back to the default', () {
    // Not dropped: the guest already has the old value, so the null is an
    // instruction to forget it rather than the absence of one.
    selections
      ..choose(one, 'flavor', 'Production')
      ..choose(one, 'flavor', null);
    expect(selections.payload(), {
      one: {'flavor': null},
    });
  });

  test('the payload is a copy, so a later choice does not rewrite it', () {
    selections.choose(one, 'flavor', 'Production');
    var sent = selections.payload();
    selections.choose(one, 'flavor', 'Staging');
    expect(sent, {
      one: {'flavor': 'Production'},
    });
  });
}
