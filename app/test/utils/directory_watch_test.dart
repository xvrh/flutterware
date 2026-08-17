import 'dart:async';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware_app/src/utils/directory_watch.dart';
import 'package:path/path.dart' as p;

/// The timing rules and the filter, with a fake stream in place of the
/// filesystem — `worktrees/watchers_test.dart` covers the same rules as the
/// changes screen sees them, and this covers them as everything else does.
void main() {
  const debounce = Duration(milliseconds: 50);
  const floor = Duration(seconds: 2);

  late Directory root;
  late String directory;
  late Map<String, StreamController<String>> controllers;
  late List<({String path, bool recursive})> watched;
  late List<Object> failures;

  setUp(() {
    root = Directory.systemTemp.createTempSync('fw_directory_watch_test');
    directory = p.join(root.path, 'test');
    Directory(directory).createSync();
    controllers = {};
    watched = [];
    failures = [];
  });

  tearDown(() => root.deleteSync(recursive: true));

  Stream<String> watch(String path, {required bool recursive}) {
    watched.add((path: path, recursive: recursive));
    return (controllers[path] = StreamController<String>.broadcast()).stream;
  }

  DirectoryWatch build({
    String? path,
    WatchFilter? accept,
    DateTime Function()? now,
  }) => DirectoryWatch(
    directory: path ?? directory,
    accept: accept,
    debounce: debounce,
    minInterval: floor,
    watch: watch,
    now: now,
    onFailure: failures.add,
  );

  void change(String relative) =>
      controllers[directory]!.add(p.join(directory, relative));

  void withClock(
    void Function(DirectoryWatch, FakeAsync) body, {
    WatchFilter? accept,
  }) {
    fakeAsync((async) {
      var start = DateTime(2026, 8, 17, 9);
      var watcher = build(accept: accept, now: () => start.add(async.elapsed))
        ..start();
      body(watcher, async);
      unawaited(watcher.dispose());
      async.flushTimers();
    });
  }

  test('one recursive watch, on the directory itself', () {
    build().start();
    expect(watched, [(path: directory, recursive: true)]);
  });

  test('a burst of saves is one signal', () {
    withClock((watcher, async) {
      var fired = 0;
      watcher.changes.listen((_) => fired++);

      for (var i = 0; i < 40; i++) {
        change('scenarios/a$i.dart');
      }
      async.elapse(debounce * 2);
      expect(fired, 1, reason: 'a save is several writes, and it is one edit');
    });
  });

  test('an agent writing without pause still fires on the floor', () {
    withClock((watcher, async) {
      var fired = 0;
      watcher.changes.listen((_) => fired++);

      for (var tick = 0; tick < 60; tick++) {
        change('scenarios/busy.dart');
        async.elapse(const Duration(milliseconds: 100));
      }

      expect(fired, 3, reason: '6 s of continuous writing, a 2 s floor');
    });
  });

  test('the filter is what makes the watch affordable', () {
    // The scenario list's own filter: a suite may keep goldens and fixtures
    // beside its tests, and a rescan is worth exactly one thing — a
    // `scenario('…')` call appearing, moving or going.
    withClock(accept: (path) => path.endsWith('.dart'), (watcher, async) {
      var fired = 0;
      watcher.changes.listen((_) => fired++);

      change('goldens/checkout.png');
      change('fixtures/orders.json');
      async.elapse(debounce * 2);
      expect(fired, 0);

      change('scenarios/checkout_test.dart');
      async.elapse(debounce * 2);
      expect(fired, 1);
    });
  });

  test('no filter accepts everything', () {
    withClock((watcher, async) {
      var fired = 0;
      watcher.changes.listen((_) => fired++);
      change('goldens/checkout.png');
      async.elapse(debounce * 2);
      expect(fired, 1);
    });
  });

  test('a directory that is not there costs liveness and nothing else', () {
    var watcher = build(path: p.join(root.path, 'absent'))..start();
    addTearDown(watcher.dispose);

    expect(watched, isEmpty);
    expect(failures, isEmpty, reason: 'gone is not an error, it is just gone');
    expect(
      watcher.isWatching,
      isFalse,
      reason: 'and the caller can say so rather than pretending to be live',
    );
  });

  test('a watch the system refuses is reported, never thrown', () {
    var watcher = DirectoryWatch(
      directory: directory,
      watch: (path, {required recursive}) =>
          throw const FileSystemException('too many open files'),
      onFailure: failures.add,
    )..start();
    addTearDown(watcher.dispose);

    expect(failures, hasLength(1));
    expect(watcher.isWatching, isFalse);
  });

  test('starting twice does not double the watch', () {
    build()
      ..start()
      ..start();
    expect(watched, hasLength(1));
  });
}
