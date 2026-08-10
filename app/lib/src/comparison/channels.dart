import 'pixel_diff.dart';
import 'tree_diff.dart';

/// One thing compared, on every channel that had something to say.
///
/// **Channels rather than "a picture plus some extras."** Pixels have a
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
    this.note,
  });

  /// What was compared: an entry id, or a step's path through its flow.
  final String id;

  final ComparedState state;

  /// How it names itself on screen — a step's `tap #pay`, an entry's name.
  final String? label;

  final PixelChannel? pixels;
  final TreeChannel? tree;
  final TextChannel? texts;

  /// Why it is in the state it is, when the state alone does not say: which
  /// file made it worth rendering, or which side failed to render.
  final String? note;

  Map<String, Object?> toJson() => {
    'id': id,
    'state': state.name,
    'label': ?label,
    'note': ?note,
    if (pixels != null || tree != null || texts != null)
      'channels': {
        'pixels': ?pixels?.toJson(),
        'tree': ?tree?.toJson(),
        'texts': ?texts?.toJson(),
      },
  };

  /// Assembles the verdict from the channels.
  ///
  /// The ladder is severity, not arithmetic. **A head that fails to render
  /// outranks everything**: it is the one result the tool exists to catch, and
  /// a percentage next to it would be answering a smaller question. A base
  /// that fails is the opposite — it says the entry was already broken before
  /// this branch, which is worth saying once and quietly.
  static ComparedItem of({
    required String id,
    String? label,
    PixelDiff? pixels,
    TreeDiff? tree,
    List<String> baseTexts = const [],
    List<String> headTexts = const [],
    bool baseRendered = true,
    bool headRendered = true,
    String? note,
  }) {
    if (!headRendered) {
      return ComparedItem(
        id: id,
        label: label,
        state: baseRendered ? ComparedState.broke : ComparedState.failed,
        note: note ?? (baseRendered ? 'renders on base, throws here' : null),
      );
    }
    if (!baseRendered) {
      return ComparedItem(
        id: id,
        label: label,
        state: ComparedState.wasBroken,
        note: note ?? 'was already broken on base',
      );
    }

    var textChannel = TextChannel.of(base: baseTexts, head: headTexts);
    var treeChannel = tree == null ? null : TreeChannel(tree);
    var pixelChannel = pixels == null ? null : PixelChannel(pixels);
    var changed =
        (pixelChannel?.changed ?? false) ||
        (treeChannel?.changed ?? false) ||
        textChannel.changed;

    return ComparedItem(
      id: id,
      label: label,
      state: changed ? ComparedState.changed : ComparedState.same,
      pixels: pixelChannel,
      tree: treeChannel,
      texts: textChannel.changed ? textChannel : null,
      note: note,
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
  skipped,
}

class PixelChannel {
  const PixelChannel(this.diff);

  final PixelDiff diff;

  bool get changed => diff.changed;

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
