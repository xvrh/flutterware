import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware/src/ui_catalog/axes.dart';
import 'package:flutterware/src/ui_catalog/knob.dart';

enum Flavor { dev, staging, prod }

enum Size { small, large }

const _flavors = {
  'Dev': Flavor.dev,
  'Staging': Flavor.staging,
  'Production': Flavor.prod,
};

const _sizes = {'Small': Size.small, 'Large': Size.large};

/// The top bar's switches, from the guest's side.
///
/// A shell declares them by asking for them while it builds, so what the panel
/// is offered is whatever the last build of the shell asked for. What keeps
/// that from drifting the way knobs can is scope, not timing: only a
/// [PreviewShell]'s builder is handed a [PreviewAxes], so nothing below the
/// shell can add to the set.
void main() {
  late CatalogAxes catalog;
  var entry = 0;

  setUp(() {
    // A shared singleton, so each test starts by clearing what the last one
    // filed — a null selection being "back to the default" is what makes that
    // expressible.
    //
    // A fresh entry id every time, because `resetFor` deliberately no-ops on an
    // unchanged one: in the guest it runs on every build of `CatalogGuest`, and
    // clearing there would wipe what the shell below had just declared.
    catalog = CatalogAxes.instance
      ..apply({
        'one': {'flavor': null, 'compact': null, 'size': null},
        'two': {'flavor': null, 'compact': null, 'size': null},
        's': {'flavor': null, 'compact': null, 'size': null},
        'app': {'flavor': null, 'compact': null, 'size': null},
        'other': {'flavor': null, 'compact': null, 'size': null},
      })
      ..resetFor('entry-${entry++}');
  });

  test('an axis reports what there is to choose from', () {
    var axes = catalog.beginShell('app');
    expect(axes.picker('flavor', _flavors, Flavor.dev), Flavor.dev);

    var report = catalog.describe();
    expect(report.shellId, 'app');
    expect(report.entryId, startsWith('entry-'));
    var axis = report.axes.single;
    expect(axis.name, 'flavor');
    expect(axis.kind, KnobKind.picker);
    // The labels the shell wrote, not the identifiers behind them.
    expect(axis.options, ['Dev', 'Staging', 'Production']);
    expect(axis.value, 'Dev');
    expect(axis.defaultValue, 'Dev');
    expect(axis.isDefault, isTrue);
  });

  test('the values may be of any type, not only enums', () {
    var axes = catalog.beginShell('s');
    var chosen = axes.picker('locale', {
      'English': const Locale('en'),
      'Français': const Locale('fr'),
    }, const Locale('en'));
    expect(chosen, const Locale('en'));
    expect(catalog.describe().axes.single.options, ['English', 'Français']);
  });

  test('a selection is answered by the next pick', () {
    catalog.apply({
      's': {'flavor': 'Production'},
    });
    var axes = catalog.beginShell('s');
    expect(axes.picker('flavor', _flavors, Flavor.dev), Flavor.prod);
    expect(catalog.describe().axes.single.isDefault, isFalse);
  });

  test('a selection the options do not have falls back', () {
    // A leftover from an older build of the shell, or a `--flavor=prd` typed
    // at a CLI.
    catalog.apply({
      's': {'flavor': 'nonsense'},
    });
    var axes = catalog.beginShell('s');
    expect(axes.picker('flavor', _flavors, Flavor.staging), Flavor.staging);
  });

  test('a selection may arrive before the shell that reads it has built', () {
    // Which is the ordinary case: the host cannot know which shell an entry
    // uses until that entry has built, so it pushes every shell's selections up
    // front and this one is already in hand when the shell first asks.
    catalog.apply({
      's': {'flavor': 'Staging'},
    });
    expect(catalog.describe().axes, isEmpty);
    var axes = catalog.beginShell('s');
    expect(axes.picker('flavor', _flavors, Flavor.dev), Flavor.staging);
  });

  test('a flag is a closed set too, and keeps its own kind', () {
    expect(catalog.beginShell('s').flag('compact', false), isFalse);
    expect(catalog.describe().axes.single.kind, KnobKind.boolean);

    catalog.apply({
      's': {'compact': true},
    });
    expect(catalog.beginShell('s').flag('compact', false), isTrue);
  });

  test('the report is the current shell, not everything ever declared', () {
    catalog.beginShell('one').picker('flavor', _flavors, Flavor.dev);
    catalog.beginShell('two').flag('compact', false);

    var report = catalog.describe();
    expect(report.shellId, 'two');
    expect(report.axes.map((a) => a.name), ['compact']);
  });

  test('two shells that name an axis alike do not share a selection', () {
    // The reason selections are filed under the shell rather than under the
    // axis name: both of these declare `flavor`, and only one of them was set.
    catalog.apply({
      'one': {'flavor': 'Production'},
    });
    expect(
      catalog.beginShell('one').picker('flavor', _flavors, Flavor.dev),
      Flavor.prod,
    );
    expect(
      catalog.beginShell('two').picker('flavor', _flavors, Flavor.dev),
      Flavor.dev,
    );
  });

  test('a selection survives a shell it does not belong to', () {
    catalog.apply({
      's': {'flavor': 'Production'},
    });
    catalog.beginShell('other').picker('size', _sizes, Size.small);
    expect(
      catalog.beginShell('s').picker('flavor', _flavors, Flavor.dev),
      Flavor.prod,
    );
  });

  test('the order is the order they were asked for', () {
    var axes = catalog.beginShell('s');
    axes.flag('compact', false);
    axes.picker('flavor', _flavors, Flavor.dev);
    expect(catalog.describe().axes.map((a) => a.name), ['compact', 'flavor']);
  });

  test('an entry change clears the axes, so one with no shell has none', () {
    catalog.beginShell('s').flag('compact', false);
    expect(catalog.describe().axes, hasLength(1));

    // Nothing declares anything for the next entry, which is exactly what an
    // entry whose wrapper is not a shell looks like.
    catalog.resetFor('a-different-entry');
    var report = catalog.describe();
    expect(report.entryId, 'a-different-entry');
    expect(report.shellId, isNull);
    expect(report.axes, isEmpty);
  });

  testWidgets('the shell declares as it builds, and rebuilds on a selection', (
    tester,
  ) async {
    var built = <Flavor>[];
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: PreviewShell(
          'app',
          builder: (context, axes) {
            built.add(axes.picker('flavor', _flavors, Flavor.dev));
            return const SizedBox();
          },
        ),
      ),
    );
    expect(built, [Flavor.dev]);
    expect(catalog.describe().shellId, 'app');

    catalog.apply({
      'app': {'flavor': 'Production'},
    });
    await tester.pump();
    expect(built, [Flavor.dev, Flavor.prod]);
  });

  test('a name left out of a push is forgotten, like an explicit null', () {
    // The host holds selections in the address, where an axis on its default is
    // written as *nothing at all* — so an absent name is an instruction to
    // forget rather than an absence of instruction. Merging instead is what
    // made the top bar look stuck: choosing the default dropped the name from
    // the payload and the shell went on rebuilding with the old choice.
    catalog.apply({
      's': {'flavor': 'Production', 'compact': true},
    });

    expect(
      catalog.apply({
        's': {'compact': true},
      }),
      isTrue,
    );

    // Proven by what the shell now builds with, not by reading a private map.
    var axes = catalog.beginShell('s');
    expect(axes.picker('flavor', _flavors, Flavor.dev), Flavor.dev);
    expect(axes.flag('compact', false), isTrue, reason: 'this one was kept');
  });

  test('an empty push changes nothing, and does not ask for a frame', () {
    var revision = catalog.revision.value;
    expect(catalog.apply(const {}), isFalse);
    expect(catalog.revision.value, revision);
  });

  test('a push that repeats what is already set asks for no frame either', () {
    catalog.apply({
      's': {'flavor': 'Production'},
    });
    var revision = catalog.revision.value;
    expect(
      catalog.apply({
        's': {'flavor': 'Production'},
      }),
      isFalse,
    );
    expect(catalog.revision.value, revision);
  });

  test('a null selection is back to the default', () {
    catalog.apply({
      's': {'flavor': 'Production'},
    });
    expect(
      catalog.beginShell('s').picker('flavor', _flavors, Flavor.dev),
      Flavor.prod,
    );

    catalog.apply({
      's': {'flavor': null},
    });
    expect(
      catalog.beginShell('s').picker('flavor', _flavors, Flavor.dev),
      Flavor.dev,
    );
  });
}
