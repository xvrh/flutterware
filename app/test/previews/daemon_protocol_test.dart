import 'package:flutterware_app/src/previews/protocol.dart';
import 'package:test/test.dart';

/// What the daemon has to survive reading, and what a client has to survive
/// being told.
///
/// The daemon is a **shared** process: one panel, one `fw` command and one agent
/// lean on the same compiler. So a line it cannot read is not a local problem —
/// decoding used to throw out of a `listen` callback, which is an unhandled
/// async error, which kills the isolate and every other client's warm state with
/// it. These tests pin the two halves of that: decoding an unknown message is
/// *fallible* (so the daemon's `catch` is the right catch), and the fallible path
/// is *reachable* from an ordinary JSON line (so it is not theoretical).
///
/// The survival of the process itself needs a real one; that check lives in
/// `integration_test/compiler_daemon_test.dart`, which pokes a running daemon
/// from a raw socket.
void main() {
  group('reading a request', () {
    test('an unknown type is a FormatException, not a crash-shaped null', () {
      // A newer client, or a stray line. It must be an exception the daemon can
      // name — a decoder that returned null here would push the failure into
      // whatever used the result.
      expect(
        () => DaemonRequest.decode({'type': 'a-request-from-the-future'}),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('a-request-from-the-future'),
          ),
        ),
      );
    });

    test('a line with no type at all fails the same way', () {
      expect(
        () => DaemonRequest.decode({'no': 'type'}),
        throwsA(isA<FormatException>()),
      );
    });

    test('tryDecodeLine hands any JSON object straight to the decoder', () {
      // This is why the above is reachable rather than theoretical: the only
      // thing filtered out before decoding is a line that is not a JSON object.
      expect(tryDecodeLine('{"type":"nonsense"}'), {'type': 'nonsense'});
      expect(tryDecodeLine('not json'), isNull);
      expect(tryDecodeLine('[1,2,3]'), isNull);
      expect(tryDecodeLine('   '), isNull);
    });

    test('every declared request round-trips', () {
      for (var request in <DaemonRequest>[
        const SelectRequest(7, 'demo/a.dart#a', full: true, ifChanged: true),
        const RefreshRequest(),
        const StopDaemonRequest(),
      ]) {
        var line = encodeLine(request);
        var decoded = DaemonRequest.decode(tryDecodeLine(line)!);
        expect(decoded.runtimeType, request.runtimeType, reason: line);
        if (decoded is SelectRequest && request is SelectRequest) {
          expect(decoded.requestId, request.requestId);
          expect(decoded.id, request.id);
          expect(decoded.full, isTrue);
          expect(decoded.ifChanged, isTrue);
        }
      }
    });
  });

  group('reading a response', () {
    test('an unknown type is a FormatException', () {
      expect(
        () => DaemonResponse.decode({'type': 'invented'}),
        throwsA(isA<FormatException>()),
      );
    });

    test('a request id survives the wire', () {
      // The client matches a reply on this id and nothing else, because the
      // daemon answers other clients' selects onto streams of the same shape.
      var line = encodeLine(
        const DaemonCompiled(
          requestId: 42,
          id: 'demo/a.dart#a',
          compile: Duration(milliseconds: 1500),
          newSourceCount: 3,
        ),
      );
      var decoded =
          DaemonResponse.decode(tryDecodeLine(line)!) as DaemonCompiled;
      expect(decoded.requestId, 42);
      expect(decoded.compile, const Duration(milliseconds: 1500));
      expect(decoded.ok, isFalse, reason: 'no dill, so nothing to load');
    });
  });
}
