import 'dart:async';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
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
  late List<String?> seen;
  late ConfigWatcher watcher;

  /// A save: write the bytes, then announce it the way a directory watcher
  /// would. Separate steps on purpose — the watcher must decide from the
  /// content, not from the event.
  Future<void> save(String contents, {String? path}) async {
    File(path ?? config.path).writeAsStringSync(contents);
    events.add(WatchEvent(ChangeType.MODIFY, path ?? config.path));
    await Future<void>.delayed(_debounce * 4);
  }

  /// Waits for a fire to land, instead of for a fixed slice of clock.
  ///
  /// The paths through the empty-file confirmation — a delete, a truncate —
  /// cost two debounce windows by design, so a budget written as a small
  /// multiple of a 10ms debounce leaves a few milliseconds of slack and
  /// ordinary scheduler jitter spends it: that 20ms path measured over 70ms on
  /// an *idle* machine, and on CI it failed for a reason that had nothing to do
  /// with the watcher. A test that asserts nothing fired still has to spend the
  /// time; these have an outcome to wait for.
  Future<void> fires(int count) async {
    var deadline = DateTime.now().add(const Duration(seconds: 5));
    while (seen.length < count && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
  }

  setUp(() {
    root = Directory.systemTemp.createTempSync('fw_config_watcher');
    config = File(p.join(root.path, configFilePath))
      ..createSync(recursive: true)
      ..writeAsStringSync('void main() {}');
    events = StreamController<WatchEvent>.broadcast();
    seen = [];
    watcher = ConfigWatcher(
      worktreePath: root.path,
      onChanged: () async =>
          seen.add(config.existsSync() ? config.readAsStringSync() : null),
      debounce: _debounce,
      watch: (_) => events.stream,
    );
  });

  tearDown(() async {
    await watcher.dispose();
    await events.close();
    root.deleteSync(recursive: true);
  });

  test("watches the config file's directory, not the file", () async {
    await watcher.start();
    expect(watcher.watching, p.join(root.path, 'tool'));
    expect(watcher.isWatching, isTrue);
  });

  test('a real edit fires once', () async {
    await watcher.start();
    await save('void main() { print(1); }');
    expect(seen, hasLength(1));
  });

  test('a save that changed no bytes does not fire', () async {
    await watcher.start();
    // What a save-all, or a formatter that had nothing to do, produces.
    await save('void main() {}');
    expect(seen, isEmpty);
  });

  test('a burst of writes inside one window fires once, for the last', () async {
    await watcher.start();

    // Distinct content each time: with no debounce every write is its own fire,
    // and counting a burst of events over *one* content cannot tell them apart.
    for (var i = 0; i < 5; i++) {
      config.writeAsStringSync('void main() { print($i); }');
      events.add(WatchEvent(ChangeType.MODIFY, config.path));
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    await Future<void>.delayed(_debounce * 6);

    expect(seen, [
      'void main() { print(4); }',
    ], reason: 'one fire, for the content it settled on');
  });

  // The one test here on fake time, because it is the only one whose subject
  // *is* the timing. The others assert an outcome and can afford to wait for
  // it; this one asserts what has not happened yet at a moment defined by the
  // clock, and on a loaded CI runner a 3ms delay outlasted the 10ms debounce,
  // firing mid-churn and failing it for a reason that had nothing to do with
  // the watcher. Virtual time makes the gaps exactly the fraction of the
  // debounce the test means them to be.
  test('sustained churn defers the fire until it stops', () {
    fakeAsync((async) {
      unawaited(watcher.start());
      async.flushMicrotasks();
      config.writeAsStringSync('void main() { print(1); }');

      // What `git rebase` looks like: events arriving faster than the debounce,
      // for longer than the debounce. Each one must *reset* the timer. Without
      // the cancel the first timer survives and fires mid-churn — and every
      // later one is then absorbed by the hash gate, so only the timing tells
      // them apart.
      for (var i = 0; i < 10; i++) {
        events.add(WatchEvent(ChangeType.MODIFY, config.path));
        async.elapse(const Duration(milliseconds: 3));
      }
      expect(seen, isEmpty, reason: 'still churning');

      async.elapse(_debounce * 6);
      expect(seen, hasLength(1), reason: 'and once it settles, exactly one');
    });
  });

  test('an event for a sibling file is ignored', () async {
    await watcher.start();

    // The config's bytes move too. Otherwise the hash gate absorbs the event
    // and the test passes with the path filter deleted.
    config.writeAsStringSync('void main() { print(99); }');
    var sibling = p.join(root.path, 'tool', 'other.dart');
    await save('// unrelated', path: sibling);

    expect(seen, isEmpty, reason: 'only the config file may wake it');
  });

  test('the file going away is a change', () async {
    await watcher.start();
    config.deleteSync();
    events.add(WatchEvent(ChangeType.REMOVE, config.path));
    await fires(1);
    expect(seen, [null], reason: 'the fire reports a config that is gone');
  });

  test('broken twice fires once', () async {
    await watcher.start();

    await save('void main() { syntax error');
    expect(seen, hasLength(1));

    // Saving the same broken file again changes nothing, and re-running would
    // reproduce the same error.
    await save('void main() { syntax error');
    expect(seen, hasLength(1));
  });

  test('fixing back to the original content still fires', () async {
    await watcher.start();
    await save('void main() { broken');
    expect(seen, hasLength(1));

    // The manifest currently running came from this content, but the *file* did
    // not have it a moment ago, so the save is real and must be acted on.
    await save('void main() {}');
    expect(seen, hasLength(2));
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
    // The event a real watcher sends for the second write. Without it the test
    // passes whether or not the empty state is confirmed, because nothing ever
    // asks again.
    events.add(WatchEvent(ChangeType.MODIFY, config.path));
    await Future<void>.delayed(_debounce * 6);

    expect(seen, [
      'void main() { print(1); }',
    ], reason: 'the empty state must never reach the loader');
  });

  test('a file that really is emptied still lands', () async {
    await watcher.start();

    config.writeAsStringSync('');
    events.add(WatchEvent(ChangeType.MODIFY, config.path));
    await fires(1);

    expect(seen, [''], reason: 'one settle later, the empty file is believed');
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

  test('disposing during a reload cancels the follow-up', () async {
    var running = Completer<void>();
    var calls = 0;
    var slow = ConfigWatcher(
      worktreePath: root.path,
      onChanged: () async {
        calls++;
        await running.future;
      },
      debounce: _debounce,
      watch: (_) => events.stream,
    );
    await slow.start();

    await save('void main() { print(1); }');
    expect(calls, 1);

    // A second save coalesced behind the one in flight, then the user turns the
    // watch off. The queued follow-up must not land afterwards.
    config.writeAsStringSync('void main() { print(2); }');
    events.add(WatchEvent(ChangeType.MODIFY, config.path));
    await Future<void>.delayed(_debounce * 2);
    await slow.dispose();
    running.complete();
    await Future<void>.delayed(_debounce * 6);

    expect(calls, 1);
  });

  test(
    'a reload that throws leaves the same bytes able to fire again',
    () async {
      var attempts = 0;
      var reported = <Object>[];
      var angry = ConfigWatcher(
        worktreePath: root.path,
        onChanged: () async {
          attempts++;
          throw StateError('reload blew up');
        },
        onError: reported.add,
        debounce: _debounce,
        watch: (_) => events.stream,
      );
      addTearDown(angry.dispose);
      await angry.start();

      // Both saves are the *same* content. Without rewinding the hash the second
      // is indistinguishable from a no-op save and the file stays unreloadable.
      await save('void main() { print(1); }');
      config.setLastModifiedSync(DateTime.now());
      events.add(WatchEvent(ChangeType.MODIFY, config.path));
      await Future<void>.delayed(_debounce * 4);

      expect(attempts, 2);
      // Reported, not swallowed: a timer callback has nobody to rethrow to.
      expect(reported, hasLength(2));
    },
  );

  test('disposing stops it firing', () async {
    await watcher.start();
    await watcher.dispose();
    await save('void main() { print(2); }');
    expect(seen, isEmpty);
  });
}
