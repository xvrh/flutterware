import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware/src/inspect/error.dart';
import 'package:flutterware/src/inspect/guest_errors.dart';

/// The `network` mark: a failed fetch is recorded as the typed fact it is, so
/// the audit — whose `flutter_test` lane answers every HTTP request with 400
/// — can keep the environment's failures from counting an entry broken.
void main() {
  setUp(GuestErrors.instance.clear);

  test('a network image failure is marked, and survives the wire', () {
    GuestErrors.instance.report(
      FlutterErrorDetails(
        exception: NetworkImageLoadException(
          statusCode: 400,
          uri: Uri.parse('https://example.com/a.png'),
        ),
        library: 'image resource service',
        context: ErrorDescription('resolving an image codec'),
      ),
    );

    var error = GuestErrors.instance.describe().errors.single;
    expect(error.network, isTrue);
    expect(InspectError.fromJson(error.toJson()).network, isTrue);
  });

  test('an ordinary error is not, and says nothing about it', () {
    GuestErrors.instance.report(
      FlutterErrorDetails(
        exception: FlutterError('A RenderFlex overflowed by 7.8 pixels.'),
        library: 'rendering library',
      ),
    );

    var error = GuestErrors.instance.describe().errors.single;
    expect(error.network, isFalse);
    // Absent, not false: the healthy case stays the size it was.
    expect(error.toJson(), isNot(contains('network')));
  });

  test('the mark outlives deduplication', () {
    for (var i = 0; i < 2; i++) {
      GuestErrors.instance.report(
        FlutterErrorDetails(
          exception: NetworkImageLoadException(
            statusCode: 400,
            uri: Uri.parse('https://example.com/a.png'),
          ),
          library: 'image resource service',
        ),
      );
    }

    var error = GuestErrors.instance.describe().errors.single;
    expect(error.count, 2);
    expect(error.network, isTrue);
  });
}
