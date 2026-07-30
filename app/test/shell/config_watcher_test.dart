import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware_app/src/plugins/manifest_loader.dart';
import 'package:flutterware_app/src/shell/config_watcher.dart';
import 'package:path/path.dart' as p;
import 'package:watcher/watcher.dart';

const _debounce = Duration(milliseconds: 10);

void main() {
  late Directory root;
  late File config;
  late StreamController<WatchEvent> events;
  late int fired;
  late ConfigWatcher watcher;

  /// A save: write the bytes, then announce it the way a directory watcher
  /// would. Separate steps on purpose — the watcher must decide from the
  /// content, not from the event.
  Future<void> save(String contents, {String? path}) async {
    File(path ?? config.path).writeAsStringSync(contents);
    events.add(WatchEvent(ChangeType.MODIFY, path ?? config.path));
    await Future<void>.delayed(_debounce * 4);
  }

  setUp(() {
    root = Directory.systemTemp.createTempSync('fw_config_watcher');
    config = File(p.join(root.path, configFilePath))
      ..createSync(recursive: true)
      ..writeAsStringSync('void main() {}');
    events = StreamController<WatchEvent>.broadcast();
    fired = 0;
    watcher = ConfigWatcher(
      worktreePath: root.path,
      onChanged: () async => fired++,
      debounce: _debounce,
      watch: (_) => events.stream,
    );
  });

  tearDown(() async {
    await watcher.dispose();
    await events.close();
    root.deleteSync(recursive: true);
  });

  test('watches the config file\'s directory, not the file', () async {
    await watcher.start();
    expect(watcher.watching, p.join(root.path, 'tool'));
    expect(watcher.isWatching, isTrue);
  });

  test('a real edit fires once', () async {
    await watcher.start();
    await save('void main() { print(1); }');
    expect(fired, 1);
  });

  test('a save that changed no bytes does not fire', () async {
    await watcher.start();
    // What a save-all, or a formatter that had nothing to do, produces.
    await save('void main() {}');
    expect(fired, 0);
  });

  test('a burst of events for one save fires once', () async {
    await watcher.start();
    config.writeAsStringSync('void main() { print(1); }');
    for (var i = 0; i < 5; i++) {
      events.add(WatchEvent(ChangeType.MODIFY, config.path));
    }
    await Future<void>.delayed(_debounce * 4);
    expect(fired, 1);
  });

  test('an event for a sibling file is ignored', () async {
    await watcher.start();
    var sibling = p.join(root.path, 'tool', 'other.dart');
    await save('// unrelated', path: sibling);
    expect(fired, 0);
  });

  test('the file going away is a change', () async {
    await watcher.start();
    config.deleteSync();
    events.add(WatchEvent(ChangeType.REMOVE, config.path));
    await Future<void>.delayed(_debounce * 4);
    expect(fired, 1);
  });

  test('broken twice fires once', () async {
    await watcher.start();

    await save('void main() { syntax error');
    expect(fired, 1);

    // Saving the same broken file again changes nothing, and re-running would
    // reproduce the same error.
    await save('void main() { syntax error');
    expect(fired, 1);
  });

  test('fixing back to the original content still fires', () async {
    await watcher.start();
    await save('void main() { broken');
    expect(fired, 1);

    // The manifest currently running came from this content, but the *file* did
    // not have it a moment ago, so the save is real and must be acted on.
    await save('void main() {}');
    expect(fired, 2);
  });

  test('nothing is watched when the config directory does not exist', () async {
    var bare = Directory.systemTemp.createTempSync('fw_no_tool');
    addTearDown(() => bare.deleteSync(recursive: true));
    var w = ConfigWatcher(
      worktreePath: bare.path,
      onChanged: () async {},
      debounce: _debounce,
      watch: (_) => events.stream,
    );
    await w.start();

    expect(w.watching, isNull);
    expect(w.isWatching, isFalse);
    await w.dispose();
  });

  test('a truncate-then-write is one fire, not an empty one first', () async {
    await watcher.start();

    // What python's `open(w)`, and `git checkout`, actually do: the file passes
    // through nothing on the way to its new content. Acting on the empty state
    // produces "it printed nothing" — a red banner for a file that is fine.
    config.writeAsStringSync('');
    events.add(WatchEvent(ChangeType.MODIFY, config.path));
    await Future<void>.delayed(_debounce * 2);
    config.writeAsStringSync('void main() { print(1); }');
    await Future<void>.delayed(_debounce * 6);

    expect(fired, 1);
  });

  test('a file that really is emptied still lands', () async {
    await watcher.start();

    config.writeAsStringSync('');
    events.add(WatchEvent(ChangeType.MODIFY, config.path));
    await Future<void>.delayed(_debounce * 8);

    expect(fired, 1, reason: 'one settle later, it is believed');
  });

  test('a save during a reload becomes one follow-up', () async {
    var running = Completer<void>();
    var calls = <String>[];
    var slow = ConfigWatcher(
      worktreePath: root.path,
      onChanged: () async {
        calls.add(config.readAsStringSync());
        await running.future;
      },
      debounce: _debounce,
      watch: (_) => events.stream,
    );
    addTearDown(slow.dispose);
    await slow.start();

    await save('void main() { print(1); }');
    expect(calls, hasLength(1));

    // Two more saves while the first reload is still going.
    config.writeAsStringSync('void main() { print(2); }');
    events.add(WatchEvent(ChangeType.MODIFY, config.path));
    await Future<void>.delayed(_debounce * 2);
    config.writeAsStringSync('void main() { print(3); }');
    events.add(WatchEvent(ChangeType.MODIFY, config.path));
    await Future<void>.delayed(_debounce * 2);
    expect(calls, hasLength(1), reason: 'nothing races the reload in flight');

    running.complete();
    await Future<void>.delayed(_debounce * 6);

    // One follow-up, for the content as it finally is — not one per save.
    expect(calls, hasLength(2));
    expect(calls.last, contains('print(3)'));
  });

  test('disposing stops it firing', () async {
    await watcher.start();
    await watcher.dispose();
    await save('void main() { print(2); }');
    expect(fired, 0);
  });
}
