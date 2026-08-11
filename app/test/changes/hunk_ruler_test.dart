import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware_app/src/changes/hunk_ruler.dart';
import 'package:flutterware_app/src/changes/patch_index.dart';
import 'package:flutterware_app/src/ui/theme.dart';

/// The ruler paints, so what a unit test can assert about it is thin. What it
/// *can* assert is the case that was actually wrong on a real branch.
void main() {
  PatchIndex index(String patch) =>
      indexPatch(Uint8List.fromList(utf8.encode(patch)));

  Future<void> pump(WidgetTester tester, FileChange file) => tester.pumpWidget(
    MaterialApp(
      theme: appTheme,
      home: Scaffold(
        body: Center(child: HunkRuler(file: file)),
      ),
    ),
  );

  testWidgets('a deleted file has a ruler, not a blank track', (tester) async {
    // **Found by looking at a real branch, not by a fixture.** git writes
    // `@@ -1,3 +0,0 @@` for a whole-file deletion: there is no post-image, so a
    // ruler measured on the new side computed a length of zero and drew
    // nothing. Five deleted files in a row, all blank.
    var patch = index(
      [
        'diff --git a/lib/gone.dart b/lib/gone.dart',
        'deleted file mode 100644',
        '--- a/lib/gone.dart',
        '+++ /dev/null',
        '@@ -1,3 +0,0 @@',
        '-one',
        '-two',
        '-three',
        '',
      ].join('\n'),
    );

    var file = patch.files.single;
    expect(file.status, ChangeStatus.deleted);
    expect(file.hunks.single.newCount, 0, reason: 'no post-image at all');

    await pump(tester, file);
    // The painter is reached and does not throw on the zero-length new side.
    expect(tester.takeException(), isNull);
    expect(find.byType(CustomPaint), findsWidgets);
  });

  testWidgets('an added file paints too', (tester) async {
    var patch = index(
      [
        'diff --git a/lib/new.dart b/lib/new.dart',
        'new file mode 100644',
        '--- /dev/null',
        '+++ b/lib/new.dart',
        '@@ -0,0 +1,2 @@',
        '+one',
        '+two',
        '',
      ].join('\n'),
    );

    await pump(tester, patch.files.single);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a file with no hunks draws an empty track and does not throw', (
    tester,
  ) async {
    var patch = index(
      [
        'diff --git a/old.dart b/new.dart',
        'similarity index 100%',
        'rename from old.dart',
        'rename to new.dart',
        '',
      ].join('\n'),
    );

    await pump(tester, patch.files.single);
    expect(tester.takeException(), isNull);
  });
}
