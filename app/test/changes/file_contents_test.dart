import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware_app/src/changes/changes_probe.dart';
import 'package:flutterware_app/src/changes/file_contents.dart';

/// The store's contract is its keys: an edit is a new key, an unchanged file
/// is a hit, and an oversized file is refused before it is read. All testable
/// with a temp directory and a fake git.
void main() {
  group('fileBodyKind', () {
    test('by extension, case-insensitively', () {
      expect(fileBodyKind('README.md'), FileBodyKind.markdown);
      expect(fileBodyKind('docs/notes.markdown'), FileBodyKind.markdown);
      expect(fileBodyKind('assets/logo.PNG'), FileBodyKind.image);
      expect(fileBodyKind('shot.jpeg'), FileBodyKind.image);
      expect(fileBodyKind('anim.gif'), FileBodyKind.image);
      expect(fileBodyKind('icon.svg'), FileBodyKind.svg);
      expect(fileBodyKind('lib/main.dart'), FileBodyKind.text);
    });

    test('a dot in a directory is not an extension', () {
      // `v1.2/README` has no extension; reading `2/README` as one would give
      // every file under a versioned directory the same wrong kind.
      expect(fileBodyKind('pkg/v1.2/README'), FileBodyKind.text);
      expect(fileBodyKind('pkg/v1.2/README.md'), FileBodyKind.markdown);
      expect(fileBodyKind('Makefile'), FileBodyKind.text);
    });
  });

  group('looksBinary', () {
    test("a NUL in the head is binary — git's own heuristic", () {
      expect(looksBinary(Uint8List.fromList([104, 105, 0, 33])), isTrue);
      expect(looksBinary(utf8.encode('plain text\nwith lines\n')), isFalse);
      expect(looksBinary(Uint8List(0)), isFalse);
    });
  });

  group('onDisk', () {
    late Directory temp;
    late FileContentStore store;

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('file_contents_test');
      store = FileContentStore(temp.path);
    });

    tearDown(() => temp.delete(recursive: true));

    test(
      'reads a file, and a missing one is a state rather than a throw',
      () async {
        await File('${temp.path}/a.txt').writeAsString('hello');

        var loaded = await store.onDisk('a.txt', maxBytes: 1024);
        expect(loaded, isA<FileBytes>());
        expect((loaded as FileBytes).text, 'hello');

        expect(
          await store.onDisk('gone.txt', maxBytes: 1024),
          isA<FileMissing>(),
        );
      },
    );

    test('refuses past the bound, carrying the size it refused', () async {
      await File('${temp.path}/big.bin').writeAsBytes(Uint8List(100));

      var loaded = await store.onDisk('big.bin', maxBytes: 99);
      expect(loaded, isA<FileTooLarge>());
      expect((loaded as FileTooLarge).length, 100);
    });

    test(
      'an overwrite is a new key — the staleness trap this store is for',
      () async {
        // An agent overwriting an untracked file changes neither the patch nor
        // the untracked list, so nothing upstream invalidates anything. The
        // stat is the invalidation.
        var file = File('${temp.path}/note.md');
        await file.writeAsString('first');
        expect(
          ((await store.onDisk('note.md', maxBytes: 1024)) as FileBytes).text,
          'first',
        );

        await file.writeAsString('second!');
        expect(
          ((await store.onDisk('note.md', maxBytes: 1024)) as FileBytes).text,
          'second!',
        );
      },
    );
  });

  group('atRevision', () {
    test(
      'size first, then bytes — an oversized blob is never fetched',
      () async {
        var calls = <List<String>>[];
        var probe = ChangesProbe(
          runGit: (directory, arguments) async {
            calls.add(arguments);
            if (arguments.contains('-s')) {
              return GitOutput(
                exitCode: 0,
                stdout: Uint8List.fromList(utf8.encode('1000000')),
              );
            }
            fail('the blob itself must not be asked for');
          },
        );
        var store = FileContentStore('/wt', probe: probe);

        var loaded = await store.atRevision('abc', 'logo.png', maxBytes: 100);
        expect(loaded, isA<FileTooLarge>());
        expect((loaded as FileTooLarge).length, 1000000);
      },
    );

    test('a path the revision never had is missing, not an error', () async {
      var probe = ChangesProbe(
        runGit: (directory, arguments) async =>
            GitOutput(exitCode: 128, stdout: Uint8List(0), stderr: 'no path'),
      );
      var store = FileContentStore('/wt', probe: probe);

      expect(
        await store.atRevision('abc', 'new.png', maxBytes: 100),
        isA<FileMissing>(),
      );
    });

    test('a revision is immutable, so the second read is a hit', () async {
      var reads = 0;
      var probe = ChangesProbe(
        runGit: (directory, arguments) async {
          if (!arguments.contains('-s')) reads++;
          return GitOutput(
            exitCode: 0,
            stdout: Uint8List.fromList(
              arguments.contains('-s') ? utf8.encode('3') : [1, 2, 3],
            ),
          );
        },
      );
      var store = FileContentStore('/wt', probe: probe);

      await store.atRevision('abc', 'logo.png', maxBytes: 100);
      await store.atRevision('abc', 'logo.png', maxBytes: 100);
      expect(reads, 1);
    });
  });
}
