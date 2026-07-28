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
/// [CatalogShell]'s builder is handed a [TopBarState], so nothing below the
/// shell can add to the set.
void main() {
  late CatalogAxes axes;
  var entry = 0;

  setUp(() {
    // A shared singleton, so each test starts by clearing what the last one
    // filed — a null selection being "back to the default" is what makes that
    // expressible.
    //
    // A fresh entry id every time, because `resetFor` deliberately no-ops on an
    // unchanged one: in the guest it runs on every build of `CatalogGuest`, and
    // clearing there would wipe what the shell below had just declared.
    axes = CatalogAxes.instance
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
    var topBar = axes.beginShell('app');
    expect(topBar.picker('flavor', _flavors, Flavor.dev), Flavor.dev);

    var report = axes.describe();
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
    var topBar = axes.beginShell('s');
    var chosen = topBar.picker('locale', {
      'English': const Locale('en'),
      'Français': const Locale('fr'),
    }, const Locale('en'));
    expect(chosen, const Locale('en'));
    expect(axes.describe().axes.single.options, ['English', 'Français']);
  });

  test('a selection is answered by the next pick', () {
    axes.apply({
      's': {'flavor': 'Production'},
    });
    var topBar = axes.beginShell('s');
    expect(topBar.picker('flavor', _flavors, Flavor.dev), Flavor.prod);
    expect(axes.describe().axes.single.isDefault, isFalse);
  });

  test('a selection the options do not have falls back', () {
    // A leftover from an older build of the shell, or a `--flavor=prd` typed
    // at a CLI.
    axes.apply({
      's': {'flavor': 'nonsense'},
    });
    var topBar = axes.beginShell('s');
    expect(topBar.picker('flavor', _flavors, Flavor.staging), Flavor.staging);
  });

  test('a selection may arrive before the shell that reads it has built', () {
    // Which is the ordinary case: the host cannot know which shell an entry
    // uses until that entry has built, so it pushes every shell's selections up
    // front and this one is already in hand when the shell first asks.
    axes.apply({
      's': {'flavor': 'Staging'},
    });
    expect(axes.describe().axes, isEmpty);
    var topBar = axes.beginShell('s');
    expect(topBar.picker('flavor', _flavors, Flavor.dev), Flavor.staging);
  });

  test('a flag is a closed set too, and keeps its own kind', () {
    expect(axes.beginShell('s').flag('compact', false), isFalse);
    expect(axes.describe().axes.single.kind, KnobKind.boolean);

    axes.apply({
      's': {'compact': true},
    });
    expect(axes.beginShell('s').flag('compact', false), isTrue);
  });

  test('the report is the current shell, not everything ever declared', () {
    axes.beginShell('one').picker('flavor', _flavors, Flavor.dev);
    axes.beginShell('two').flag('compact', false);

    var report = axes.describe();
    expect(report.shellId, 'two');
    expect(report.axes.map((a) => a.name), ['compact']);
  });

  test('two shells that name an axis alike do not share a selection', () {
    // The reason selections are filed under the shell rather than under the
    // axis name: both of these declare `flavor`, and only one of them was set.
    axes.apply({
      'one': {'flavor': 'Production'},
    });
    expect(
      axes.beginShell('one').picker('flavor', _flavors, Flavor.dev),
      Flavor.prod,
    );
    expect(
      axes.beginShell('two').picker('flavor', _flavors, Flavor.dev),
      Flavor.dev,
    );
  });

  test('a selection survives a shell it does not belong to', () {
    axes.apply({
      's': {'flavor': 'Production'},
    });
    axes.beginShell('other').picker('size', _sizes, Size.small);
    expect(
      axes.beginShell('s').picker('flavor', _flavors, Flavor.dev),
      Flavor.prod,
    );
  });

  test('the order is the order they were asked for', () {
    var topBar = axes.beginShell('s');
    topBar.flag('compact', false);
    topBar.picker('flavor', _flavors, Flavor.dev);
    expect(axes.describe().axes.map((a) => a.name), ['compact', 'flavor']);
  });

  test('an entry change clears the axes, so one with no shell has none', () {
    axes.beginShell('s').flag('compact', false);
    expect(axes.describe().axes, hasLength(1));

    // Nothing declares anything for the next entry, which is exactly what an
    // entry whose wrapper is not a shell looks like.
    axes.resetFor('a-different-entry');
    var report = axes.describe();
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
        child: CatalogShell(
          'app',
          builder: (context, topBar) {
            built.add(topBar.picker('flavor', _flavors, Flavor.dev));
            return const SizedBox();
          },
        ),
      ),
    );
    expect(built, [Flavor.dev]);
    expect(axes.describe().shellId, 'app');

    axes.apply({
      'app': {'flavor': 'Production'},
    });
    await tester.pump();
    expect(built, [Flavor.dev, Flavor.prod]);
  });

  test('an empty push changes nothing, and does not ask for a frame', () {
    var revision = axes.revision.value;
    expect(axes.apply(const {}), isFalse);
    expect(axes.revision.value, revision);
  });

  test('a push that repeats what is already set asks for no frame either', () {
    axes.apply({
      's': {'flavor': 'Production'},
    });
    var revision = axes.revision.value;
    expect(
      axes.apply({
        's': {'flavor': 'Production'},
      }),
      isFalse,
    );
    expect(axes.revision.value, revision);
  });

  test('a null selection is back to the default', () {
    axes.apply({
      's': {'flavor': 'Production'},
    });
    expect(
      axes.beginShell('s').picker('flavor', _flavors, Flavor.dev),
      Flavor.prod,
    );

    axes.apply({
      's': {'flavor': null},
    });
    expect(
      axes.beginShell('s').picker('flavor', _flavors, Flavor.dev),
      Flavor.dev,
    );
  });
}
