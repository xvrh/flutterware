import 'dart:async';

import 'package:flutterware_app/src/previews/catalog_entry.dart';
import 'package:flutterware_app/src/previews/catalog_session.dart';
import 'package:flutterware_app/src/previews/protocol.dart';
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
  _retryMarkerTests();
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

  group('a click is a request too', () {
    test('so what the address is taken to want follows the selection', () {
      // The panel writes the address back from a post-frame callback, so
      // between a click and the next frame boundary this still named the entry
      // you came from. Anything calling `_applyWanted` in that window — and a
      // `CatalogChanged` from the daemon does — switched you straight back.
      var session = _session()
        ..entries = [
          _entry('demo/a.dart', 'alpha'),
          _entry('demo/b.dart', 'beta'),
        ]
        ..phase = CatalogSessionPhase.ready;

      session.wantedEntryId = 'demo/a.dart#alpha';
      unawaited(session.switchTo(_entry('demo/b.dart', 'beta')));

      expect(session.selected?.id, 'demo/b.dart#beta');
      expect(
        session.wantedEntryId,
        'demo/b.dart#beta',
        reason: 'or the next change event puts you back on alpha',
      );

      session.dispose();
    });

    test('and a quarantined entry is wanted like any other', () {
      // The one this was actually reported on. Asking for a quarantined entry
      // *is* the retry, so the daemon announces the change before it has
      // compiled anything — which is why this race was so easy to lose here
      // and nowhere else.
      var broken = _entry('demo/broken.dart', 'nope');
      var session = _session()
        ..entries = [_entry('demo/a.dart', 'alpha')]
        ..quarantined = [QuarantinedEntry(entry: broken, error: 'boom')]
        ..phase = CatalogSessionPhase.ready;

      session.wantedEntryId = 'demo/a.dart#alpha';
      unawaited(session.switchTo(broken));

      expect(session.wantedEntryId, broken.id);
      expect(session.wantedEntry?.id, broken.id);
      expect(session.missingEntryId, isNull);

      session.dispose();
    });
  });
}

void _retryMarkerTests() {
  group('retrying a quarantined entry', () {
    var broken = _entry('demo/broken.dart', 'nope');

    test('keeps saying it is broken until the retry has decided', () {
      var session = _session()
        ..entries = [_entry('demo/a.dart', 'alpha')]
        ..quarantined = [QuarantinedEntry(entry: broken, error: 'boom')]
        ..phase = CatalogSessionPhase.ready;
      expect(session.compileErrorFor(broken), 'boom');

      unawaited(session.switchTo(broken));
      // What the daemon announces the instant it is asked: the entry is out of
      // the quarantine and back among the buildable ones, before a single line
      // has been compiled.
      session
        ..entries = [_entry('demo/a.dart', 'alpha'), broken]
        ..quarantined = [];

      expect(
        session.compileErrorFor(broken),
        'boom',
        reason: 'the row must not claim to be healthy while it is being tried',
      );

      session.dispose();
    });

    test('and says nothing about an entry nobody asked about', () {
      var session = _session()
        ..entries = [_entry('demo/a.dart', 'alpha')]
        ..quarantined = [QuarantinedEntry(entry: broken, error: 'boom')]
        ..phase = CatalogSessionPhase.ready;

      unawaited(session.switchTo(_entry('demo/a.dart', 'alpha')));
      session.quarantined = [];

      expect(session.compileErrorFor(broken), isNull);
      session.dispose();
    });
  });
}
