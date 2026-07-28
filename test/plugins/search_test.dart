import 'package:flutterware/plugins.dart';
import 'package:test/test.dart';

/// The generic tier: what every plugin gets without writing search code.
///
/// Shaped like the UI catalog's real report — children per package, declared
/// actions, and a view of sections wrapping item lists — because the point of
/// this walk is that it works on a report it has never been told about.
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
  view: PluginView([
    ViewSection('app', [
      ViewItems([
        _entry('Dashboard', 'demo/dashboard.dart#dashboard'),
        _entry('Counter', 'demo/counter.dart#counter'),
        _entry('Does not compile', 'demo/broken.dart#broken'),
      ]),
      ViewSection('Diagnostics', [ViewText('demo/broken.dart: 1 error')]),
    ]),
    ViewSection('examples/example', [
      ViewField('Entrypoint', 'demo/main.dart'),
      ViewTable(
        ['Package', 'Version'],
        [
          ['collection', '1.19.1'],
        ],
      ),
    ]),
  ]),
);

ViewItem _entry(String name, String id) => ViewItem(
  name,
  detail: id,
  address: Address(
    worktree: 'main',
    plugin: 'flutterware.ui_catalog',
    segments: ['app', id],
  ),
);

void main() {
  group('what is offered', () {
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
      expect(package.address.segments, ['examples/example']);
      expect(package.subtitle, 'no entries', reason: 'the status comes along');
    });

    test('nothing for an empty query', () {
      expect(searchReport(_report(), '   '), isEmpty);
    });
  });

  group('what is refused, because it is not a destination', () {
    test('an action, however well it matches', () {
      // "Screenshot" is a verb. Offering it beside a list of places is a
      // category error, and some actions are declared `danger`.
      expect(searchReport(_report(), 'screenshot'), isEmpty);
      // Its description, too — "Render one entry to a PNG".
      expect(searchReport(_report(), 'render'), isEmpty);
    });

    test('free text, such as a diagnostic', () {
      expect(searchReport(_report(), '1 error'), isEmpty);
    });

    test('a field', () {
      expect(searchReport(_report(), 'entrypoint'), isEmpty);
    });

    test('a table row, which has nowhere to put an address', () {
      expect(searchReport(_report(), 'collection'), isEmpty);
    });

    test('an item that declares no address', () {
      var report = PluginReport(
        id: 'p',
        label: 'P',
        view: const PluginView([
          ViewItems([ViewItem('Orphan', detail: 'nowhere to go')]),
        ]),
      );
      expect(searchReport(report, 'orphan'), isEmpty);
    });

    test('a section heading, which is a heading and not a place', () {
      // 'Diagnostics' titles a section; selecting it would mean nothing. Its
      // children are still walked.
      expect(searchReport(_report(), 'diagnostics'), isEmpty);
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
            'a title match carries highlight offsets; a detail match does not',
      );
    });

    test('a detail match still lands, for an id you half remember', () {
      // "broken" appears only in the entry id, never in the display name.
      var hit = searchReport(
        _report(),
        'broken',
      ).firstWhere((h) => h.title == 'Does not compile');

      expect(hit.subtitle, 'demo/broken.dart#broken');
      expect(hit.matched, isEmpty);
    });

    test('a detail matches as a substring, never as a subsequence', () {
      // 'dmo' is a subsequence of the detail "demo/dashboard.dart#dashboard"
      // and of no title — matching it is how a palette fills with noise. A
      // real substring of the same detail still lands.
      expect(searchReport(_report(), 'dashboard.dart'), isNotEmpty);
      expect(searchReport(_report(), 'dmo'), isEmpty);
    });

    test('the plugin outranks an entry matching as well', () {
      var hits = searchReport(_report(), 'ca');
      expect(hits.first.reason, SearchReason.plugin);
    });

    test('but a better match beats the weight', () {
      var hits = searchReport(_report(), 'dash');
      expect(hits.first.title, 'Dashboard');
    });

    test('hits come back sorted', () {
      var scores = [for (var hit in searchReport(_report(), 'a')) hit.score];
      expect(scores, isNotEmpty);
      expect(scores, orderedEquals(scores.toList()..sort((a, b) => b - a)));
    });
  });

  group('addressing', () {
    test('an entry is followed to itself, not to its plugin', () {
      var hit = searchReport(_report(), 'dash', worktree: 'main').first;

      expect(hit.address.segments, ['app', 'demo/dashboard.dart#dashboard']);
      expect(
        hit.address.toString(),
        'fw://main/flutterware.ui_catalog/app/demo%2Fdashboard.dart%23dashboard',
      );
    });

    test('the plugin and its packages carry the worktree', () {
      var hits = searchReport(_report(), 'catalog', worktree: 'feature-x');
      expect(hits, isNotEmpty);
      for (var hit in hits) {
        expect(hit.address.worktree, 'feature-x', reason: hit.title);
      }
    });

    test('an address round-trips through its string form', () {
      var hit = searchReport(_report(), 'dash', worktree: 'main').first;
      expect(Address.parse(hit.address.toString()), hit.address);
    });
  });

  group('grouping and deduplication', () {
    test('every hit is grouped under the plugin label', () {
      var hits = searchReport(_report(), 'a');
      expect(hits.map((h) => h.group).toSet(), {'UI catalog'});
    });

    test('the same entry listed twice collapses to one', () {
      var entry = _entry('Dashboard', 'demo/dashboard.dart#dashboard');
      var report = PluginReport(
        id: 'flutterware.ui_catalog',
        label: 'UI catalog',
        view: PluginView([
          ViewSection('by name', [
            ViewItems([entry]),
          ]),
          ViewSection('by group', [
            ViewItems([entry]),
          ]),
        ]),
      );

      expect(searchReport(report, 'dash'), hasLength(1));
    });
  });

  group('fuzzyMatch', () {
    test('matches a subsequence and reports where', () {
      // D-a-s-h-b-o-a-r-d
      expect(fuzzyMatch('dsh', 'Dashboard')!.matched, [0, 2, 3]);
    });

    test('refuses when a character is missing or out of order', () {
      expect(fuzzyMatch('xyz', 'Dashboard'), isNull);
      expect(fuzzyMatch('hsad', 'Dashboard'), isNull);
    });

    test('a symbol after # starts a word', () {
      expect(
        fuzzyMatch('t', 'x#team')!.score,
        greaterThan(fuzzyMatch('t', 'xxteam')!.score),
      );
    });

    test('it takes the first subsequence, not the best one', () {
      // The documented greed: `t` lands in "dart" and never reaches the symbol
      // after the `#`. Pinned because it is the ceiling on ranking quality.
      // a . d a r t # t e a m
      // 0 1 2 3 4 5 6 7 8 9 10
      expect(fuzzyMatch('t', 'a.dart#team')!.matched, [5]);
    });

    test('an empty query is neutral, not a refusal', () {
      expect(fuzzyMatch('', 'anything')?.score, 0);
    });
  });
}
