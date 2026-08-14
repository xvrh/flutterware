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

  InspectLogLine _withText(String replacement) =>
      InspectLogLine(sequence: sequence, text: replacement, at: at);
}

/// The longest single line a step hands back.
///
/// Generous for a `print` and mean for a protocol dump, which is the line this
/// is drawn on. Measured 2026-08-13 driving the flutterware GUI: one
/// `device.added` blob from the flutter daemon is about 4KB, and a step that
/// caught a few of them cost more context than the screen it was reporting.
const maxStepLogLineChars = 2000;

/// The most lines a step hands back.
///
/// [GuestLogs] holds five hundred, because a scrollback should; a *step* is a
/// different question — "what did this act print" — and fifty is already more
/// than anybody reads. What this drops is a flood, and a flood is exactly what
/// the reader cannot use.
const maxStepLogLines = 50;

/// [lines], trimmed to what a step's reply can afford — and saying so.
///
/// **Nothing is dropped silently.** A reply that quietly shortened its own
/// evidence would be worse than one that costs too much: the reader would draw
/// conclusions from a log it believed was complete. So an over-long line keeps
/// its head and admits its tail, and an over-long step keeps its most recent
/// lines behind one entry saying how many came before — the same end
/// [GuestLogs] keeps when its own buffer overflows.
///
/// The full scrollback is still there: `run/inspect` with `logs` reads the
/// guest's buffer, which this does not touch. This shapes one reply, not the
/// record.
List<InspectLogLine> capStepLogs(
  List<InspectLogLine> lines, {
  int maxLines = maxStepLogLines,
  int maxChars = maxStepLogLineChars,
}) {
  var kept = [
    for (var line
        in lines.length > maxLines
            ? lines.sublist(lines.length - maxLines)
            : lines)
      if (line.text.length <= maxChars)
        line
      else
        line._withText(
          '${line.text.substring(0, maxChars)}… '
          '(+${line.text.length - maxChars} chars)',
        ),
  ];
  var dropped = lines.length - kept.length;
  if (dropped == 0) return kept;
  return [
    InspectLogLine(
      sequence: kept.isEmpty ? 0 : kept.first.sequence - 1,
      text: '… (+$dropped earlier lines)',
      at: kept.isEmpty ? 0 : kept.first.at,
    ),
    ...kept,
  ];
}
