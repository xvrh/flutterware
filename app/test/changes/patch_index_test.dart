import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware_app/src/changes/patch_index.dart';

/// This is the file where a wrong byte offset silently renders the wrong
/// code, which is the worst failure the changes screen can have. So the cases
/// here are the ones a happy-path patch never produces, written out explicitly
/// rather than recorded, because each one is a specific claim about the format.
///
/// The round-trip against real git — every file's slice equalling
/// `git diff -- <path>` — lives in `changes_git_test.dart`, where there is a
/// repository to check it against.
void main() {
  PatchIndex index(String patch) =>
      indexPatch(Uint8List.fromList(utf8.encode(patch)));

  group('files and statuses', () {
    test('reads an ordinary modification, with counts from the content', () {
      var patch = index('''
diff --git a/lib/a.dart b/lib/a.dart
index 111..222 100644
--- a/lib/a.dart
+++ b/lib/a.dart
@@ -1,3 +1,4 @@
 one
-two
+TWO
+three
 four
''');

      expect(patch.files, hasLength(1));
      var file = patch.files.single;
      expect(file.path, 'lib/a.dart');
      expect(file.status, ChangeStatus.modified);
      expect(file.added, 2);
      expect(file.removed, 1);
      expect(file.hunks, hasLength(1));
      expect(file.hunks.single.oldStart, 1);
      expect(file.hunks.single.newStart, 1);
    });

    test('an added file is added, not modified', () {
      var patch = index('''
diff --git a/new.txt b/new.txt
new file mode 100644
index 000..111
--- /dev/null
+++ b/new.txt
@@ -0,0 +1 @@
+brand new
''');
      expect(patch.files.single.status, ChangeStatus.added);
      expect(patch.files.single.path, 'new.txt');
      expect(patch.files.single.added, 1);
      expect(patch.files.single.removed, 0);
    });

    test('a deleted file keeps the path it had', () {
      var patch = index('''
diff --git a/gone.txt b/gone.txt
deleted file mode 100644
index 111..000
--- a/gone.txt
+++ /dev/null
@@ -1 +0,0 @@
-gone
''');
      expect(patch.files.single.status, ChangeStatus.deleted);
      expect(patch.files.single.path, 'gone.txt');
      expect(patch.files.single.removed, 1);
    });

    test('a rename reports both ends', () {
      var patch = index('''
diff --git a/old.txt b/new.txt
similarity index 80%
rename from old.txt
rename to new.txt
index 111..222 100644
--- a/old.txt
+++ b/new.txt
@@ -1,3 +1,3 @@
 old name
-content
+CONTENT
 here
''');
      var file = patch.files.single;
      expect(file.status, ChangeStatus.renamed);
      expect(file.path, 'new.txt');
      expect(file.oldPath, 'old.txt');
    });

    test('a rename with no content change has no ---/+++ to read', () {
      // git omits them entirely when only the path moved, so `rename from`/
      // `rename to` are the *only* source of the names.
      var patch = index('''
diff --git a/old.txt b/moved/new.txt
similarity index 100%
rename from old.txt
rename to moved/new.txt
''');
      expect(patch.files.single.path, 'moved/new.txt');
      expect(patch.files.single.oldPath, 'old.txt');
      expect(patch.files.single.hunks, isEmpty);
    });

    test('a binary file is a file with no lines', () {
      var patch = index('''
diff --git a/blob.bin b/blob.bin
index 111..222 100644
Binary files a/blob.bin and b/blob.bin differ
''');
      var file = patch.files.single;
      expect(file.isBinary, isTrue);
      expect(file.path, 'blob.bin');
      expect(file.added, 0);
      expect(file.removed, 0);
      expect(file.hunks, isEmpty);
    });
  });

  group('hunk headers', () {
    test('an omitted count means one, not zero', () {
      // `@@ -1 +1 @@` reading as zero would end the hunk before its content and
      // hand the rest of the file to the header parser.
      var patch = index('''
diff --git a/a.txt b/a.txt
--- a/a.txt
+++ b/a.txt
@@ -1 +1 @@
-before
+after
diff --git a/b.txt b/b.txt
--- a/b.txt
+++ b/b.txt
@@ -1 +1 @@
-x
+y
''');
      expect(patch.files, hasLength(2));
      expect(patch.files[0].added, 1);
      expect(patch.files[0].removed, 1);
      expect(patch.files[1].path, 'b.txt');
    });

    test('carries the context git guessed', () {
      var patch = index('''
diff --git a/a.dart b/a.dart
--- a/a.dart
+++ b/a.dart
@@ -12,3 +12,3 @@ class StreamParser {
 a
-b
+B
''');
      expect(patch.files.single.hunks.single.context, 'class StreamParser {');
    });

    test('several hunks each keep their own position and weight', () {
      var patch = index('''
diff --git a/a.dart b/a.dart
--- a/a.dart
+++ b/a.dart
@@ -1,2 +1,3 @@
 one
+two
 three
@@ -40,2 +41,2 @@
-forty
+FORTY
 rest
''');
      var hunks = patch.files.single.hunks;
      expect(hunks, hasLength(2));
      expect(hunks[0].newStart, 1);
      expect(hunks[0].added, 1);
      expect(hunks[0].removed, 0);
      expect(hunks[1].newStart, 41);
      expect(hunks[1].added, 1);
      expect(hunks[1].removed, 1);
    });

    test('display height is known before anything is decoded', () {
      var patch = index('''
diff --git a/a.dart b/a.dart
--- a/a.dart
+++ b/a.dart
@@ -1,3 +1,4 @@
 one
-two
+TWO
+three
 four
''');
      // Four new lines drawn, plus the one removed line beside them.
      expect(patch.files.single.hunks.single.displayLines, 5);
    });
  });

  group('content that looks like a header', () {
    test('a removed line reading "--- x" is content, not the next file', () {
      var patch = index('''
diff --git a/doc.md b/doc.md
--- a/doc.md
+++ b/doc.md
@@ -1,3 +1,3 @@
 title
---- old rule
+diff --git a/fake b/fake
 end
''');
      expect(patch.files, hasLength(1), reason: 'one real file');
      expect(patch.files.single.path, 'doc.md');
      expect(patch.files.single.added, 1);
      expect(patch.files.single.removed, 1);
    });

    test('a no-newline marker counts as nothing', () {
      var patch = index(r'''
diff --git a/a.txt b/a.txt
--- a/a.txt
+++ b/a.txt
@@ -1 +1 @@
-before
\ No newline at end of file
+after
\ No newline at end of file
''');
      expect(patch.files.single.added, 1);
      expect(patch.files.single.removed, 1);
    });

    test('an empty context line does not end the hunk', () {
      var patch = index(
        'diff --git a/a.txt b/a.txt\n'
        '--- a/a.txt\n'
        '+++ b/a.txt\n'
        '@@ -1,3 +1,3 @@\n'
        ' one\n'
        '\n' // a context line whose single space was stripped
        '-two\n'
        '+TWO\n',
      );
      expect(patch.files.single.added, 1);
      expect(patch.files.single.removed, 1);
    });

    test('CRLF content does not confuse the line classifier', () {
      var patch = index(
        'diff --git a/a.txt b/a.txt\r\n'
        '--- a/a.txt\r\n'
        '+++ b/a.txt\r\n'
        '@@ -1,2 +1,3 @@\r\n'
        ' crlf\r\n'
        '-lines\r\n'
        '+LINES\r\n'
        '+more\r\n',
      );
      expect(patch.files.single.path, 'a.txt');
      expect(patch.files.single.added, 2);
      expect(patch.files.single.removed, 1);
    });
  });

  group('paths', () {
    test('a path with a space comes from ---/+++, not from diff --git', () {
      // `diff --git a/with space.txt b/with space.txt` has three plausible
      // split points and git does not quote it. The trailing tab on the
      // ---/+++ lines is the disambiguator, and it is not part of the name.
      var patch = index(
        'diff --git a/with space.txt b/with space.txt\n'
        '--- a/with space.txt\t\n'
        '+++ b/with space.txt\t\n'
        '@@ -1 +1 @@\n'
        '-a\n'
        '+b\n',
      );
      expect(patch.files.single.path, 'with space.txt');
    });

    test('unquotes an octal-escaped path as one character, not two', () {
      var patch = index(
        'diff --git "a/caf\\303\\251.txt" "b/caf\\303\\251.txt"\n'
        '--- "a/caf\\303\\251.txt"\n'
        '+++ "b/caf\\303\\251.txt"\n'
        '@@ -1 +1 @@\n'
        '-x\n'
        '+y\n',
      );
      expect(patch.files.single.path, 'café.txt');
    });

    test('a directory really called "a" survives prefix stripping', () {
      var patch = index('''
diff --git a/a/thing.dart b/a/thing.dart
--- a/a/thing.dart
+++ b/a/thing.dart
@@ -1 +1 @@
-x
+y
''');
      expect(patch.files.single.path, 'a/thing.dart');
    });

    test('a binary rename names both ends from the rename lines alone', () {
      var patch = index('''
diff --git a/old.png b/new.png
similarity index 100%
rename from old.png
rename to new.png
''');
      expect(patch.files.single.path, 'new.png');
      expect(patch.files.single.oldPath, 'old.png');
    });
  });

  group('slices', () {
    test('each file owns a contiguous range that starts at its own header', () {
      var patch = index('''
diff --git a/a.txt b/a.txt
--- a/a.txt
+++ b/a.txt
@@ -1 +1 @@
-one
+ONE
diff --git a/b.txt b/b.txt
--- a/b.txt
+++ b/b.txt
@@ -1 +1 @@
-two
+TWO
''');
      var first = patch.textFor(patch.files[0]);
      var second = patch.textFor(patch.files[1]);

      expect(first, startsWith('diff --git a/a.txt'));
      expect(first, contains('+ONE'));
      expect(first, isNot(contains('b.txt')));

      expect(second, startsWith('diff --git a/b.txt'));
      expect(second, contains('+TWO'));

      // No gap: the ranges tile the buffer.
      expect(patch.files[0].byteEnd, patch.files[1].byteStart);
    });

    test('a hunk slices to itself', () {
      var patch = index('''
diff --git a/a.txt b/a.txt
--- a/a.txt
+++ b/a.txt
@@ -1,2 +1,2 @@
 keep
-one
+ONE
@@ -9,2 +9,2 @@
 keep
-two
+TWO
''');
      var second = patch.textForHunk(patch.files.single.hunks[1]);
      expect(second, startsWith('@@ -9,2 +9,2 @@'));
      expect(second, contains('+TWO'));
      expect(second, isNot(contains('ONE')));
    });

    test('malformed bytes are replaced rather than thrown on', () {
      var bytes = <int>[
        ...utf8.encode(
          'diff --git a/a.txt b/a.txt\n'
          '--- a/a.txt\n'
          '+++ b/a.txt\n'
          '@@ -1 +1 @@\n'
          '-x\n'
          '+',
        ),
        0xff, // a lone continuation byte, as a latin-1 file would produce
        0x0a,
      ];
      var patch = indexPatch(Uint8List.fromList(bytes));
      expect(patch.files.single.added, 1);
      expect(() => patch.textFor(patch.files.single), returnsNormally);
    });
  });

  test('an empty patch is an empty list, not a failure', () {
    expect(index('').files, isEmpty);
    expect(indexPatch(Uint8List(0)).files, isEmpty);
  });
}
