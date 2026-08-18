import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware_app/src/changes/change_set.dart';
import 'package:flutterware_app/src/changes/changes_screen.dart';
import 'package:flutterware_app/src/changes/patch_index.dart';
import 'package:flutterware_app/src/shell/worktree.dart';
import 'package:flutterware_app/src/ui/theme.dart';

/// The bodies a diff cannot draw, against a **real directory**: these tests
/// exist because the pane used to show an untracked file nothing at all, and
/// a placeholder saying "every line is new" is not a line of the file.
void main() {
  late Directory temp;

  // Sync IO throughout the setup: a widget test's body runs under FakeAsync,
  // where a real async file operation never completes and the test hangs in
  // `setUp` before its first line.
  setUp(() {
    temp = Directory.systemTemp.createTempSync('file_body_test');
  });

  tearDown(() => temp.deleteSync(recursive: true));

  Worktree worktree() =>
      Worktree(path: temp.path, gitName: 'feature', branch: 'claude/feature');

  FileChange file(String path, {required ChangeStatus status}) => FileChange(
    path: path,
    status: status,
    added: 1,
    removed: 0,
    hunks: [
      HunkSpan(
        oldStart: 1,
        oldCount: 0,
        newStart: 1,
        newCount: 1,
        added: 1,
        removed: 0,
        byteStart: 0,
        byteEnd: 0,
      ),
    ],
    byteStart: 0,
    byteEnd: 0,
  );

  ChangeSet setOf({
    List<FileChange> files = const [],
    List<UntrackedEntry> untracked = const [],
  }) => ChangeSet(
    worktreePath: temp.path,
    patch: PatchIndex.empty,
    base: 'master',
    baseSource: BaseSource.inferred,
    files: files,
    untracked: untracked,
  );

  Future<void> pump(
    WidgetTester tester,
    ChangeSet set, {
    required String open,
  }) async {
    // A realistic pane, not the 800 px default: the test font draws every
    // glyph as a full square, so the header's toggle and button measure far
    // wider here than they ever do in the app — see the header overflow that
    // only Ahem could produce.
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme,
        home: Scaffold(
          body: ChangesScreen(
            worktree: worktree(),
            live: false,
            initialPath: open,
            load: (_) async => set,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Lets the real file reads behind the body complete, then draws them.
  ///
  /// Plain `pumpAndSettle` cannot: the test body runs under FakeAsync, where
  /// real IO futures never fire. And one `runAsync` is not enough either —
  /// a future created in the fake zone resumes only on a pump, so a chain of
  /// awaits (stat, then read, then the builder's own `then`) advances one
  /// link per window. Alternate until the chain is longer than any body has.
  Future<void> settleIo(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  testWidgets('an untracked markdown file opens rendered', (tester) async {
    File(
      '${temp.path}/notes.md',
    ).writeAsStringSync('# A heading\n\nA paragraph of prose.\n');
    await pump(
      tester,
      setOf(untracked: const [UntrackedEntry('notes.md')]),
      open: 'notes.md',
    );
    await settleIo(tester);

    // Rendered: the heading's text without its `#`.
    expect(find.textContaining('A heading', findRichText: true), findsOne);
    expect(
      find.textContaining('# A heading', findRichText: true),
      findsNothing,
    );
    // And the toggle offers the other face.
    expect(find.text('Source'), findsOne);
    expect(find.text('Rendered'), findsOne);
  });

  testWidgets('the toggle flips a markdown body to its lines', (tester) async {
    File('${temp.path}/notes.md').writeAsStringSync('# A heading\n');
    await pump(
      tester,
      setOf(untracked: const [UntrackedEntry('notes.md')]),
      open: 'notes.md',
    );
    await settleIo(tester);

    await tester.tap(find.text('Source'));
    await settleIo(tester);

    // The source face is the file's own line, marker and all.
    expect(find.text('# A heading'), findsOne);
  });

  testWidgets('an untracked text file shows its numbered lines', (
    tester,
  ) async {
    File('${temp.path}/scratch.txt').writeAsStringSync('first\nsecond\n');
    await pump(
      tester,
      setOf(untracked: const [UntrackedEntry('scratch.txt')]),
      open: 'scratch.txt',
    );
    await settleIo(tester);

    expect(find.text('first'), findsOne);
    expect(find.text('second'), findsOne);
    expect(find.text('2'), findsOne);
    // No toggle: a plain text file has one face.
    expect(find.text('Source'), findsNothing);
  });

  testWidgets('an untracked binary file is refused in words', (tester) async {
    File('${temp.path}/blob.bin').writeAsBytesSync([104, 105, 0, 33]);
    await pump(
      tester,
      setOf(untracked: const [UntrackedEntry('blob.bin')]),
      open: 'blob.bin',
    );
    await settleIo(tester);

    expect(find.textContaining('Binary file'), findsOne);
  });

  testWidgets('an untracked image gets the viewer, not a notice', (
    tester,
  ) async {
    File('${temp.path}/pixel.png').writeAsBytesSync(base64Decode(_pixelPng));
    await pump(
      tester,
      setOf(untracked: const [UntrackedEntry('pixel.png')]),
      open: 'pixel.png',
    );
    await settleIo(tester);

    expect(find.byType(Image), findsOne);
    expect(find.textContaining('B'), findsWidgets); // the byte-size caption
  });

  testWidgets('a tracked, added markdown file opens rendered', (tester) async {
    File('${temp.path}/README.md').writeAsStringSync('# Fresh\n');
    await pump(
      tester,
      setOf(files: [file('README.md', status: ChangeStatus.added)]),
      open: 'README.md',
    );
    await settleIo(tester);

    expect(find.textContaining('Fresh', findRichText: true), findsWidgets);
    expect(find.textContaining('@@'), findsNothing);
  });

  testWidgets('a modified markdown file opens on its diff, toggle in reach', (
    tester,
  ) async {
    File('${temp.path}/README.md').writeAsStringSync('# Fresh\n');
    await pump(
      tester,
      setOf(files: [file('README.md', status: ChangeStatus.modified)]),
      open: 'README.md',
    );
    await settleIo(tester);

    // The diff is the default — the change is what review is about.
    expect(find.textContaining('@@'), findsOne);

    await tester.tap(find.text('Rendered'));
    await settleIo(tester);
    expect(find.textContaining('Fresh', findRichText: true), findsWidgets);
    expect(find.textContaining('@@'), findsNothing);
  });

  testWidgets('a tracked image replaces the binary notice with the viewer', (
    tester,
  ) async {
    File('${temp.path}/pixel.png').writeAsBytesSync(base64Decode(_pixelPng));
    var image = FileChange(
      path: 'pixel.png',
      status: ChangeStatus.added,
      added: 0,
      removed: 0,
      isBinary: true,
      hunks: const [],
      byteStart: 0,
      byteEnd: 0,
    );
    await pump(tester, setOf(files: [image]), open: 'pixel.png');
    await settleIo(tester);

    expect(find.byType(Image), findsOne);
    expect(find.textContaining('no lines to show'), findsNothing);
  });
}

/// A 1×1 transparent PNG — 68 bytes, the smallest honest image.
const _pixelPng =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhf'
    'DwAChwGA60e6kgAAAABJRU5ErkJggg==';
