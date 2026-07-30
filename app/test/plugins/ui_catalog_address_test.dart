import 'package:flutterware_app/src/plugins/native/ui_catalog_address.dart';
import 'package:test/test.dart';

/// The round trip is the contract.
///
/// Search writes an address, the panel reads it, and the panel writes back what
/// it landed on. If the two directions disagree by so much as a slash the app
/// navigates, nothing throws, and you end up on the wrong demo — which is
/// exactly the failure this pair was extracted to make impossible.
void main() {
  _addressMovedTests();
  const ids = [
    'demo/dashboard.dart#dashboard',
    'tool/catalog/demos/avatar_tile.dart#avatarTileMembers',
    'main.dart#root',
    'a/b/c/d/e.dart#deeplyNested',
  ];

  group('entry ids survive the trip', () {
    for (var id in ids) {
      test(id, () {
        var place = catalogPlace(catalogSegments('app', id));
        expect(place, CatalogPlace('app', entryId: id));
      });
    }

    test('and so does a package path containing slashes', () {
      var segments = catalogSegments('examples/example', 'demo/x.dart#x');
      // The package is one segment; only the entry id is spread.
      expect(segments, ['examples/example', 'demo', 'x.dart#x']);
      expect(
        catalogPlace(segments),
        CatalogPlace('examples/example', entryId: 'demo/x.dart#x'),
      );
    });
  });

  group('a package with no entry', () {
    test('is written as one segment', () {
      expect(catalogSegments('app'), ['app']);
    });

    test('reads back as a package and no entry', () {
      expect(catalogPlace(['app']), const CatalogPlace('app'));
      expect(catalogPlace(['app'])!.entryId, isNull);
    });

    test('and an empty entry id is the same as none', () {
      expect(catalogSegments('app', ''), ['app']);
    });
  });

  test('an address naming nothing is nowhere, not a package called ""', () {
    expect(catalogPlace([]), isNull);
  });

  test('the entry id is split so the address stays readable', () {
    // `…/app/tool/catalog/demos/avatar.dart%23members`, not one blob of %2F.
    expect(catalogSegments('app', 'tool/catalog/demos/avatar.dart#members'), [
      'app',
      'tool',
      'catalog',
      'demos',
      'avatar.dart#members',
    ]);
  });
}

void _addressMovedTests() {
  group('addressMoved', () {
    test('a first call always hands over, including a null', () {
      expect(
        addressMoved(
          hasFollowed: false,
          sessionChanged: false,
          followed: null,
          place: null,
        ),
        isTrue,
      );
    });

    test('restating the same address does not', () {
      // The bug. `didChangeDependencies` fires for its own reasons, and the
      // address lags a local selection by a frame — so this is the *old* entry
      // being pushed onto a session that has already moved on.
      expect(
        addressMoved(
          hasFollowed: true,
          sessionChanged: false,
          followed: 'demo/a.dart#alpha',
          place: 'demo/a.dart#alpha',
        ),
        isFalse,
      );
    });

    test('a genuine move does', () {
      expect(
        addressMoved(
          hasFollowed: true,
          sessionChanged: false,
          followed: 'demo/a.dart#alpha',
          place: 'demo/b.dart#beta',
        ),
        isTrue,
      );
    });

    test('and a new session is told even when the address stood still', () {
      // It has been told nothing at all, so "unchanged" means nothing to it.
      expect(
        addressMoved(
          hasFollowed: true,
          sessionChanged: true,
          followed: 'demo/a.dart#alpha',
          place: 'demo/a.dart#alpha',
        ),
        isTrue,
      );
    });
  });
}
