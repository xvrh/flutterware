/// Where a verb's finger went.
///
/// A scenario runs with no cursor and no pointer of any kind on screen, so a
/// picture of a tap is indistinguishable from a picture of the screen sitting
/// still — the step says `tap "Cappuccino"` and nothing in the pixels says
/// *which* Cappuccino, or where. This is the missing half: the box the verb
/// resolved to, in the app's own logical pixels, measured on the frame the
/// verb was about to act on.
///
/// One class for both ends of the wire, like [ScenarioNotification]: the
/// scenario measures it, the panel and the exported page draw it, and the
/// schema exists once. It rides the step inline — six numbers and a word at
/// most, so there is no file to fetch before a viewer can point at something.
///
/// The coordinates are the ones every other rect in a report is in: the
/// view's logical pixels, the same space [InspectLayout] writes and the same
/// space the screenshot is laid out in, so drawing it needs no transform.
///
/// The rect does not always mean "the thing that was touched". For a
/// pointer verb it is the box the finder resolved. For `scrollTo` it is the
/// scrollable's viewport and [toward] is where the target is; for `keyboard`
/// it is the band the stage is about to take or give back. The verb on the
/// step says which, and it is the verb a viewer switches on.
class ScenarioAim {
  const ScenarioAim({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.dx,
    this.dy,
    this.toward,
  });

  static ScenarioAim? fromJson(Object? json) => switch (json) {
    Map json => ScenarioAim(
      x: _double(json['x']),
      y: _double(json['y']),
      width: _double(json['w']),
      height: _double(json['h']),
      dx: json['dx'] == null ? null : _double(json['dx']),
      dy: json['dy'] == null ? null : _double(json['dy']),
      toward: json['toward'] as String?,
    ),
    _ => null,
  };

  static double _double(Object? value) => value is num ? value.toDouble() : 0.0;

  /// The resolved target's box — what the verb aimed at, not necessarily what
  /// draws the button. `tap('Cappuccino')` resolves the `Text`, so this is the
  /// word's box and the tap landed at its centre, which is the truth of what
  /// happened and is why a viewer marks the point as well as the box.
  final double x;
  final double y;
  final double width;
  final double height;

  /// How far the finger travelled, for `drag` — the verb's own offset, in the
  /// same logical pixels. Null for a verb that did not move.
  final double? dx;
  final double? dy;

  /// Which way a verb that acts on a *region* travels — `'up'`, `'down'`,
  /// `'left'`, `'right'`. Null for every verb that acts on a point, and for a
  /// region verb that moves nothing.
  ///
  /// Not the same claim as [dx]/[dy], which is a measured distance. This is a
  /// direction and nothing more, because a direction is all a region verb
  /// honestly knows before it acts: `scrollTo` cannot say how far it will
  /// walk, and the box it will walk to is not measurable on the frame the
  /// mark is drawn on — the ladder scrolls before it is there. What it can
  /// say is *which pane* ([x] … [height]) and *which way*, and that is all
  /// this pair says.
  final String? toward;

  /// The point the pointer went down on. Every pointer verb taps the centre of
  /// the box it resolved, so this is derived rather than recorded — a second
  /// pair of numbers saying what the first pair already says would be a
  /// schema that can disagree with itself.
  (double, double) get point => (x + width / 2, y + height / 2);

  Map<String, Object?> toJson() => {
    'x': x,
    'y': y,
    'w': width,
    'h': height,
    if (dx != null) 'dx': dx,
    if (dy != null) 'dy': dy,
    if (toward != null) 'toward': toward,
  };
}
