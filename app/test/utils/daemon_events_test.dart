import 'package:flutterware_app/src/utils/daemon/events.dart';
import 'package:flutterware_app/src/utils/daemon/protocol.dart';
import 'package:test/test.dart';

/// What `flutter run --machine` actually puts on the wire, decoded.
///
/// [DaemonProtocol.tryReadEvent] swallows a decoding failure on purpose — a
/// throw inside the stdout subscription would silence the daemon for the rest
/// of its life — which makes a field declared too strictly invisible: the
/// event is dropped, a warning goes to the log, and the run simply never
/// learns something. That is worth a test rather than a reading.
void main() {
  group('app.debugPort', () {
    /// **The web payload, verbatim from a Chrome launch.** The daemon builds
    /// `baseUri` with a null-aware map entry, so a runner that leaves it unset
    /// omits the key — and the web runner is one, where the mobile and desktop
    /// path sets it.
    ///
    /// Declared non-null this threw, the event was dropped, and the handle
    /// never learned its VM service: no inspect, no act, no reload, for the
    /// life of the run. Reported by a consumer whose log plainly contained the
    /// port that the cockpit went on reporting as "not started yet".
    test('decodes without a baseUri, which is how web sends it', () {
      var event = DaemonProtocol.tryReadEvent({
        'event': 'app.debugPort',
        'params': {
          'appId': 'a1b2',
          'port': 57000,
          'wsUri': 'ws://127.0.0.1:57000/fguzYUsKTwk=/ws',
        },
      });

      expect(event, isA<AppDebugPortEvent>());
      var port = event! as AppDebugPortEvent;
      expect(port.appId, 'a1b2');
      expect(port.port, 57000);
      expect(port.wsUri, Uri.parse('ws://127.0.0.1:57000/fguzYUsKTwk=/ws'));
      expect(port.baseUri, isNull);
    });

    test('still reads the baseUri when one is sent', () {
      var event =
          DaemonProtocol.tryReadEvent({
                'event': 'app.debugPort',
                'params': {
                  'appId': 'a1b2',
                  'port': 57000,
                  'wsUri': 'ws://127.0.0.1:57000/x=/ws',
                  'baseUri': 'http://127.0.0.1:57000/x=/',
                },
              })!
              as AppDebugPortEvent;

      expect(event.baseUri, Uri.parse('http://127.0.0.1:57000/x=/'));
    });

    /// The guard the swallow is there for, held to the *dropped* half of the
    /// contract: a malformed event costs one event, never the subscription.
    test('a malformed payload is dropped rather than thrown', () {
      expect(
        DaemonProtocol.tryReadEvent({
          'event': 'app.debugPort',
          'params': {'appId': 'a1b2'},
        }),
        isNull,
      );
    });
  });
}
