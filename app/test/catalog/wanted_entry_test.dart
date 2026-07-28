import 'package:flutterware_app/src/catalog/catalog_entry.dart';
import 'package:flutterware_app/src/catalog/catalog_session.dart';
import 'package:flutterware_app/src/catalog/protocol.dart';
import 'package:flutter_test/flutter_test.dart';

CatalogEntry _entry(String path, String symbol) => CatalogEntry(
  path: path,
  symbol: symbol,
  annotation: 'Demo()',
  name: symbol,
);

/// No daemon here on purpose. What is under test is the *resolution* — which
/// entry an address names and what happens when it names one that is not there
/// yet — and none of that should need a compiler running to be true.
CatalogSession _session() => CatalogSession(
  appPackageRoot: '/app',
  flutterSdkRoot: '/flutter',
  projectRoot: '/project',
);

void main() {
  group('the address names an entry before the daemon has reported', () {
    test('and the request is held rather than dropped', () {
      var session = _session();

      // Clicking a search hit is what *starts* the compile it would otherwise
      // be waiting for, so this always arrives first on a cold start.
      session.wantedEntryId = 'demo/avatar.dart#members';
      expect(session.wantedEntry, isNull);

      session.entries = [_entry('demo/avatar.dart', 'members')];
      expect(session.wantedEntry?.id, 'demo/avatar.dart#members');

      session.dispose();
    });

    test('and says nothing about it being missing meanwhile', () {
      // Otherwise "no such entry" is the first thing every cold start says
      // about a perfectly good address.
      var session = _session()..wantedEntryId = 'demo/avatar.dart#members';

      expect(session.phase, isNot(CatalogSessionPhase.ready));
      expect(session.missingEntryId, isNull);

      session.dispose();
    });
  });

  group('once there is a catalog to resolve against', () {
    test('an entry that does not exist is reported, not repaired', () {
      var session = _session()
        ..entries = [_entry('demo/avatar.dart', 'members')]
        ..phase = CatalogSessionPhase.ready
        ..wantedEntryId = 'demo/nope.dart#gone';

      expect(session.missingEntryId, 'demo/nope.dart#gone');
      expect(
        session.wantedEntryId,
        'demo/nope.dart#gone',
        reason: 'the address is left naming what it named',
      );

      session.dispose();
    });

    test(
      'an entry that does not compile still resolves, so its error shows',
      () {
        // Being sent somewhere else instead is how a broken build turns into
        // "the link is wrong".
        var broken = _entry('demo/broken.dart', 'broken');
        var session = _session()
          ..entries = []
          ..quarantined = [
            QuarantinedEntry(entry: broken, error: 'expected an identifier'),
          ]
          ..phase = CatalogSessionPhase.ready
          ..wantedEntryId = broken.id;

        expect(session.wantedEntry?.id, broken.id);
        expect(session.missingEntryId, isNull);

        session.dispose();
      },
    );

    test('asking selects at once, not when the compile finishes', () {
      // The bug this pins: `CatalogView` reloads "whatever is selected" the
      // moment it mounts, and switches are serialised. With `selected` only
      // assigned at the far end of the queue, opening the catalog at an address
      // queued the address's switch, then the mount queued a switch back to the
      // entry before it — and the second one won. Arriving from search landed
      // on the last entry you had open, but only when the panel was not already
      // mounted, which is why it looked like search worked.
      var members = _entry('demo/avatar.dart', 'members');
      var session = _session()
        ..entries = [_entry('demo/team.dart', 'team'), members]
        ..phase = CatalogSessionPhase.ready;

      session.switchTo(session.entries.first);
      session.wantedEntryId = members.id;

      expect(session.selected?.id, members.id);

      // What the mount then reloads. Reading it must not walk backwards.
      expect((session.selected ?? session.active)?.id, members.id);

      session.dispose();
    });

    test('naming no entry at all is not a failure', () {
      var session = _session()
        ..entries = [_entry('demo/avatar.dart', 'members')]
        ..phase = CatalogSessionPhase.ready;

      expect(session.wantedEntry, isNull);
      expect(session.missingEntryId, isNull);

      session.dispose();
    });
  });
}
