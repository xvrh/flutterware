/// What the guest says when the thing you are looking at has moved.
///
/// Pure Dart, in its own file rather than beside [GuestWatch], for the reason
/// every model here is: the guest half imports `package:flutter/widgets.dart`
/// and `fw` cannot link that. Both ends encode and decode through this one
/// class, so a field renamed on one side fails to compile on the other —
/// which is the cheap version of the check that `setParameter` did not have.
class WatchPush {
  const WatchPush({
    required this.entryId,
    required this.frame,
    required this.nodes,
    required this.hashMicros,
    this.structureChanged = false,
    this.resized = false,
    this.scrolled = false,
    this.geometry,
  });

  /// Which entry the guest was showing. A push that arrives after a switch
  /// describes a demo that is no longer on screen, and only this makes that
  /// detectable.
  final String? entryId;

  /// The guest's own frame counter since the watch started, so a host can see
  /// gaps — a run of frames with no push is either nothing moving or events
  /// being dropped, and the two look identical without it.
  final int frame;

  /// How many elements the shape walk touched.
  final int nodes;

  /// What that walk cost, on this frame.
  ///
  /// Carried in every push rather than behind a separate question, because a
  /// per-frame cost that has to be asked for is one nobody reads until
  /// something is already slow.
  final int hashMicros;

  /// The shape of the element tree changed — the host should re-read the tree.
  ///
  /// A flag rather than the tree itself: the host already knows how to read
  /// `ext.flutterware.tree`, and what it cannot do is know when to. Sending the
  /// tree would put the expensive walk on the frame that detected the change,
  /// which is the frame least able to afford it.
  final bool structureChanged;

  /// The demo was given a different box — so **every** rect in the tree is out
  /// of date, though not one widget in it changed.
  ///
  /// Its own signal rather than folded into [structureChanged], because the
  /// shape did not change and saying it did would be a lie the host could act
  /// on. It is also the commonest real staleness there is: dragging the panel
  /// divider resizes the preview, and until this existed the tree went on
  /// reporting the widths it had before the drag — including whether anything
  /// overflowed.
  final bool resized;

  /// Something in the demo scrolled — so the rects below it have all moved,
  /// though the shape did not change and neither did the demo's box.
  ///
  /// **Still moving, not finished moving.** This arrives on every frame of a
  /// fling, and a host that re-read the tree on each one would queue walks
  /// faster than they complete. What it says is "wait for me": read once the
  /// pushes stop.
  final bool scrolled;

  /// The watched node's box, when it moved.
  final WatchBox? geometry;

  static WatchPush fromJson(Map<String, Object?> json) => WatchPush(
    entryId: json['entryId'] as String?,
    frame: (json['frame'] as num?)?.toInt() ?? 0,
    nodes: (json['nodes'] as num?)?.toInt() ?? 0,
    hashMicros: (json['hashMicros'] as num?)?.toInt() ?? 0,
    structureChanged: json['structure'] == true,
    resized: json['resized'] == true,
    scrolled: json['scrolled'] == true,
    geometry: switch (json['geometry']) {
      Map box => WatchBox.fromJson(box.cast<String, Object?>()),
      _ => null,
    },
  );

  Map<String, Object?> toJson() => {
    'entryId': entryId,
    'frame': frame,
    'nodes': nodes,
    'hashMicros': hashMicros,
    if (structureChanged) 'structure': true,
    if (resized) 'resized': true,
    if (scrolled) 'scrolled': true,
    if (geometry case var box?) 'geometry': box.toJson(),
  };
}

/// One node's box, in the guest's own coordinates — the space
/// `InspectLayout.x` reports and a capture is taken in.
class WatchBox {
  const WatchBox({
    required this.id,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  final String? id;
  final double x;
  final double y;
  final double width;
  final double height;

  static WatchBox fromJson(Map<String, Object?> json) => WatchBox(
    id: json['id'] as String?,
    x: (json['x'] as num?)?.toDouble() ?? 0,
    y: (json['y'] as num?)?.toDouble() ?? 0,
    width: (json['width'] as num?)?.toDouble() ?? 0,
    height: (json['height'] as num?)?.toDouble() ?? 0,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'x': x,
    'y': y,
    'width': width,
    'height': height,
  };
}

/// What the watch has cost so far, read rather than pushed.
///
/// The answer to "is this affordable" has to survive the case that matters
/// most — a watch whose events are arriving too slowly to trust — so it is
/// available to something that is not subscribed at all.
class WatchStats {
  const WatchStats({
    required this.watching,
    required this.entryId,
    required this.node,
    required this.frames,
    required this.pushes,
    required this.nodes,
    required this.hashMicrosLast,
    required this.hashMicrosMean,
    required this.hashMicrosMax,
    required this.resolveMicrosLast,
    required this.resolved,
    required this.minIntervalMillis,
  });

  final bool watching;
  final String? entryId;
  final String? node;
  final int frames;
  final int pushes;
  final int nodes;
  final int hashMicrosLast;
  final int hashMicrosMean;
  final int hashMicrosMax;

  /// What turning a node id back into a render object cost, the last time it
  /// had to be done. Separate from the per-frame figure on purpose: it is a
  /// whole summary-tree walk, and it is the number that says how expensive it
  /// would have been to do this per frame instead of caching it.
  final int resolveMicrosLast;

  final bool resolved;
  final int minIntervalMillis;

  static WatchStats fromJson(Map<String, Object?> json) => WatchStats(
    watching: json['watching'] == true,
    entryId: json['entryId'] as String?,
    node: json['node'] as String?,
    frames: (json['frames'] as num?)?.toInt() ?? 0,
    pushes: (json['pushes'] as num?)?.toInt() ?? 0,
    nodes: (json['nodes'] as num?)?.toInt() ?? 0,
    hashMicrosLast: (json['hashMicrosLast'] as num?)?.toInt() ?? 0,
    hashMicrosMean: (json['hashMicrosMean'] as num?)?.toInt() ?? 0,
    hashMicrosMax: (json['hashMicrosMax'] as num?)?.toInt() ?? 0,
    resolveMicrosLast: (json['resolveMicrosLast'] as num?)?.toInt() ?? 0,
    resolved: json['resolved'] == true,
    minIntervalMillis: (json['minIntervalMillis'] as num?)?.toInt() ?? 0,
  );

  Map<String, Object?> toJson() => {
    'watching': watching,
    'entryId': entryId,
    'node': node,
    'frames': frames,
    'pushes': pushes,
    'nodes': nodes,
    'hashMicrosLast': hashMicrosLast,
    'hashMicrosMean': hashMicrosMean,
    'hashMicrosMax': hashMicrosMax,
    'resolveMicrosLast': resolveMicrosLast,
    'resolved': resolved,
    'minIntervalMillis': minIntervalMillis,
  };
}
