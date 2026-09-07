// What a walk drives.
//
// The previews harness photographs a screen at a series of playhead
// positions, and until now it reached for one particular runtime's registry
// to do it. This is that seam, named: anything that is a function of `t` —
// the scene runtime's player, an app's own controller — registers here, and
// the harness knows nothing else about it.
//
// Pure Dart on purpose: it is a contract, and a contract that imported a
// framework would decide who may implement it.
library;

/// Something a walk can park at a moment.
abstract class Playhead {
  /// How long it runs. The walk asks, because only the running thing knows —
  /// a caller computing its own stops would have to render once to find out.
  Duration get duration;

  /// Park at [position] and leave it there. No time passes: what the next
  /// frame draws must be `evaluate(position)` and nothing else, which is what
  /// makes a walk verifiable by taking it backwards.
  void seek(Duration position);
}

/// The playheads mounted in this isolate, in mount order.
class PlayheadRegistry {
  PlayheadRegistry._();

  static final instance = PlayheadRegistry._();

  final _mounted = <String, Playhead>{};
  var _nextId = 0;

  /// Mount order, which is also the order a panel would list them in.
  Iterable<String> get ids => _mounted.keys;

  String attach(Playhead playhead) {
    var id = '${_nextId++}';
    _mounted[id] = playhead;
    return id;
  }

  void detach(String id) => _mounted.remove(id);

  /// The one an argument names, the only one when there is only one, or null.
  ///
  /// Defaulting to the sole playhead is what lets a walk drive the common
  /// case — one screen, one motion — without first asking for an id.
  Playhead? resolve(String? id) {
    if (id != null) return _mounted[id];
    return _mounted.length == 1 ? _mounted.values.first : null;
  }

  /// The id to drive when the caller named none: null when there is one (the
  /// resolver's own default answers), and the first when there are several,
  /// so a screen that mounts two still renders rather than refusing.
  String? get defaultId {
    var mounted = ids.toList();
    return mounted.length == 1 ? null : mounted.firstOrNull;
  }
}
