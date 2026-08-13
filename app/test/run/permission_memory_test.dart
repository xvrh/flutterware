import 'dart:io';

import 'package:flutterware_app/src/run/permission_memory.dart';
import 'package:flutterware_app/src/run/permission_write.dart';
import 'package:test/test.dart';

void main() {
  late String dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('fw-wish-').path);

  test('a wish survives being written and read back', () {
    var memory = PermissionMemory(dir);
    var key = PermissionMemory.keyFor('/w/tree', 'examples/example');

    memory.write(key, const PermissionWish(profile: 'first-run'));

    expect(PermissionMemory(dir).read(key).profile, 'first-run');
    expect(
      PermissionMemory(dir).read(key).resolved,
      PermissionProfile.firstRun,
    );
  });

  test('is keyed by worktree and package, not by device or entry point', () {
    // A profile set for the app is one you meant for the app — `main.dart` and
    // `main_dev.dart` are two builds of one thing, and the emulator and the
    // simulator are two places to put it.
    var memory = PermissionMemory(dir);
    memory.write(
      PermissionMemory.keyFor('/w/a', 'examples/example'),
      const PermissionWish(profile: 'granted'),
    );

    expect(
      memory.read(PermissionMemory.keyFor('/w/b', 'examples/example')).isEmpty,
      isTrue,
    );
    expect(memory.read(PermissionMemory.keyFor('/w/a', 'app')).isEmpty, isTrue);
  });

  test('clearing removes it rather than storing an empty one', () {
    var memory = PermissionMemory(dir);
    var key = PermissionMemory.keyFor('/w/tree', 'app');
    memory.write(key, const PermissionWish(profile: 'granted'));

    memory.clear(key);

    expect(memory.read(key).isEmpty, isTrue);
    expect(File('$dir/permissions.json').readAsStringSync(), '{}');
  });

  test('overrides ride on top of a profile', () {
    var memory = PermissionMemory(dir);
    var key = PermissionMemory.keyFor('/w/tree', 'app');

    memory.write(
      key,
      const PermissionWish(profile: 'granted', overrides: {'camera': 'denied'}),
    );

    var read = memory.read(key);
    expect(read.profile, 'granted');
    expect(read.overrides, {'camera': 'denied'});
  });

  test('a torn file is an empty memory, not a crash', () {
    // Best effort, like FlagMemory: a memory that cannot be read must never
    // stop a launch.
    File('$dir/permissions.json').writeAsStringSync('{not json at all');

    expect(
      PermissionMemory(dir).read(PermissionMemory.keyFor('/w', 'app')).isEmpty,
      isTrue,
    );
  });

  test('an unknown profile id resolves to null rather than guessing', () {
    var memory = PermissionMemory(dir);
    var key = PermissionMemory.keyFor('/w', 'app');
    memory.write(key, const PermissionWish(profile: 'sensible-sounding'));

    expect(memory.read(key).resolved, isNull);
  });
}
