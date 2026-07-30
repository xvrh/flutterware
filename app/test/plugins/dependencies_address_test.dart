import 'package:flutterware_app/src/plugins/native/dependencies_address.dart';
import 'package:test/test.dart';

/// The round trip is the contract.
///
/// The list writes an address, the panel reads it back to decide what to show.
/// If the two directions disagree the app navigates, nothing throws, and you
/// end up on the wrong screen — which is what this pair exists to make
/// impossible.
void main() {
  group('a place survives the trip', () {
    var places = [
      const DependencyPlace('app'),
      const DependencyPlace('app', dependency: 'collection'),
      const DependencyPlace('app', upgrade: true),
      const DependencyPlace('examples/example', dependency: 'flutter_lints'),
    ];

    for (var place in places) {
      test('$place', () {
        expect(
          dependencyPlace(
            dependencySegments(
              place.package,
              dependency: place.dependency,
              upgrade: place.upgrade,
            ),
          ),
          place,
        );
      });
    }
  });

  group('what the segments look like', () {
    test('a package on its own is one segment', () {
      expect(dependencySegments('app'), ['app']);
    });

    test('a dependency is named after a literal, not by position', () {
      // `packages` is what tells a dependency apart from `upgrade`; without it
      // a dependency called "upgrade" would open the wrong screen.
      expect(dependencySegments('app', dependency: 'upgrade'), [
        'app',
        'packages',
        'upgrade',
      ]);
      expect(
        dependencyPlace(['app', 'packages', 'upgrade']),
        const DependencyPlace('app', dependency: 'upgrade'),
      );
    });

    test('a package path keeps its slashes, as one segment', () {
      expect(dependencySegments('examples/example', dependency: 'meta'), [
        'examples/example',
        'packages',
        'meta',
      ]);
    });

    test('upgrade wins over a dependency, since it is its own screen', () {
      expect(dependencySegments('app', dependency: 'meta', upgrade: true), [
        'app',
        'upgrade',
      ]);
    });
  });

  group('an address that names something else', () {
    test('with no segments at all names no place', () {
      expect(dependencyPlace([]), isNull);
    });

    test('with a tail this shape does not know reads as the list', () {
      // Written against an older shape, or typed. The package's own screen is
      // the least surprising place to be left.
      expect(
        dependencyPlace(['app', 'nonsense']),
        const DependencyPlace('app'),
      );
      expect(
        dependencyPlace(['app', 'packages', 'a', 'b']),
        const DependencyPlace('app'),
      );
    });

    test('naming packages and nothing after it reads as the list', () {
      expect(
        dependencyPlace(['app', 'packages']),
        const DependencyPlace('app'),
      );
    });
  });
}
