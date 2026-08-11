import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware_app/src/changes/diff_shape.dart';
import 'package:flutterware_app/src/changes/patch_index.dart';

/// The two rules that read the change rather than the path, and the cases where
/// they must **refuse to claim anything**. Every one of these demotes a file
/// out of the main list, so being wrong here costs a user the thing they came
/// to see.
void main() {
  PatchIndex index(List<String> lines) =>
      indexPatch(Uint8List.fromList(utf8.encode(lines.join('\n'))));

  DiffShape shapeOfPatch(List<String> body, {String path = 'lib/a.dart'}) {
    var patch = index([
      'diff --git a/$path b/$path',
      '--- a/$path',
      '+++ b/$path',
      ...body,
      '',
    ]);
    return shapeOf(patch, patch.files.single);
  }

  group('whitespace only', () {
    test('a reindent is whitespace only', () {
      expect(
        shapeOfPatch(['@@ -1,1 +1,1 @@', '-  var x = 1;', '+var x = 1;']),
        DiffShape.whitespaceOnly,
      );
    });

    test('a rewrap across lines is still whitespace only', () {
      expect(
        shapeOfPatch(['@@ -1,1 +1,2 @@', '-foo(a, b);', '+foo(a,', '+    b);']),
        DiffShape.whitespaceOnly,
      );
    });

    test('blank lines added and removed are whitespace only', () {
      // Both squeezed sides are empty, which is still a true statement about
      // the change.
      expect(
        shapeOfPatch(['@@ -1,1 +1,1 @@', '-', '+', '+']),
        DiffShape.whitespaceOnly,
      );
    });

    test('one character of real content is not', () {
      expect(
        shapeOfPatch(['@@ -1,1 +1,1 @@', '-var x = 1;', '+var x = 2;']),
        DiffShape.none,
      );
    });

    test('context lines are not part of the comparison', () {
      // A context line appears on both sides; counting it would make every
      // hunk with more context than change look like a reformat.
      expect(
        shapeOfPatch([
          '@@ -1,3 +1,3 @@',
          ' before',
          '-  x();',
          '+x();',
          ' after',
        ]),
        DiffShape.whitespaceOnly,
      );
    });
  });

  group('imports only', () {
    test('a reordered import block', () {
      expect(
        shapeOfPatch([
          '@@ -1,2 +1,2 @@',
          "-import 'b.dart';",
          "-import 'a.dart';",
          "+import 'a.dart';",
          "+import 'b.dart';",
        ]),
        DiffShape.importsOnly,
      );
    });

    test('part counts too', () {
      expect(
        shapeOfPatch([
          '@@ -1,2 +1,2 @@',
          "-part 'a.g.dart';",
          "+part 'b.g.dart';",
        ]),
        DiffShape.importsOnly,
      );
    });

    test('an export is the public surface, and is never noise', () {
      // Found by running this over a real branch: `lib/plugins.dart` gaining
      // one `export` line landed in the drawer, and that line *is* the API.
      expect(
        shapeOfPatch([
          '@@ -1,1 +1,2 @@',
          " import 'a.dart';",
          "+export 'src/new_thing.dart';",
        ]),
        DiffShape.none,
      );
    });

    test('a wrapped import fails towards showing the file', () {
      // `    show Foo;` is a continuation, not a directive. Failing towards
      // *showing* is the only acceptable direction for a rule that hides.
      expect(
        shapeOfPatch([
          '@@ -1,2 +1,2 @@',
          "-import 'a.dart' show Foo;",
          "+import 'a.dart'",
          '+    show Foo, Bar;',
        ]),
        DiffShape.none,
      );
    });

    test('only blank lines in a Dart file is whitespace, not imports', () {
      // A blank line is *compatible* with a directive block but is not one.
      // Without the distinction this would claim "only imports changed" about
      // a change containing no imports at all.
      expect(
        shapeOfPatch(['@@ -1,2 +1,1 @@', '-', '-']),
        DiffShape.whitespaceOnly,
      );
    });

    test('a non-Dart file is never imports-only', () {
      // The rule reads Dart syntax; claiming it about a `.py` would be a guess.
      expect(
        shapeOfPatch([
          '@@ -1,1 +1,1 @@',
          '-import os',
          '+import sys',
        ], path: 'tool/run.py'),
        DiffShape.none,
      );
    });
  });

  group('refusing to claim anything', () {
    test('a binary file is not read', () {
      var patch = index([
        'diff --git a/x.png b/x.png',
        'index 1111111..2222222 100644',
        'Binary files a/x.png and b/x.png differ',
        '',
      ]);
      expect(shapeOf(patch, patch.files.single), DiffShape.none);
    });

    test('a rename with no body is not whitespace-only', () {
      // Nothing changed at all, so "only whitespace changed" would be a claim
      // about a change that has no lines.
      var patch = index([
        'diff --git a/old.dart b/new.dart',
        'similarity index 100%',
        'rename from old.dart',
        'rename to new.dart',
        '',
      ]);
      expect(shapeOf(patch, patch.files.single), DiffShape.none);
    });

    test(r'the \ no-newline marker is not a changed line', () {
      expect(
        shapeOfPatch([
          '@@ -1,1 +1,1 @@',
          '-var x = 1;',
          r'\ No newline at end of file',
          '+  var x = 1;',
        ]),
        DiffShape.whitespaceOnly,
      );
    });
  });
}
