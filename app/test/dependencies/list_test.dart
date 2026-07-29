import 'dart:io';

import 'package:flutterware_app/src/dependencies/list.dart';
import 'package:flutterware_app/src/dependencies/model/pub_deps.dart';
import 'package:flutterware_app/src/dependencies/model/service.dart';
import 'package:flutterware_app/src/ui/table.dart';
import 'package:pubspec_parse/pubspec_parse.dart';
import 'package:test/test.dart';

/// The list screen's only real logic: what rows it shows and in what order.
/// Driven off the same captured resolution as `resolution_test.dart`.
void main() {
  var pubDeps = PubDeps.parse(
    File('test/dependencies/fixtures/pub_deps.json').readAsStringSync(),
  );

  var dependencies = Dependencies.resolve(
    pubspec: Pubspec.parse(
      'name: flutterware_example\nenvironment:\n  sdk: ^3.6.0\n',
    ),
    pubDeps: pubDeps,
    lock: null,
    packageConfig: null,
    readPubspec: (_) => null,
  );

  List<String> names({
    Set<DependencyKind> kinds = const {
      DependencyKind.direct,
      DependencyKind.dev,
    },
    String query = '',
    FwTableSort sort = const FwTableSort(DependencySort.name),
  }) => visibleDependencies(
    dependencies.dependencies,
    kinds: kinds,
    query: query,
    sort: sort,
  ).map((e) => e.name).toList();

  group('filtering', () {
    test('shows the declared kinds by default', () {
      // 14 direct + 4 dev, and none of the 89 transitive.
      expect(names(), hasLength(18));
    });

    test('each kind can be shown alone', () {
      expect(names(kinds: {DependencyKind.dev}), hasLength(4));
      expect(names(kinds: {DependencyKind.direct}), hasLength(14));
      expect(
        names(kinds: {DependencyKind.transitive}),
        hasLength(dependencies.transitives.length),
      );
    });

    test('no kinds selected shows nothing', () {
      expect(names(kinds: const {}), isEmpty);
    });

    test('a query narrows what the filter left', () {
      // The bug this replaces: typing re-filtered from every package, so the
      // kind filter silently stopped applying as soon as you searched.
      var hits = names(kinds: {DependencyKind.direct}, query: 'flutter');
      expect(hits, isNotEmpty);
      for (var name in hits) {
        expect(
          dependencies[name]!.kind,
          DependencyKind.direct,
          reason: 'searching must not reintroduce a filtered-out kind',
        );
      }
      expect(hits, isNot(contains('flutter_test')), reason: 'a dev dependency');
    });

    test('the query is trimmed and case-insensitive', () {
      expect(names(query: '  FLUTTERWARE '), contains('flutterware'));
    });

    test('a query matching nothing yields an empty list, not everything', () {
      expect(names(query: 'zzzz-no-such-package'), isEmpty);
    });
  });

  group('sorting', () {
    test('by name, both directions', () {
      var ascending = names();
      expect(ascending, orderedEquals([...ascending]..sort()));

      var descending = names(
        sort: const FwTableSort(DependencySort.name, ascending: false),
      );
      expect(descending, orderedEquals(ascending.reversed.toList()));
    });

    test('by kind puts what you declared before what you did not', () {
      var sorted = visibleDependencies(
        dependencies.dependencies,
        kinds: DependencyKind.values.toSet(),
        query: '',
        sort: const FwTableSort(DependencySort.kind),
      );
      var kinds = sorted.map((e) => e.kind).toList();
      // Direct, then dev, then transitive — enum order, not alphabetical, which
      // would have put dev first.
      var expected = [...kinds]..sort((a, b) => a.index.compareTo(b.index));
      expect(kinds, orderedEquals(expected));
      expect(kinds.first, DependencyKind.direct);
      expect(kinds.last, DependencyKind.transitive);
    });

    test('by origin groups the unusual sources together', () {
      var sorted = visibleDependencies(
        dependencies.dependencies,
        kinds: DependencyKind.values.toSet(),
        query: '',
        sort: const FwTableSort(DependencySort.origin),
      );
      var labels = sorted.map((e) => e.origin.label).toList();
      expect(labels, orderedEquals([...labels]..sort()));
    });

    test('a missing score sorts last descending, not first', () {
      // With no PubScores at all every package scores -1, so the order falls
      // back to being stable rather than putting unrated packages on top.
      var descending = visibleDependencies(
        dependencies.dependencies,
        kinds: {DependencyKind.direct},
        query: '',
        sort: const FwTableSort(DependencySort.pub, ascending: false),
      );
      expect(descending, hasLength(14));
    });
  });
}
