import 'package:flutterware_app/src/passthrough/passthrough_command.dart';
import 'package:test/test.dart';

void main() {
  test('runUnderPty returns 127 for nonexistent executable without throwing',
      () async {
    final code = await runUnderPty(
      executable: '/no/such/binary_xyz_for_test',
      arguments: const [],
      printSummary: false,
    );
    expect(code, equals(127));
  });

  test('runUnderPty returns 0 for /usr/bin/true', () async {
    final code = await runUnderPty(
      executable: '/usr/bin/true',
      arguments: const [],
      printSummary: false,
    );
    expect(code, equals(0));
  });
}
