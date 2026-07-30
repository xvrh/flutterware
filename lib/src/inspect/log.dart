/// What the demo printed.
///
/// Pure Dart, like every model here, because `fw` links it and cannot link
/// `package:flutter/widgets.dart`.
class InspectLogs {
  const InspectLogs({
    required this.entryId,
    this.lines = const [],
    this.dropped = 0,
  });

  static const empty = InspectLogs(entryId: null);

  /// Which entry was on screen when these were printed. The same rule
  /// `InspectTree.entryId` and `InspectErrors.entryId` follow: a report naming
  /// another entry is a read from before a switch, not an empty one.
  final String? entryId;

  final List<InspectLogLine> lines;

  /// How many lines fell off the front of the buffer.
  ///
  /// Reported rather than silently forgotten. A console that quietly begins in
  /// the middle reads as a console that has everything, and the one time that
  /// matters is the one time you are looking for the first line.
  final int dropped;

  bool get isEmpty => lines.isEmpty;

  static InspectLogs fromJson(Map<String, Object?> json) => InspectLogs(
    entryId: json['entryId'] as String?,
    dropped: (json['dropped'] as num?)?.toInt() ?? 0,
    lines: [
      for (var line in json['lines'] as List? ?? const [])
        if (line is Map) InspectLogLine.fromJson(line.cast<String, Object?>()),
    ],
  );

  Map<String, Object?> toJson() => {
    'entryId': entryId,
    'dropped': dropped,
    'lines': [for (var line in lines) line.toJson()],
  };
}

/// One line, with enough on it to be merged with a stream of the same lines.
class InspectLogLine {
  const InspectLogLine({
    required this.sequence,
    required this.text,
    required this.at,
  });

  /// Monotonic within one guest, and the whole reason a console can be both
  /// pulled and pushed without showing anything twice.
  ///
  /// A reader takes the buffer when it opens and subscribes to the pushes at
  /// the same time; the two overlap by however long the round trip took. With
  /// this, the overlap is dropped by number. Without it, the reader would have
  /// to match on text and time and would still be wrong about a demo printing
  /// the same word twice in a frame.
  final int sequence;

  final String text;

  /// Milliseconds since the epoch, from the guest's clock.
  ///
  /// The guest's rather than the host's, deliberately: this is when the demo
  /// printed, not when a reader got round to asking. The two differ by a poll
  /// interval, and the whole point of a timestamp is to say what happened
  /// before what.
  final int at;

  static InspectLogLine fromJson(Map<String, Object?> json) => InspectLogLine(
    sequence: (json['n'] as num?)?.toInt() ?? 0,
    text: json['text'] as String? ?? '',
    at: (json['at'] as num?)?.toInt() ?? 0,
  );

  Map<String, Object?> toJson() => {'n': sequence, 'text': text, 'at': at};
}
