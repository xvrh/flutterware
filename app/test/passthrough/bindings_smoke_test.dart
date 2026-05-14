import 'dart:ffi';
import 'package:flutterware_app/src/passthrough/pty/bindings/libc_bindings.dart';
import 'package:test/test.dart';

void main() {
  test('libc bindings load and getpid returns positive', () {
    final libc = LibcBindings();
    final pid = libc.getpid();
    expect(pid, greaterThan(0));
  });

  test('winsize struct is 8 bytes', () {
    expect(sizeOf<WinSize>(), equals(8));
  });
}
