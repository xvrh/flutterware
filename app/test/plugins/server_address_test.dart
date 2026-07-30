import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware_app/src/plugins/native/server_address.dart';

/// The round trip is the contract — see the file's own header.
void main() {
  test('segments and place are inverses', () {
    expect(serverPlace(serverSegments('api')), const ServerPlace('api'));
    expect(
      serverPlace(serverSegments('api', requestId: 42)),
      const ServerPlace('api', requestId: 42),
    );
  });

  test('sql segments and place are inverses', () {
    expect(serverPlace(sqlSegments('api')), const ServerPlace.sql('api'));
    expect(
      serverPlace(sqlSegments('api', queryKey: 'ab12cd34')),
      const ServerPlace.sql('api', queryKey: 'ab12cd34'),
    );
  });

  test('every place round-trips through serverSegmentsOf', () {
    for (var place in [
      const ServerPlace('api'),
      const ServerPlace('api', requestId: 7),
      const ServerPlace.sql('api'),
      const ServerPlace.sql('api', queryKey: 'ab12cd34'),
    ]) {
      expect(serverPlace(serverSegmentsOf(place)), place);
    }
  });

  test('a malformed tail reads back as the server alone', () {
    expect(serverPlace(['api', 'req']), const ServerPlace('api'));
    expect(serverPlace(['api', 'req', 'oops']), const ServerPlace('api'));
    expect(serverPlace(['api', 'other', '3']), const ServerPlace('api'));
  });

  test('no segments is no place', () {
    expect(serverPlace([]), isNull);
  });
}
