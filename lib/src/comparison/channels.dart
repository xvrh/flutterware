import 'pixel_diff.dart';
import 'tree_diff.dart';

/// One thing compared, on every channel that had something to say.
///
/// Channels rather than "a picture plus some extras." Pixels have a
/// threshold, texts are exact, and the events channel that is coming will need
/// field masks for tokens and timestamps. Making each channel own its own
/// rules now is what lets a new one land later without reopening the kernel —
/// and what lets a reader who cannot see pixels, which is every agent, read
/// the same comparison a human is looking at.
class ComparedItem {
  const ComparedItem({
    required this.id,
    required this.state,
    this.label,
    this.pixels,
    this.tree,
    this.texts,
    this.events,
    this.note,
    this.shots,
  });

  /// What was compared: an entry id, or a step's path through its flow.
  final String id;

  final ComparedState state;

  /// How it names itself on screen — a step's `tap #pay`, an entry's name.
  final String? label;

  final PixelChannel? pixels;
  final TreeChannel? tree;
  final TextChannel? texts;
  final EventChannel? events;

  /// Why it is in the state it is, when the state alone does not say: which
  /// file made it worth rendering, or which side failed to render.
  final String? note;

  /// Where the two frames are filed, as `ShotCache` keys.
  ///
  /// The verdict is not the picture, and a reader wants both. Without this
  /// a comparison could say a preview changed by 0.38% and nothing anywhere
  /// could show it: the keys are computed inside the runner from a closure
  /// fingerprint nobody outside can reproduce. They go in the artifact too, so
  /// a panel, an agent and a static page all address the same two files.
  final ({String base, String head})? shots;

  Map<String, Object?> toJson() => {
    'id': id,
    'state': state.name,
    'label': ?label,
    'note': ?note,
    'shots': ?(shots == null
        ? null
        : {'base': shots!.base, 'head': shots!.head}),
    if (pixels != null || tree != null || texts != null || events != null)
      'channels': {
        'pixels': ?pixels?.toJson(),
        'tree': ?tree?.toJson(),
        'texts': ?texts?.toJson(),
        'events': ?events?.toJson(),
      },
  };

  /// A row read back off `index.json` — what an exported page draws from.
  ///
  /// Lossy exactly where [toJson] is: the pixel counts come back as the rounded
  /// fraction, the mask never travels, and a capped cluster list stays capped.
  /// Everything a viewer draws survives the round trip; nothing recomputes.
  static ComparedItem fromJson(Map<String, Object?> json) {
    var channels = json['channels'] as Map<String, Object?>? ?? const {};
    var shots = json['shots'] as Map<String, Object?>?;
    var base = shots?['base'] as String?;
    var head = shots?['head'] as String?;
    return ComparedItem(
      id: json['id'] as String? ?? '',
      state:
          ComparedState.values.asNameMap()[json['state']] ??
          ComparedState.skipped,
      label: json['label'] as String?,
      note: json['note'] as String?,
      shots: base == null || head == null ? null : (base: base, head: head),
      pixels: switch (channels['pixels']) {
        Map<String, Object?> pixels => PixelChannel.fromJson(pixels),
        _ => null,
      },
      tree: switch (channels['tree']) {
        Map<String, Object?> tree => TreeChannel.fromJson(tree),
        _ => null,
      },
      texts: switch (channels['texts']) {
        Map<String, Object?> texts => TextChannel.fromJson(texts),
        _ => null,
      },
      events: switch (channels['events']) {
        Map<String, Object?> events => EventChannel.fromJson(events),
        _ => null,
      },
    );
  }

  /// Assembles the verdict from the channels.
  ///
  /// The ladder is severity rather than arithmetic. A head that fails to render
  /// outranks everything: it is the result the tool exists to catch, and a
  /// percentage next to it would answer a smaller question. A base that fails
  /// is the opposite — it means the entry was already broken before this
  /// branch, which is worth stating once and quietly.
  static ComparedItem of({
    required String id,
    String? label,
    PixelDiff? pixels,
    TreeDiff? tree,
    List<String> baseTexts = const [],
    List<String> headTexts = const [],
    List<Map<String, Object?>> baseEvents = const [],
    List<Map<String, Object?>> headEvents = const [],
    bool baseRendered = true,
    bool headRendered = true,
    String? note,
    ({String base, String head})? shots,
  }) {
    if (!headRendered) {
      return ComparedItem(
        id: id,
        label: label,
        state: baseRendered ? ComparedState.broke : ComparedState.failed,
        note: note ?? (baseRendered ? 'renders on base, throws here' : null),
        shots: shots,
      );
    }
    if (!baseRendered) {
      return ComparedItem(
        id: id,
        label: label,
        state: ComparedState.wasBroken,
        note: note ?? 'was already broken on base',
        shots: shots,
      );
    }

    var textChannel = TextChannel.of(base: baseTexts, head: headTexts);
    var eventChannel = EventChannel.of(base: baseEvents, head: headEvents);
    var treeChannel = tree == null ? null : TreeChannel(tree);
    var pixelChannel = pixels == null ? null : PixelChannel(pixels);
    var changed =
        (pixelChannel?.changed ?? false) ||
        (treeChannel?.changed ?? false) ||
        textChannel.changed ||
        eventChannel.changed;

    return ComparedItem(
      id: id,
      label: label,
      state: changed ? ComparedState.changed : ComparedState.same,
      pixels: pixelChannel,
      tree: treeChannel,
      texts: textChannel.changed ? textChannel : null,
      events: eventChannel.changed ? eventChannel : null,
      note: note,
      shots: shots,
    );
  }
}

/// Declared in the order a report ranks them: the top row should be the thing
/// most likely to be a mistake.
enum ComparedState {
  /// Renders on base, throws on head. The most valuable output in the tool.
  broke,

  /// Neither side renders.
  failed,

  /// Throws on base, renders on head — already broken before this branch.
  wasBroken,

  /// Only on head.
  added,

  /// Only on base.
  removed,

  changed,

  /// Compared and identical.
  same,

  /// Not compared, because nothing it reads differs between the two
  /// checkouts. Indistinguishable from [same] in truth, and worth its own name
  /// so a report can say how much work it did not do.
  skipped;

  /// True for the states worth drawing attention to. [same] and [skipped] mean
  /// "nothing to see", and a list that highlights those does not get read to
  /// the end.
  bool get isFinding => this != same && this != skipped;
}

class PixelChannel {
  const PixelChannel(this.diff);

  final PixelDiff diff;

  bool get changed => diff.changed;

  /// The written form back into a [PixelDiff] a stage can draw.
  ///
  /// The exact counts are gone — [toJson] keeps a rounded fraction — so they
  /// are reconstructed from it, which is faithful to the same five decimal
  /// places every reader of the file sees.
  static PixelChannel fromJson(Map<String, Object?> json) {
    var width = json['width'] as int? ?? 0;
    var height = json['height'] as int? ?? 0;
    var fraction = (json['changed'] as num?)?.toDouble() ?? 0;
    return PixelChannel(
      PixelDiff(
        width: width,
        height: height,
        comparedPixels: width * height,
        changedPixels: (fraction * width * height).round(),
        sizeChanged: json['sizeChanged'] as bool? ?? false,
        clusters: [
          for (var rect in json['clusters'] as List? ?? const [])
            DiffRect.fromJson((rect as Map).cast<String, Object?>()),
        ],
      ),
    );
  }

  Map<String, Object?> toJson() => {
    'changed': double.parse(diff.fraction.toStringAsFixed(5)),
    'sizeChanged': diff.sizeChanged,
    'width': diff.width,
    'height': diff.height,
    // The eye's jump targets and an agent's coordinates, and capped: a
    // repainted background is thousands of one-pixel specks, and a reader
    // wants the regions rather than the confetti.
    'clusters': [for (var rect in diff.clusters.take(24)) rect.toJson()],
    if (diff.clusters.length > 24) 'clustersDropped': diff.clusters.length - 24,
  };
}

class TreeChannel {
  const TreeChannel(this.diff);

  final TreeDiff diff;

  static TreeChannel fromJson(Map<String, Object?> json) => TreeChannel(
    TreeDiff([
      for (var delta in json['deltas'] as List? ?? const [])
        TreeDelta.fromJson((delta as Map).cast<String, Object?>()),
    ]),
  );

  /// A tree that differs *only* below a resized ancestor has not changed —
  /// something above it did, and that something is already reported.
  bool get changed =>
      diff.deltas.any((delta) => delta.kind != TreeDeltaKind.shifted);

  Map<String, Object?> toJson() => {
    'deltas': [for (var delta in diff.deltas.take(50)) delta.toJson()],
    if (diff.deltas.length > 50) 'deltasDropped': diff.deltas.length - 50,
  };
}

/// The visible text, which diffs exactly and costs nothing.
///
/// The cheapest channel and the most legible one in a terminal: a label that
/// changed shows up here as two lines, where the pixel channel can only say
/// what fraction of the screen moved.
class TextChannel {
  const TextChannel({required this.added, required this.removed});

  static TextChannel fromJson(Map<String, Object?> json) => TextChannel(
    added: (json['added'] as List? ?? const []).cast<String>(),
    removed: (json['removed'] as List? ?? const []).cast<String>(),
  );

  factory TextChannel.of({
    required List<String> base,
    required List<String> head,
  }) {
    // Multiset, not set: a list gaining a second "Buy" is a change, and two
    // sets would call it nothing.
    var remaining = <String, int>{};
    for (var text in base) {
      remaining[text] = (remaining[text] ?? 0) + 1;
    }
    var added = <String>[];
    for (var text in head) {
      var left = remaining[text] ?? 0;
      if (left > 0) {
        remaining[text] = left - 1;
      } else {
        added.add(text);
      }
    }
    var removed = [
      for (var entry in remaining.entries)
        for (var i = 0; i < entry.value; i++) entry.key,
    ];
    return TextChannel(added: added, removed: removed);
  }

  final List<String> added;
  final List<String> removed;

  bool get changed => added.isNotEmpty || removed.isNotEmpty;

  Map<String, Object?> toJson() => {'added': added, 'removed': removed};
}

/// What the app did on the way to a step, compared.
///
/// The channel that catches what no picture can: a duplicated request, a new
/// analytics call, an N+1 that appeared because somebody moved a fetch into a
/// builder. None of those change a pixel, and all of them are regressions.
///
/// Masked before compared, and that is the whole reason this is a channel
/// with rules of its own rather than a list diff. A request carries a token, a
/// timestamp and a request id; compare them raw and every transition differs
/// every time. What survives masking is what a reader meant by "the same
/// request".
class EventChannel {
  const EventChannel({required this.added, required this.removed});

  static EventChannel fromJson(Map<String, Object?> json) => EventChannel(
    added: (json['added'] as List? ?? const []).cast<String>(),
    removed: (json['removed'] as List? ?? const []).cast<String>(),
  );

  factory EventChannel.of({
    required List<Map<String, Object?>> base,
    required List<Map<String, Object?>> head,
  }) {
    // A multiset over the masked form: two identical requests are two events,
    // and a transition that starts making a second one is a change.
    var remaining = <String, int>{};
    for (var event in base) {
      var key = mask(event);
      remaining[key] = (remaining[key] ?? 0) + 1;
    }
    var added = <String>[];
    for (var event in head) {
      var key = mask(event);
      var left = remaining[key] ?? 0;
      if (left > 0) {
        remaining[key] = left - 1;
      } else {
        added.add(key);
      }
    }
    return EventChannel(
      added: added,
      removed: [
        for (var entry in remaining.entries)
          for (var i = 0; i < entry.value; i++) entry.key,
      ],
    );
  }

  /// One event reduced to what makes it *that* event.
  ///
  /// The channel and the title, and nothing else: the detail is a status code
  /// or a row count, the data is a payload, and the body is a whole request —
  /// all of which move for reasons that are not the branch's. A status that
  /// changed is worth seeing and is not this; it is what the detail-level diff
  /// a panel shows is for.
  ///
  /// Digits in the title collapse to `#`, because an id in a path — `/order/
  /// 8814` — is the commonest way a run differs from itself for no reason.
  static String mask(Map<String, Object?> event) {
    var channel = event['channel'] as String? ?? '';
    var title = event['title'] as String? ?? '';
    return '$channel ${title.replaceAll(RegExp(r'\d+'), '#')}';
  }

  final List<String> added;
  final List<String> removed;

  bool get changed => added.isNotEmpty || removed.isNotEmpty;

  Map<String, Object?> toJson() => {'added': added, 'removed': removed};
}
