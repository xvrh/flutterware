import 'dart:io';

import 'package:flutterware/src/working_copy.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// What the working copy is a function of.
///
/// Both cases here are the same bug seen from its two ends, and the bug is not
/// hypothetical: a consumer whose project moved to a newer Flutter kept a copy
/// resolved against this repository's pinned one, and the way it surfaced was
/// a package in the middle of the graph failing to *parse* — a minute into a
/// GUI build, naming a package the project never asked for. Neither half fixes
/// it alone. Drop the lock and an existing copy still never re-resolves; stamp
/// the SDK and the fresh copy still inherits the versions in the lock.
void main() {
  late Directory temp;
  late String source;
  late String destination;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('working_copy');
    source = p.join(temp.path, 'source');
    destination = p.join(temp.path, 'destination');
    _write(p.join(source, 'pubspec.yaml'), 'name: flutterware\n');
    _write(p.join(source, 'lib', 'flutterware.dart'), '// library\n');
    _write(p.join(source, 'app', 'pubspec.yaml'), 'name: flutterware_app\n');
  });

  tearDown(() => temp.deleteSync(recursive: true));

  group('the lock does not cross the boundary', () {
    test('is left behind rather than copied', () {
      _write(p.join(source, 'pubspec.lock'), 'packages:\n  jni: 1.0.0\n');

      copyPackageInto(source, destination, 'stamp');

      expect(File(p.join(destination, 'pubspec.yaml')).existsSync(), isTrue);
      expect(
        File(p.join(destination, 'lib', 'flutterware.dart')).existsSync(),
        isTrue,
      );
      expect(File(p.join(destination, 'pubspec.lock')).existsSync(), isFalse);
    });

    test('one an older flutterware left in the copy is removed', () {
      // The heal for a machine that already has a copy: not copying it is no
      // use while `pub get` can still find the one already sitting there.
      _write(p.join(destination, 'pubspec.lock'), 'packages:\n  jni: 1.0.0\n');

      copyPackageInto(source, destination, 'stamp');

      expect(File(p.join(destination, 'pubspec.lock')).existsSync(), isFalse);
    });

    test('a changed lock does not invalidate the copy', () {
      // The stamp and the copy walk one list, so a file the copy skips must not
      // be able to say the copy is stale.
      _write(p.join(source, 'pubspec.lock'), 'packages:\n  jni: 1.0.0\n');
      var before = workingCopyStamp(source, sdk: 'dart 3.13');

      _write(p.join(source, 'pubspec.lock'), 'packages:\n  jni: 1.0.3\n');

      expect(workingCopyStamp(source, sdk: 'dart 3.13'), before);
    });
  });

  group('the SDK is an input', () {
    test('the same sources under a different SDK are a different copy', () {
      expect(
        workingCopyStamp(source, sdk: 'dart 3.14'),
        isNot(workingCopyStamp(source, sdk: 'dart 3.13')),
      );
    });

    test('the same sources under the same SDK are the same copy', () {
      expect(
        workingCopyStamp(source, sdk: 'dart 3.13'),
        workingCopyStamp(source, sdk: 'dart 3.13'),
      );
    });

    test('changed sources under one SDK are a different copy', () {
      var before = workingCopyStamp(source, sdk: 'dart 3.13');

      _write(p.join(source, 'lib', 'flutterware.dart'), '// library, longer\n');

      expect(workingCopyStamp(source, sdk: 'dart 3.13'), isNot(before));
    });
  });

  test('the stamp records what the copy was made from', () {
    var stamp = workingCopyStamp(source, sdk: 'dart 3.13');

    copyPackageInto(source, destination, stamp);

    expect(workingCopyStampFile(destination).readAsStringSync(), stamp);
  });
}

void _write(String path, String contents) => File(path)
  ..createSync(recursive: true)
  ..writeAsStringSync(contents);
