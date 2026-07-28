import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware/plugins.dart';
import 'package:flutterware_app/src/address/address_scope.dart';

/// The shape the UI catalog will nest into: a package, then an entry that owns
/// the knobs. Written out here so the granularity tests are about a real tree
/// rather than an arrangement invented to pass.
Address _catalog({
  String entry = 'demo/avatar.dart#members',
  Map<String, String> axes = const {},
}) => Address(
  worktree: 'main',
  plugin: 'flutterware.ui_catalog',
  segments: ['app', entry],
  axes: axes,
);

/// Counts its own builds, so a test can assert what did **not** rebuild —
/// which is the entire claim this file exists to check.
class _Probe extends StatelessWidget {
  const _Probe(this.label, this.read, this.builds);

  final String label;
  final Object? Function(BuildContext) read;
  final Map<String, int> builds;

  @override
  Widget build(BuildContext context) {
    builds[label] = (builds[label] ?? 0) + 1;
    return Text('$label=${read(context)}', textDirection: TextDirection.ltr);
  }
}

void main() {
  group('AddressView eats its part', () {
    test('segments are consumed positionally', () {
      var root = AddressView(_catalog());
      expect(root.segments, ['app', 'demo/avatar.dart#members']);

      var package = root.nest(eat: 1);
      expect(package.segments, ['demo/avatar.dart#members']);
      expect(
        package.segment(0),
        'demo/avatar.dart#members',
        reason: 'a level indexes from zero of what it can see',
      );

      var entry = package.nest(eat: 1);
      expect(entry.segments, isEmpty);
      expect(entry.segment(0), isNull);
    });

    test('eating past the end is empty, not an error', () {
      expect(AddressView(_catalog()).nest(eat: 9).segments, isEmpty);
    });

    test('parameters are consumed by namespace', () {
      var view = AddressView(
        _catalog(axes: {'axis.theme': 'dark', 'knob.count': '3'}),
      );

      expect(
        view.params,
        isEmpty,
        reason: 'the root owns un-namespaced params',
      );

      var axes = view.nest(namespace: 'axis');
      expect(axes.param('theme'), 'dark');
      expect(axes.param('count'), isNull);
      expect(axes.params, {'theme': 'dark'});

      var knobs = axes.nest(eat: 1, namespace: 'knob');
      expect(knobs.param('count'), '3');
      expect(knobs.params, {'count': '3'});
    });

    test('a namespace replaces rather than compounds', () {
      // `?knob.count`, never `?axis.knob.count` — the address gets pasted into
      // terminals and filenames and has to stay legible however deep the tree.
      var view = AddressView(
        _catalog(),
      ).nest(namespace: 'axis').nest(namespace: 'knob');
      expect(view.keyFor('count'), 'knob.count');
    });

    test('an un-namespaced level keeps the parent namespace', () {
      var view = AddressView(_catalog()).nest(namespace: 'knob').nest(eat: 1);
      expect(view.keyFor('count'), 'knob.count');
    });
  });

  group('writes are relative', () {
    test('a level cannot move anything above it', () {
      Address? written;
      var handle = AddressHandle(
        AddressView(_catalog(), segmentOffset: 1),
        (a) => written = a,
      );

      handle.setSegments(['demo/team.dart#list']);

      expect(written!.segments, ['app', 'demo/team.dart#list']);
      expect(written!.worktree, 'main');
      expect(written!.plugin, 'flutterware.ui_catalog');
    });

    test('replacing a level truncates everything deeper', () {
      // Changing the package cannot leave the previous package's entry behind:
      // it names nothing there.
      Address? written;
      AddressHandle(
        AddressView(_catalog()),
        (a) => written = a,
      ).setSegments(['examples/example']);

      expect(written!.segments, ['examples/example']);
    });

    test('a namespace can be emptied, which is how a lifetime ends', () {
      // A knob belongs to the entry, so it cannot outlive one. The nesting says
      // which namespace sits below which segment; this is the write that acts
      // on it.
      Address? written;
      AddressHandle(
        AddressView(
          _catalog(axes: {'axis.theme': 'dark', 'knob.count': '3'}),
          segmentOffset: 1,
        ),
        (a) => written = a,
      ).update(segments: ['demo/team.dart#list'], drop: const {'knob'});

      expect(written!.segments, ['app', 'demo/team.dart#list']);
      expect(
        written!.axes,
        {'axis.theme': 'dark'},
        reason: 'an axis belongs to the shell and outlives the entry',
      );
    });

    test('a parameter is written into its own namespace', () {
      Address? written;
      var handle = AddressHandle(
        AddressView(_catalog(axes: {'axis.theme': 'dark'}), namespace: 'knob'),
        (a) => written = a,
      );

      handle.setParam('count', '3');

      expect(written!.axes, {'axis.theme': 'dark', 'knob.count': '3'});
    });

    test('null removes, and other namespaces are untouched', () {
      Address? written;
      AddressHandle(
        AddressView(
          _catalog(axes: {'axis.theme': 'dark', 'knob.count': '3'}),
          namespace: 'knob',
        ),
        (a) => written = a,
      ).setParam('count', null);

      expect(written!.axes, {'axis.theme': 'dark'});
    });
  });

  group('a widget rebuilds for what it read, and nothing else', () {
    late ValueNotifier<Address> address;
    late Map<String, int> builds;

    /// root → package scope → axes scope → entry scope, with a probe at each
    /// depth reading exactly one thing.
    Widget tree() => AddressRoot(
      address: address,
      onChanged: (next) => address.value = next,
      child: Column(
        textDirection: TextDirection.ltr,
        children: [
          _Probe('pkg', (c) => AddressScope.segment(c, 0), builds),
          AddressScope(
            eat: 1,
            child: Column(
              textDirection: TextDirection.ltr,
              children: [
                _Probe('entry', (c) => AddressScope.segment(c, 0), builds),
                AddressScope(
                  namespace: 'axis',
                  child: Column(
                    textDirection: TextDirection.ltr,
                    children: [
                      _Probe(
                        'theme',
                        (c) => AddressScope.param(c, 'theme'),
                        builds,
                      ),
                      AddressScope(
                        eat: 1,
                        namespace: 'knob',
                        child: Column(
                          textDirection: TextDirection.ltr,
                          children: [
                            _Probe(
                              'count',
                              (c) => AddressScope.param(c, 'count'),
                              builds,
                            ),
                            _Probe(
                              'size',
                              (c) => AddressScope.param(c, 'size'),
                              builds,
                            ),
                            _Probe('inert', (_) => 'x', builds),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    setUp(() {
      address = ValueNotifier(
        _catalog(axes: {'axis.theme': 'dark', 'knob.count': '3'}),
      );
      builds = {};
    });

    tearDown(() => address.dispose());

    testWidgets('one knob moves one widget', (tester) async {
      await tester.pumpWidget(tree());
      expect(find.text('count=3'), findsOneWidget);
      var before = {...builds};

      address.value = _catalog(axes: {'axis.theme': 'dark', 'knob.count': '4'});
      await tester.pump();

      expect(find.text('count=4'), findsOneWidget);
      expect(builds['count'], before['count']! + 1);
      // This is the whole point: dragging a slider must not redraw the app.
      expect(builds['size'], before['size']);
      expect(builds['theme'], before['theme']);
      expect(builds['pkg'], before['pkg']);
      expect(builds['entry'], before['entry']);
      expect(builds['inert'], before['inert']);
    });

    testWidgets('a segment change leaves the parameters alone', (tester) async {
      await tester.pumpWidget(tree());
      var before = {...builds};

      address.value = _catalog(
        entry: 'demo/team.dart#list',
        axes: {'axis.theme': 'dark', 'knob.count': '3'},
      );
      await tester.pump();

      expect(builds['count'], before['count']);
      expect(builds['theme'], before['theme']);
    });

    testWidgets('an unrelated namespace changes nothing', (tester) async {
      await tester.pumpWidget(tree());
      var before = {...builds};

      address.value = _catalog(
        axes: {'axis.theme': 'dark', 'knob.count': '3', 'other.x': '1'},
      );
      await tester.pump();

      expect(builds, before);
    });

    testWidgets('a widget that reads nothing never rebuilds', (tester) async {
      // The scope machinery rewraps a child it already has, so an address
      // change does not walk the subtree looking for who cares.
      await tester.pumpWidget(tree());
      var before = builds['inert'];

      for (var i = 0; i < 5; i++) {
        address.value = _catalog(axes: {'knob.count': '$i'});
        await tester.pump();
      }

      expect(builds['inert'], before);
    });

    testWidgets('a write from inside comes back down', (tester) async {
      await tester.pumpWidget(tree());

      var context = tester.element(find.text('count=3'));
      AddressScope.write(context).setParam('count', '9');
      await tester.pump();

      expect(find.text('count=9'), findsOneWidget);
      expect(address.value.axes['knob.count'], '9');
    });
  });
}
