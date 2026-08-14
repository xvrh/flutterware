/// Where review comments live between launches.
///
/// **An append-only log, one file per checkout.** Not a field in
/// `worktrees.json`: that file is read-whole and written-whole by every
/// flutterware process on the repository, and it has a documented history of
/// one window reverting another's writes. A line appended to a log cannot
/// revert a line somebody else appended — the failure mode is bounded to *my
/// window has not noticed yours yet*, which a re-read fixes, rather than *your
/// six comments are gone*, which nothing fixes.
///
/// **Keyed by the worktree, not by the repository.** Elsewhere in the app that
/// would be the wrong way round — per-project identity keys on the main
/// checkout — but a review is of *this* branch's delta against *its* base.
/// Two worktrees of one repository are two different reviews, and merging them
/// into one list would be the same mistake as merging their diffs.
///
/// Outside the checkout, like every other cache here: a review file written
/// into the worktree would show up as an untracked row on the very screen it
/// belongs to.
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../utils/run_dir.dart';
import 'review_comment.dart';

/// The log for one checkout.
class ReviewStore {
  ReviewStore(this.file);

  /// `~/.flutterware/<sha1 of the worktree path>/review.jsonl`.
  ReviewStore.forWorktree(String worktreePath)
    : file = File(fileFor(worktreePath));

  static String fileFor(String worktreePath) => p.join(
    flutterwareDir(),
    sha1.convert(utf8.encode(p.canonicalize(worktreePath))).toString(),
    'review.jsonl',
  );

  final File file;

  /// Everything the log says, folded.
  ///
  /// **Never throws.** A log that will not parse is an empty log — the same
  /// rule the facts cache follows, and for a stronger reason: this screen is
  /// how you look at a checkout, and refusing to draw it because a note file
  /// was truncated would be a worse program than one that had never stored
  /// notes.
  ReviewState read() => ReviewState.fold(_events());

  Iterable<ReviewEvent> _events() sync* {
    List<String> lines;
    try {
      if (!file.existsSync()) return;
      lines = const LineSplitter().convert(file.readAsStringSync());
    } on Object {
      return;
    }
    for (var line in lines) {
      if (line.trim().isEmpty) continue;
      if (ReviewEvent.decode(line) case var event?) yield event;
    }
  }

  /// Appends [events] and returns the log as it now reads.
  ///
  /// The re-read is the point: it folds in whatever another window appended
  /// since this one last looked, at no cost worth measuring — these files are
  /// kilobytes, and this runs when you press a button rather than per frame.
  ReviewState append(List<ReviewEvent> events) {
    try {
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(
        events.map((e) => '${e.encode()}\n').join(),
        mode: FileMode.append,
        flush: true,
      );
    } on Object {
      // A read-only home, or a disk that just filled. The comment stays on
      // screen for this session either way — losing what you typed because the
      // log could not be written would be the worst possible response.
    }
    return read();
  }
}

/// The screen's handle on the log.
///
/// Deliberately thin: it holds the folded state, and every mutation is an
/// append followed by the re-read the append already does. There is no
/// in-memory list that the file is a backup of, because two such lists on one
/// machine is exactly the divergence the append-only format exists to avoid.
class ReviewController extends ChangeNotifier {
  ReviewController({required String worktreePath, ReviewStore? store})
    : _store = store ?? ReviewStore.forWorktree(worktreePath) {
    _state = _store.read();
  }

  final ReviewStore _store;
  late ReviewState _state;

  ReviewState get state => _state;
  List<ReviewComment> get open => _state.open;
  List<ReviewBatch> get history => _state.history;

  /// Comments on [path], in the order they were written.
  List<ReviewComment> forFile(String path) => [
    for (var comment in _state.open)
      if (comment.anchor.path == path) comment,
  ];

  void add(ReviewComment comment) => _apply([CommentAdded(comment)]);

  void edit(String id, String body) =>
      _apply([CommentEdited(id: id, body: body)]);

  void delete(String id) => _apply([CommentDeleted(id)]);

  /// Closes the open batch.
  ///
  /// Takes the ids explicitly rather than "everything open" so that the batch
  /// handed off is the batch the sheet was showing — a comment added in
  /// another window while the sheet was up belongs to the next batch, not to
  /// the one you already copied.
  void handOff({
    required String id,
    required List<String> ids,
    required DateTime at,
    required String route,
    String? savedTo,
  }) => _apply([
    BatchHandedOff(id: id, ids: ids, at: at, route: route, savedTo: savedTo),
  ]);

  /// Re-reads without writing — for a window that has been sitting open while
  /// another one was used.
  void reload() {
    _state = _store.read();
    notifyListeners();
  }

  void _apply(List<ReviewEvent> events) {
    _state = _store.append(events);
    notifyListeners();
  }
}

/// A fresh comment id.
///
/// Time plus a per-process counter: unique inside one window by the counter,
/// and across windows by the microsecond, which two of them do not share.
String newReviewId() =>
    '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}'
    '-${(_counter++).toRadixString(36)}';

int _counter = 0;
