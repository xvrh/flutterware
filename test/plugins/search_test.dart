import 'package:flutterware/plugins.dart';
import 'package:test/test.dart';

/// The generic tier: what every plugin gets without writing search code.
///
/// The report below is shaped like the UI catalog's real one — children per
/// package, declared actions, and a view of sections wrapping item lists —
/// because the point of this walk is that it works on a report it has never
/// been told about.
PluginReport _report() => PluginReport(
  id: 'flutterware.ui_catalog',
  label: 'UI catalog',
  children: const [
    PluginChild(id: 'app', label: 'app'),
    PluginChild(
      id: 'examples/example',
      label: 'examples/example',
      status: Status.warn('no entries'),
    ),
  ],
  actions: const [
    PluginAction('entries', 'Entries', description: 'Every catalog entry'),
    PluginAction(
      'screenshot',
      'Screenshot',
      description: 'Render one entry to a PNG',
    ),
  ],
  view: const PluginView([
    ViewSection('app', [
      ViewItems([
        ViewItem('Dashboard', detail: 'demo/dashboard.dart#dashboard'),
        ViewItem('Counter', detail: 'demo/counter.dart#counter'),
        ViewItem('Does not compile', detail: 'demo/broken.dart#broken'),
      ]),
      ViewSection('Diagnostics', [ViewText('demo/broken.dart: 1 error')]),
    ]),
    ViewSection('examples/example', [
      ViewField('Entrypoint', 'demo/main.dart'),
      ViewTable(
        ['Package', 'Version'],
        [
          ['collection', '1.19.1'],
          ['path', '1.9.1'],
        ],
      ),
    ]),
  ]),
);

void main() {
  group('the walk finds', () {
    test('an entry by name, which is the case that motivated this', () {
      var hits = searchReport(_report(), 'dash', worktree: 'main');

      expect(hits, isNotEmpty);
      expect(hits.first.title, 'Dashboard');
      expect(hits.first.reason, SearchReason.item);
      expect(hits.first.subtitle, 'demo/dashboard.dart#dashboard');
    });

    test('the plugin itself', () {
      var hits = searchReport(_report(), 'catalog', worktree: 'main');
      expect(hits.first.title, 'UI catalog');
      expect(hits.first.reason, SearchReason.plugin);
    });

    test('a package, addressed one segment deeper', () {
      var hits = searchReport(_report(), 'examples', worktree: 'main');
      var package = hits.firstWhere((h) => h.reason == SearchReason.package);

      expect(package.title, 'examples/example');
      expect(package.address.plugin, 'flutterware.ui_catalog');
      expect(package.address.segments, ['examples/example']);
      expect(package.subtitle, 'no entries', reason: 'the status comes along');
    });

    test('an action, carried as a verb rather than a path', () {
      var hits = searchReport(_report(), 'screensh', worktree: 'main');
      var hit = hits.first;

      expect(hit.reason, SearchReason.action);
      expect(hit.action, 'screenshot');
      expect(
        hit.address.segments,
        isEmpty,
        reason: 'an action is run at the plugin, not at a path of its own',
      );
    });

    test('a field, a table row and free text', () {
      var report = _report();
      expect(
        searchReport(report, 'entrypoint').first.reason,
        SearchReason.field,
      );
      expect(searchReport(report, 'collection').first.reason, SearchReason.row);
      expect(searchReport(report, '1 error').first.reason, SearchReason.text);
    });

    test('nothing for an empty query', () {
      expect(searchReport(_report(), '   '), isEmpty);
    });
  });

  group('ranking', () {
    test('a name beats the same letters in a detail', () {
      var hits = searchReport(_report(), 'counter');
      expect(hits.first.title, 'Counter');
      expect(
        hits.first.matched,
        isNotEmpty,
        reason:
            'a title match carries highlight offsets; a detail match does '
            'not',
      );
    });

    test('a detail match still lands, for an id you half remember', () {
      // "broken" appears only in the entry id, never in the display name.
      var hits = searchReport(_report(), 'broken');
      var hit = hits.firstWhere((h) => h.title == 'Does not compile');

      expect(hit.subtitle, 'demo/broken.dart#broken');
      expect(hit.matched, isEmpty);
    });

    test('a detail matches as a substring, never as a subsequence', () {
      // "Render one entry to a PNG" contains r-e-n-d-e-r contiguously and also
      // contains d-a-s-h scattered across it. Only the first is a match; the
      // second is how a palette fills with prose that happens to share letters.
      var hits = searchReport(_report(), 'render');
      expect(hits.map((h) => h.action), contains('screenshot'));

      var noise = searchReport(_report(), 'dash');
      expect(
        noise.map((h) => h.reason),
        isNot(contains(SearchReason.action)),
        reason: 'no action description should match "dash"',
      );
      expect(noise.first.title, 'Dashboard');
    });

    test('the plugin outranks a view row matching as well', () {
      // Both "UI catalog" and the Diagnostics text contain these letters.
      var hits = searchReport(_report(), 'ca');
      expect(hits.first.reason, SearchReason.plugin);
    });

    test('but a better match beats the weight', () {
      // The plugin does not match "dash" at all, so no weight rescues it.
      var hits = searchReport(_report(), 'dash');
      expect(hits.first.title, 'Dashboard');
    });

    test('hits come back sorted', () {
      var scores = [for (var hit in searchReport(_report(), 'e')) hit.score];
      expect(scores, isNotEmpty);
      expect(scores, orderedEquals(scores.toList()..sort((a, b) => b - a)));
    });
  });

  group('addressing', () {
    test('every hit carries the worktree it came from', () {
      var hits = searchReport(_report(), 'e', worktree: 'feature-x');
      expect(hits, isNotEmpty);
      for (var hit in hits) {
        expect(hit.address.worktree, 'feature-x', reason: hit.title);
        expect(hit.address.plugin, 'flutterware.ui_catalog', reason: hit.title);
      }
    });

    test('a relative address survives an omitted worktree', () {
      var hits = searchReport(_report(), 'dash');
      expect(hits.first.address.isRelative, isTrue);
    });

    test('a view hit addresses the plugin, which is the documented floor', () {
      // The limitation, pinned: `ViewItem` has no address, so the generic
      // walk can find "Dashboard" but only navigate to the catalog. A plugin
      // that knows better contributes its own hits.
      var hit = searchReport(_report(), 'dash').first;
      expect(hit.address.segments, isEmpty);
    });

    test('an address round-trips through its string form', () {
      var hit = searchReport(
        _report(),
        'examples',
        worktree: 'main',
      ).firstWhere((h) => h.reason == SearchReason.package);
      expect(Address.parse(hit.address.toString()), hit.address);
    });
  });

  group('grouping', () {
    test('every hit is grouped under the plugin label', () {
      var hits = searchReport(_report(), 'e');
      expect(hits.map((h) => h.group).toSet(), {'UI catalog'});
    });
  });

  group('deduplication', () {
    test('a row repeated across packages collapses to one', () {
      // What the dependencies plugin really does: the same package listed once
      // per declared package, identical in every way a user can see.
      var report = PluginReport(
        id: 'flutterware.dependencies',
        label: 'Dependencies',
        view: const PluginView([
          ViewSection('.', [
            ViewTable(
              ['Package', 'Version'],
              [
                ['collection', '1.19.1'],
              ],
            ),
          ]),
          ViewSection('app', [
            ViewTable(
              ['Package', 'Version'],
              [
                ['collection', '1.19.1'],
              ],
            ),
          ]),
        ]),
      );

      var hits = searchReport(report, 'collection');
      expect(hits.where((h) => h.title == 'collection'), hasLength(1));
    });

    test('but rows differing in their detail both survive', () {
      var report = PluginReport(
        id: 'flutterware.dependencies',
        label: 'Dependencies',
        view: const PluginView([
          ViewTable(
            ['Package', 'Version'],
            [
              ['collection', '1.19.1'],
              ['collection', '1.20.0'],
            ],
          ),
        ]),
      );

      expect(searchReport(report, 'collection'), hasLength(2));
    });
  });

  group('fuzzyMatch', () {
    test('matches a subsequence and reports where', () {
      // D-a-s-h-b-o-a-r-d
      var match = fuzzyMatch('dsh', 'Dashboard')!;
      expect(match.matched, [0, 2, 3]);
    });

    test('refuses when a character is missing or out of order', () {
      expect(fuzzyMatch('xyz', 'Dashboard'), isNull);
      expect(fuzzyMatch('hsad', 'Dashboard'), isNull);
    });

    test('a symbol after # starts a word', () {
      // Entry ids are `file.dart#symbol`, and the symbol is what gets typed.
      expect(
        fuzzyMatch('t', 'x#team')!.score,
        greaterThan(fuzzyMatch('t', 'xxteam')!.score),
      );
    });

    test('it takes the first subsequence, not the best one', () {
      // The documented greed: `t` lands in "dart" and never reaches the symbol
      // after the `#`, so the boundary bonus above cannot rescue it. Pinned
      // because it is the ceiling on ranking quality — lifting it means
      // backtracking, and that is a deliberate later decision.
      // a . d a r t # t e a m
      // 0 1 2 3 4 5 6 7 8 9 10
      expect(fuzzyMatch('t', 'a.dart#team')!.matched, [5]);
    });

    test('an empty query is neutral, not a refusal', () {
      expect(fuzzyMatch('', 'anything')?.score, 0);
    });
  });
}
