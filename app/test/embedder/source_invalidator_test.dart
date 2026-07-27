import 'dart:io';

import 'package:flutterware_app/src/embedder/source_invalidator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory root;
  late SourceInvalidator invalidator;

  Uri write(String relative, String contents) {
    var file = File(p.join(root.path, relative))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(contents);
    return file.uri;
  }

  /// The filesystem's mtime resolution is coarse enough that two writes in the
  /// same millisecond are indistinguishable. Every test here is about a change
  /// being *seen*, so say when it happened rather than racing the clock.
  void touch(Uri uri, DateTime when) =>
      File.fromUri(uri).setLastModifiedSync(when);

  setUp(() {
    root = Directory.systemTemp.createTempSync('fw_invalidator_test');
    invalidator = SourceInvalidator();
  });

  tearDown(() => root.deleteSync(recursive: true));

  test('the first sweep is a baseline, not a change', () {
    var demo = write('demo/tile.dart', 'a');
    expect(invalidator.sweep([demo]), isEmpty);
    expect(invalidator.watched, 1);
  });

  test('reports a file edited since the baseline, once', () {
    var demo = write('demo/tile.dart', 'a');
    invalidator.sweep([demo]);

    touch(demo, DateTime(2026, 7, 27, 12));
    expect(invalidator.sweep([demo]), [demo]);
    // The edit is now the baseline; a second sweep has nothing to say.
    expect(invalidator.sweep([demo]), isEmpty);
  });

  test('an mtime that moves backwards is still a change', () {
    // What a branch switch or a `git stash` does to a file. A `lastCompiled`
    // comparison reads this as untouched and serves the stale library.
    var demo = write('demo/tile.dart', 'a');
    touch(demo, DateTime(2026, 7, 27, 12));
    invalidator.sweep([demo]);

    touch(demo, DateTime(2026, 7, 20, 9));
    expect(invalidator.sweep([demo]), [demo]);
  });

  test('a deleted source is invalidated, and only once', () {
    var demo = write('demo/tile.dart', 'a');
    invalidator.sweep([demo]);

    File.fromUri(demo).deleteSync();
    expect(invalidator.sweep([demo]), [demo]);
    expect(invalidator.sweep([demo]), isEmpty);
  });

  test('skips ignored roots without statting them', () {
    var sdk = Directory(p.join(root.path, 'sdk'))..createSync();
    invalidator = SourceInvalidator(ignoredRoots: [sdk.path]);
    var framework = write('sdk/widgets.dart', 'a');
    var demo = write('demo/tile.dart', 'a');
    invalidator.sweep([framework, demo]);
    expect(invalidator.watched, 1);

    touch(framework, DateTime(2026, 7, 27, 12));
    touch(demo, DateTime(2026, 7, 27, 12));
    expect(invalidator.sweep([framework, demo]), [demo]);
  });

  test('ignores sources that are not files on disk', () {
    expect(
      invalidator.sweep([Uri.parse('package:flutter/widgets.dart')]),
      isEmpty,
    );
    expect(invalidator.watched, 0);
  });

  test('a file first seen after the baseline does not report as edited', () {
    // A source the entry pulled in on its first visit: new to the invalidator,
    // but the compile that reported it has already built it.
    var demo = write('demo/tile.dart', 'a');
    invalidator.sweep([demo]);

    var helper = write('demo/shell.dart', 'b');
    expect(invalidator.sweep([demo, helper]), isEmpty);

    touch(helper, DateTime(2026, 7, 27, 12));
    expect(invalidator.sweep([demo, helper]), [helper]);
  });
}
