/// A note left on this delta for the agent that produced it.
///
/// **A comment is an observation, not a pointer.** It carries the code it was
/// written about, quoted at the moment you wrote it, and the line numbers are a
/// hint beside that quote rather than the thing being stored. That is the whole
/// answer to *what happens when the agent keeps editing while I type*: nothing
/// happens, because nothing here addresses a line that can move. The receiving
/// agent relocates a three-line snippet better than any tracking we could write
/// against a [DiffLine], which has no identity, or a [HunkSpan], whose only key
/// is a byte range that any upstream edit invalidates.
///
/// Pure Dart — no widgets, no `dart:io` — so the model, the folding and the
/// markdown are all testable without pumping or writing a file.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Which side of the diff a line number is counted on.
///
/// A removed line exists only in the old file and an added line only in the
/// new one, so a comment on either has exactly one number that means anything.
/// Recording which avoids the classic off-by-a-whole-file error of printing an
/// old-side number as if you could open the file and find it there.
enum ReviewSide {
  /// Numbers on the left gutter: the file as the base branch has it.
  before,

  /// Numbers on the right gutter: the file as this checkout has it.
  after,
}

/// What a comment is about.
///
/// **Three anchors, and no more.** A line-only tool forces *this whole file is
/// untested* into a lie about line 1, and forces *three of these are the same
/// problem* into a lie about a file. Each of the three is a thing people
/// actually write, and each reads differently in the handoff.
sealed class ReviewAnchor {
  const ReviewAnchor();

  /// The file this comment is filed under, or null for [ReviewWide].
  String? get path;

  /// The whole thing — the grammar you would use to look it up, and the only
  /// spelling the markdown ever uses. An agent gets a path or it gets nothing.
  String get label;

  /// The part worth reading in a 320 px column: the file's name and the line.
  ///
  /// The directory is not dropped, it is [directory] — drawn beside this,
  /// dimmed, and the first thing given up when the row runs out of width.
  String get shortLabel {
    var slash = label.lastIndexOf('/');
    return slash < 0 ? label : label.substring(slash + 1);
  }

  /// Everything before [shortLabel], with its trailing slash, or null when the
  /// anchor names no directory.
  ///
  /// Drawn beside [shortLabel] where there is room for it — the composer — and
  /// given up entirely where there is not. The index row carries it in a
  /// tooltip instead: sharing a 320 px line, it ellipsised the name it was
  /// supposed to make room for.
  String? get directory {
    var slash = label.lastIndexOf('/');
    return slash < 0 ? null : label.substring(0, slash + 1);
  }

  Map<String, Object?> toJson();

  static ReviewAnchor fromJson(Map<String, Object?> json) =>
      switch (json['kind']) {
        'line' => LineAnchor(
          path: json['path']! as String,
          from: json['from']! as int,
          to: json['to']! as int,
          side: json['side'] == 'before' ? ReviewSide.before : ReviewSide.after,
        ),
        'file' => FileAnchor(json['path']! as String),
        _ => const ReviewWide(),
      };
}

/// One line, or a span of them.
final class LineAnchor extends ReviewAnchor {
  const LineAnchor({
    required this.path,
    required this.from,
    required this.to,
    required this.side,
  });

  @override
  final String path;

  /// Inclusive, and in the numbering [side] names.
  final int from;
  final int to;

  final ReviewSide side;

  bool get isSpan => to > from;

  @override
  String get label => isSpan ? '$path:$from–$to' : '$path:$from';

  @override
  Map<String, Object?> toJson() => {
    'kind': 'line',
    'path': path,
    'from': from,
    'to': to,
    'side': side.name,
  };
}

/// The file, with no line worth singling out.
final class FileAnchor extends ReviewAnchor {
  const FileAnchor(this.path);

  @override
  final String path;

  @override
  String get label => path;

  @override
  Map<String, Object?> toJson() => {'kind': 'file', 'path': path};
}

/// The review itself — the note that is about the shape of the change rather
/// than about any part of it.
final class ReviewWide extends ReviewAnchor {
  const ReviewWide();

  @override
  String? get path => null;

  @override
  String get label => 'Whole review';

  @override
  Map<String, Object?> toJson() => const {'kind': 'review'};
}

/// One note.
class ReviewComment {
  const ReviewComment({
    required this.id,
    required this.anchor,
    required this.body,
    required this.createdAt,
    this.quote = const [],
    this.fileDigest,
  });

  /// Unique within a worktree's log, and stable across a rewrite of the body —
  /// it is what a delete and an edit name.
  final String id;

  final ReviewAnchor anchor;

  /// What you wrote.
  final String body;

  final DateTime createdAt;

  /// The code as it stood when you wrote the comment, without diff markers.
  ///
  /// **Kept as it was, forever.** Re-reading it from the current patch would
  /// turn a note about a line the agent has since deleted into a note about
  /// whatever now occupies that position, which is the one failure mode a
  /// review tool must not have.
  final List<String> quote;

  /// A fingerprint of the file's slice of the patch at capture time.
  ///
  /// The only drift claim we can make honestly: *this file changed after you
  /// commented*. Whether **your** line moved is not knowable from a patch, and
  /// a badge that claimed it would be wrong exactly when it mattered. Null for
  /// [ReviewWide], which is about no file.
  final String? fileDigest;

  ReviewComment withBody(String body) => ReviewComment(
    id: id,
    anchor: anchor,
    body: body,
    createdAt: createdAt,
    quote: quote,
    fileDigest: fileDigest,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'anchor': anchor.toJson(),
    'body': body,
    'createdAt': createdAt.toIso8601String(),
    if (quote.isNotEmpty) 'quote': quote,
    if (fileDigest != null) 'fileDigest': fileDigest,
  };

  static ReviewComment fromJson(Map<String, Object?> json) => ReviewComment(
    id: json['id']! as String,
    anchor: ReviewAnchor.fromJson(
      (json['anchor']! as Map).cast<String, Object?>(),
    ),
    body: json['body']! as String,
    createdAt:
        DateTime.tryParse('${json['createdAt']}') ??
        DateTime.fromMillisecondsSinceEpoch(0),
    quote: [for (var line in json['quote'] as List? ?? const []) '$line'],
    fileDigest: json['fileDigest'] as String?,
  );
}

/// A batch that has been handed off, and is therefore closed.
///
/// **There is no *Clear* button**, and this is why. You accumulate, you hand
/// off, the batch moves here; the next comment opens the next batch. A clear
/// button asks *are you sure* about work whose only copy is on this screen,
/// and it makes "I already sent these" and "I gave up on these" the same
/// gesture.
class ReviewBatch {
  const ReviewBatch({
    required this.id,
    required this.comments,
    required this.handedOffAt,
    required this.route,
    this.savedTo,
  });

  final String id;
  final List<ReviewComment> comments;
  final DateTime handedOffAt;

  /// How it left: `copy` or `file`. Shown in history, because *I copied it* and
  /// *I wrote it to disk* have different next steps when the agent says it saw
  /// nothing.
  final String route;

  /// Where it was written, for the file route.
  final String? savedTo;
}

/// The fingerprint [ReviewComment.fileDigest] holds.
///
/// Over the file's own bytes of the patch rather than over the whole patch, so
/// an edit somewhere else in the branch does not mark every comment stale.
String digestOfPatchSlice(List<int> bytes) => sha1.convert(bytes).toString();

/// The handoff, as markdown.
///
/// **This is the artefact, not a preview of one.** Both routes render it — the
/// clipboard and the file are two ways of moving the same text — so there is
/// one format to keep readable and one to test.
///
/// Fenced with the language guessed from the extension, because an agent that
/// gets ` ```dart ` reads the snippet as code on the first pass.
String reviewMarkdown(
  List<ReviewComment> comments, {
  required String worktree,
  String? base,
  DateTime? at,
  Set<String> drifted = const {},
}) {
  var buffer = StringBuffer()..writeln('# Review — $worktree');
  var meta = [
    if (base != null) 'Against `$base`',
    '${comments.length} ${comments.length == 1 ? 'comment' : 'comments'}',
    if (at != null) _clock(at),
  ];
  buffer
    ..writeln(meta.join(' · '))
    ..writeln();

  for (var comment in comments) {
    buffer.writeln('## ${comment.anchor.label}');
    if (comment.anchor.path case var path? when drifted.contains(path)) {
      buffer.writeln(
        '> ⚠ this file has changed since the comment was written — the quote '
        'below is as it stood then.',
      );
    }
    if (comment.quote.isNotEmpty) {
      buffer
        ..writeln('```${_language(comment.anchor.path)}')
        ..writeAll(comment.quote, '\n')
        ..writeln()
        ..writeln('```');
    }
    buffer
      ..writeln(comment.body.trim())
      ..writeln();
  }

  return '${buffer.toString().trimRight()}\n';
}

String _clock(DateTime at) =>
    '${at.hour.toString().padLeft(2, '0')}:'
    '${at.minute.toString().padLeft(2, '0')}';

/// The fence's language tag. Unknown extensions get no tag rather than a wrong
/// one — a mislabelled fence is worse for a reader than an unlabelled one.
String _language(String? path) {
  if (path == null) return '';
  var dot = path.lastIndexOf('.');
  if (dot < 0) return '';
  return switch (path.substring(dot + 1).toLowerCase()) {
    'dart' => 'dart',
    'yaml' || 'yml' => 'yaml',
    'json' => 'json',
    'md' => 'markdown',
    'sh' || 'bash' || 'zsh' => 'bash',
    'html' => 'html',
    'css' => 'css',
    'js' => 'javascript',
    'ts' => 'typescript',
    'kt' => 'kotlin',
    'swift' => 'swift',
    'java' => 'java',
    'py' => 'python',
    'sql' => 'sql',
    'xml' => 'xml',
    _ => '',
  };
}

/// One line of the append-only log, as it is written and read back.
///
/// **Events rather than a snapshot.** The alternative — a JSON document holding
/// the current list — is what `worktrees.json` is, and it has a documented
/// clobber history across Studio instances: two windows on one repository each
/// write the whole file, and the last one wins. An appended line physically
/// cannot revert another writer's line.
sealed class ReviewEvent {
  const ReviewEvent();

  String encode() => jsonEncode(toJson());

  Map<String, Object?> toJson();

  /// Null for a line this version does not understand, which is how a log
  /// written by a newer build degrades to *the events I know* rather than to a
  /// crash on startup.
  static ReviewEvent? decode(String line) {
    try {
      var json = jsonDecode(line);
      if (json is! Map) return null;
      var map = json.cast<String, Object?>();
      return switch (map['event']) {
        'add' => CommentAdded(
          ReviewComment.fromJson((map['comment']! as Map).cast()),
        ),
        'edit' => CommentEdited(
          id: map['id']! as String,
          body: map['body']! as String,
        ),
        'delete' => CommentDeleted(map['id']! as String),
        'handoff' => BatchHandedOff(
          id: map['batch']! as String,
          ids: [for (var id in map['ids'] as List? ?? const []) '$id'],
          at:
              DateTime.tryParse('${map['at']}') ??
              DateTime.fromMillisecondsSinceEpoch(0),
          route: '${map['route'] ?? 'copy'}',
          savedTo: map['savedTo'] as String?,
        ),
        _ => null,
      };
    } on Object {
      // A half-written final line, or a field a future version added and made
      // required. Neither is worth losing the rest of the log over.
      return null;
    }
  }
}

final class CommentAdded extends ReviewEvent {
  const CommentAdded(this.comment);
  final ReviewComment comment;

  @override
  Map<String, Object?> toJson() => {
    'event': 'add',
    'comment': comment.toJson(),
  };
}

final class CommentEdited extends ReviewEvent {
  const CommentEdited({required this.id, required this.body});
  final String id;
  final String body;

  @override
  Map<String, Object?> toJson() => {'event': 'edit', 'id': id, 'body': body};
}

/// A delete, as a tombstone rather than as a removal.
///
/// An append-only log cannot unwrite a line, and would not want to: the
/// tombstone is what makes two windows agree about a comment one of them
/// deleted.
final class CommentDeleted extends ReviewEvent {
  const CommentDeleted(this.id);
  final String id;

  @override
  Map<String, Object?> toJson() => {'event': 'delete', 'id': id};
}

final class BatchHandedOff extends ReviewEvent {
  const BatchHandedOff({
    required this.id,
    required this.ids,
    required this.at,
    required this.route,
    this.savedTo,
  });

  final String id;
  final List<String> ids;
  final DateTime at;
  final String route;
  final String? savedTo;

  @override
  Map<String, Object?> toJson() => {
    'event': 'handoff',
    'batch': id,
    'ids': ids,
    'at': at.toIso8601String(),
    'route': route,
    if (savedTo != null) 'savedTo': savedTo,
  };
}

/// What a log folds down to: the batch you are writing, and the ones you sent.
class ReviewState {
  const ReviewState({this.open = const [], this.history = const []});

  /// The batch being accumulated, oldest comment first — the order they are
  /// numbered in, and the order they are handed off in.
  final List<ReviewComment> open;

  /// Handed-off batches, **newest first**.
  final List<ReviewBatch> history;

  bool get isEmpty => open.isEmpty && history.isEmpty;

  /// Folds a log into the two lists.
  ///
  /// Order of events is the order of the file, which is the order they
  /// happened — that is the one guarantee appending gives, and everything here
  /// leans on it rather than on timestamps, which two clocks can disagree
  /// about.
  static ReviewState fold(Iterable<ReviewEvent> events) {
    var byId = <String, ReviewComment>{};
    var order = <String>[];
    var history = <ReviewBatch>[];

    for (var event in events) {
      switch (event) {
        case CommentAdded(:var comment):
          if (!byId.containsKey(comment.id)) order.add(comment.id);
          byId[comment.id] = comment;
        case CommentEdited(:var id, :var body):
          if (byId[id] case var it?) byId[id] = it.withBody(body);
        case CommentDeleted(:var id):
          byId.remove(id);
          order.remove(id);
        case BatchHandedOff(
          :var id,
          :var ids,
          :var at,
          :var route,
          :var savedTo,
        ):
          var taken = [for (var commentId in ids) ?byId.remove(commentId)];
          order.removeWhere(ids.contains);
          // A batch whose comments were all deleted before it was folded is
          // not history, it is nothing — and a row saying *0 comments* is a
          // row nobody can act on.
          if (taken.isEmpty) continue;
          history.add(
            ReviewBatch(
              id: id,
              comments: taken,
              handedOffAt: at,
              route: route,
              savedTo: savedTo,
            ),
          );
      }
    }

    return ReviewState(
      open: [for (var id in order) byId[id]!],
      history: history.reversed.toList(),
    );
  }
}
