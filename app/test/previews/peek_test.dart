import 'dart:async';
import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware/plugins.dart';
import 'package:flutterware_app/src/address/address_scope.dart';
import 'package:flutterware_app/src/previews/catalog_view.dart';
import 'package:flutterware_app/src/embedder/guest_vm_service.dart';
import 'package:flutterware_app/src/previews/catalog_entry.dart';
import 'package:flutterware_app/src/previews/catalog_session.dart';
import 'package:flutterware_app/src/previews/inspect_client.dart';
import 'package:flutterware_app/src/previews/protocol.dart';
import 'package:vm_service/vm_service.dart';

/// A guest that answers `showEntry` with what it is actually showing, as the
/// real one does — see `show_entry_test.dart`, which this is the peek half of.
class _FakeGuest {
  _FakeGuest({required this.holds, required this.showing}) {
    service = VmService(_toClient.stream, _onRequest);
  }

  final Set<String> holds;
  String showing;

  /// Every entry this guest has been asked for, in order — a peek that put
  /// the same picture back twice is invisible to [showing] and obvious here.
  final asked = <String>[];

  late final VmService service;
  final _toClient = StreamController<String>();

  void _onRequest(String message) {
    var request = jsonDecode(message) as Map<String, Object?>;
    var params = (request['params'] as Map?)?.cast<String, Object?>() ?? {};
    if (params['id'] case String wanted) {
      asked.add(wanted);
      if (holds.contains(wanted)) showing = wanted;
    }
    _toClient.add(
      jsonEncode({
        'jsonrpc': '2.0',
        'id': request['id'],
        'result': {'type': 'Response', 'entry': showing},
      }),
    );
  }

  Future<void> close() => _toClient.close();
}

void main() {
  const alpha = CatalogEntry(
    path: 'demo/a.dart',
    symbol: 'alpha',
    annotation: "Demo(name: 'Alpha')",
    name: 'Alpha',
  );
  const beta = CatalogEntry(
    path: 'demo/b.dart',
    symbol: 'beta',
    annotation: "Demo(name: 'Beta')",
    name: 'Beta',
  );
  const gamma = CatalogEntry(
    path: 'demo/c.dart',
    symbol: 'gamma',
    annotation: "Demo(name: 'Gamma')",
    name: 'Gamma',
  );

  /// A session sitting on [alpha], with a guest holding all three.
  (CatalogSession, _FakeGuest) sessionOn(CatalogEntry entry) {
    var guest = _FakeGuest(
      holds: {alpha.id, beta.id, gamma.id},
      showing: entry.id,
    );
    addTearDown(guest.close);
    var session =
        CatalogSession(
            appPackageRoot: '/app',
            flutterSdkRoot: '/sdk',
            projectRoot: '/project',
          )
          ..phase = CatalogSessionPhase.ready
          ..entries = [alpha, beta, gamma]
          ..selected = entry
          ..active = entry
          ..attachInspect(
            InspectClient(
              GuestVmService.forTesting(guest.service, 'isolates/1'),
              patience: InspectPatience.live,
            ),
          );
    addTearDown(session.dispose);
    return (session, guest);
  }

  /// Past the delay, plus a turn for the round trip the timer starts.
  Future<void> settle() async {
    await Future<void>.delayed(
      CatalogSession.peekDelay + const Duration(milliseconds: 60),
    );
  }

  test(
    'resting on a row shows it, and leaving puts back what was there',
    () async {
      var (session, guest) = sessionOn(alpha);

      session.hover(beta);
      await settle();
      expect(guest.showing, beta.id);
      expect(session.peeking, beta, reason: 'and the canvas says so');
      expect(
        session.selected,
        alpha,
        reason: 'a peek is a picture: nothing was asked for',
      );
      expect(session.active, alpha, reason: 'and nothing was committed');

      session.hover(null);
      await settle();
      expect(guest.showing, alpha.id);
      expect(session.peeking, isNull);
    },
  );

  test('sweeping past rows shows none of them', () async {
    var (session, guest) = sessionOn(alpha);

    // The whole reason there is a delay: a pointer crossing the list produces
    // an enter per row, and forty round trips for a gesture that asked for
    // nothing is what the delay exists to refuse.
    session.hover(beta);
    session.hover(gamma);
    session.hover(beta);
    session.hover(null);
    await settle();

    expect(guest.asked, isEmpty);
    expect(guest.showing, alpha.id);
    expect(session.peeking, isNull);
  });

  test('the row already on screen is not a peek', () async {
    var (session, guest) = sessionOn(alpha);

    session.hover(alpha);
    await settle();
    expect(
      session.peeking,
      isNull,
      reason: 'the picture did not change, so nothing should be labelled',
    );
    expect(guest.asked, isEmpty, reason: 'and nothing was sent');
  });

  test('a quarantined entry is never peeked', () async {
    var (session, guest) = sessionOn(alpha);
    session.quarantined = [
      QuarantinedEntry(entry: beta, error: 'does not compile'),
    ];

    session.hover(beta);
    await settle();
    // The guest does not hold it, so the only thing a peek could do is be
    // refused — and the recovery for that is a compile, which no pointer
    // should start.
    expect(guest.asked, isEmpty);
    expect(guest.showing, alpha.id);
  });

  test('the switch turned off ends the peek that is up', () async {
    var (session, guest) = sessionOn(alpha);

    session.hover(beta);
    await settle();
    expect(guest.showing, beta.id);

    session.browsing.previewOnHover = false;
    session.hover(null);
    await settle();
    expect(guest.showing, alpha.id, reason: 'the return is never gated');
    expect(session.peeking, isNull);

    session.hover(gamma);
    await settle();
    expect(guest.showing, alpha.id, reason: 'and no new peek starts');
  });

  // The one thing the calls above cannot show: that a pointer arriving on a
  // row reaches [CatalogSession.hover] at all. Mountable without an engine
  // because the *selected* entry is the broken one, which draws the compiler's
  // page where the texture would be — see `catalog_view_test.dart`.
  testWidgets('the pointer on a row is what starts a peek', (tester) async {
    var guest = _FakeGuest(holds: {alpha.id, gamma.id}, showing: alpha.id);
    addTearDown(guest.close);
    var session =
        CatalogSession(
            appPackageRoot: '/app',
            flutterSdkRoot: '/sdk',
            projectRoot: '/project',
          )
          ..phase = CatalogSessionPhase.ready
          ..entries = [alpha, gamma]
          ..quarantined = [QuarantinedEntry(entry: beta, error: 'boom')]
          ..selected = beta
          ..active = alpha
          ..attachInspect(
            InspectClient(
              GuestVmService.forTesting(guest.service, 'isolates/1'),
              patience: InspectPatience.live,
            ),
          );

    var address = ValueNotifier<Address>(
      Address(worktree: 'test', plugin: 'flutterware.previews'),
    );
    addTearDown(address.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: AddressRoot(
          address: address,
          onChanged: (next) => address.value = next,
          child: Scaffold(body: CatalogView(session: session)),
        ),
      ),
    );

    var pointer = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(
      pointer.hover(tester.getCenter(find.text('Gamma'))),
    );
    await tester.pump(CatalogSession.peekDelay);
    await tester.pumpAndSettle();

    expect(guest.showing, gamma.id);
    expect(session.peeking, gamma);
    // And the canvas says which of the two entries it is showing, because
    // everything else on the panel is still describing the other one.
    // Private to the view, so found by type name, as `catalog_view_test` does.
    var label = find.byWidgetPredicate(
      (w) => w.runtimeType.toString() == '_PeekLabel',
    );
    expect(label, findsOneWidget);
    expect(find.descendant(of: label, matching: find.text('Gamma')), findsOne);

    // The row's tooltip arms a 600ms timer of its own when the pointer lands,
    // and the binding fails a test that leaves any timer pending. Run it out.
    await tester.pump(const Duration(seconds: 1));
    // Unmounted first, so the list reports the pointer leaving it and the
    // session is disposed holding whatever that armed — which is the ordering
    // a worktree closing has, and the one that leaked a timer here.
    await tester.pumpWidget(const SizedBox.shrink());
    session.dispose();
  });

  // The device the canvas frames a peek as, read off the top bar — which is
  // the one place it is observable without an engine to render into.
  testWidgets('a peek is framed as the hovered entry declares', (tester) async {
    var guest = _FakeGuest(holds: {alpha.id, gamma.id}, showing: alpha.id);
    addTearDown(guest.close);
    var session =
        CatalogSession(
            appPackageRoot: '/app',
            flutterSdkRoot: '/sdk',
            projectRoot: '/project',
            // `gamma` is the phone one. `alpha` and `beta` inherit the
            // package's own canvas, which is a desktop window.
            canvases: [
              PreviewCanvas('', devices: [Devices.window]),
              PreviewCanvas('demo/c.dart', devices: [Devices.iphoneSe]),
            ],
          )
          ..phase = CatalogSessionPhase.ready
          ..entries = [alpha, gamma]
          ..quarantined = [QuarantinedEntry(entry: beta, error: 'boom')]
          ..selected = beta
          ..active = alpha
          ..attachInspect(
            InspectClient(
              GuestVmService.forTesting(guest.service, 'isolates/1'),
              patience: InspectPatience.live,
            ),
          );

    var address = ValueNotifier<Address>(
      Address(worktree: 'test', plugin: 'flutterware.previews'),
    );
    addTearDown(address.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: AddressRoot(
          address: address,
          onChanged: (next) => address.value = next,
          child: Scaffold(body: CatalogView(session: session)),
        ),
      ),
    );
    // A desktop canvas stages as the plain rectangle — see
    // `PreviewCanvas.defaultDevice`, which offers a window and never stages
    // one.
    expect(find.text('Fit'), findsOneWidget);

    var pointer = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(
      pointer.hover(tester.getCenter(find.text('Gamma'))),
    );
    await tester.pump(CatalogSession.peekDelay);
    await tester.pumpAndSettle();

    // The whole point: a phone screen shown in a desktop rectangle is not a
    // preview of anything, and neither is a 900-wide panel inside an iPhone.
    expect(find.text(Devices.iphoneSe.label), findsOneWidget);
    expect(find.text('Fit'), findsNothing);

    // And a device the address is carrying is dropped where it means nothing.
    // A window picked while looking at a studio panel is not an answer about
    // the phone demo the pointer just moved to, and `gamma`'s canvas says so
    // by not offering it.
    session.hover(null);
    await tester.pump(CatalogSession.peekReturnDelay);
    await tester.pumpAndSettle();
    address.value = address.value.copyWith(axes: const {'device': 'window'});
    await tester.pumpAndSettle();
    expect(find.text(Devices.window.label), findsOneWidget);

    session.hover(gamma);
    await tester.pump(CatalogSession.peekDelay);
    await tester.pumpAndSettle();
    expect(find.text(Devices.iphoneSe.label), findsOneWidget);
    expect(
      find.text(Devices.window.label),
      findsNothing,
      reason: 'the pick did not hold for this entry',
    );

    await tester.pump(const Duration(seconds: 1));
    await tester.pumpWidget(const SizedBox.shrink());
    session.dispose();
  });

  test('a peek does not survive a click', () async {
    var (session, _) = sessionOn(alpha);

    session.hover(beta);
    await settle();
    expect(session.peeking, beta);

    // `switchTo` needs a daemon to get anywhere, which is exactly right here:
    // what is under test is that asking for something clears the intent, so
    // nothing puts the old entry back underneath the click.
    unawaited(session.switchTo(gamma));
    expect(session.peeking, isNull);
    expect(session.selected, gamma);
  });
}
