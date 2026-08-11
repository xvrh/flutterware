import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware_app/src/run/guest_entrypoint.dart';
import 'package:path/path.dart' as p;

/// The generated wrapper that turns a plain launch into a driveable app —
/// and the two ways generation declines, both of which launch uninstrumented
/// rather than failing.
void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('guest_entrypoint_test');
    File(
      p.join(root.path, 'pubspec.yaml'),
    ).writeAsStringSync('name: shop_app\n');
  });

  tearDown(() => root.deleteSync(recursive: true));

  test('wraps a lib/ entrypoint in the run guest', () {
    var result = writeGuestEntrypoint(
      packageRoot: root.path,
      entrypoint: 'lib/main_dev.dart',
    );

    expect(result.guest, isTrue);
    expect(result.target, '.dart_tool/flutterware/run/main_dev_guest.dart');
    var content = File(
      p.joinAll([root.path, ...p.posix.split(result.target)]),
    ).readAsStringSync();
    expect(content, contains("import 'package:shop_app/main_dev.dart'"));
    expect(content, contains("import 'package:flutterware/run_guest.dart'"));
    // The wrapper forwards `args` when the app's main takes them — a
    // `void main(List<String> args)` entrypoint is legal and must not turn
    // the launch into a compile failure.
    expect(content, contains('void main(List<String> args)'));
    expect(content, contains('FutureOr<void> Function(List<String>)'));
    expect(content, contains('runGuest(() => entryMain(args))'));
  });

  test('regenerates in place on a second launch', () {
    writeGuestEntrypoint(packageRoot: root.path, entrypoint: 'lib/main.dart');
    var again = writeGuestEntrypoint(
      packageRoot: root.path,
      entrypoint: 'lib/main.dart',
    );
    expect(again.guest, isTrue);
  });

  test('an entrypoint outside lib/ launches unwrapped, with the reason', () {
    var result = writeGuestEntrypoint(
      packageRoot: root.path,
      entrypoint: 'tool/spike.dart',
    );

    expect(result.guest, isFalse);
    expect(result.target, 'tool/spike.dart');
    expect(result.reason, contains('not under lib/'));
  });

  test('a missing package name launches unwrapped, with the reason', () {
    File(p.join(root.path, 'pubspec.yaml')).deleteSync();

    var result = writeGuestEntrypoint(
      packageRoot: root.path,
      entrypoint: 'lib/main.dart',
    );

    expect(result.guest, isFalse);
    expect(result.target, 'lib/main.dart');
    expect(result.reason, contains('package name'));
  });
}
