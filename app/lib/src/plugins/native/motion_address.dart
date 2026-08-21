/// How the motion plugin writes itself into an address, and how it reads itself
/// back out — both directions in one file, with a round-trip test, for the
/// reason `dependencies_address.dart` gives.
///
/// ```
/// <package>                       the package's motion list
/// <package>/<file…>/<motion>      one motion, scrubbable
/// ```
///
/// The package path is one segment (the framework escapes `/`); the source file
/// is split into path segments so the tree reads naturally; the file's end is
/// recognised by its `.dart` suffix, which is what makes the values identifier
/// after it unambiguous.
///
/// The playhead rides above the segments, as `?t=`. It is an axis, not a
/// place: `t` is to a motion what `device` and `language` are to a scenario, and
/// the rule that a screenshot is under-specified without its axis assignment is
/// exactly why it has to be in the address at all. Park the playhead at 0.42,
/// copy the URL, and what comes back is the frame you were looking at.
library;

/// A place in the motion plugin.
class MotionPlace {
  const MotionPlace(this.package, {this.file, this.motion, this.t})
    : assert(motion == null || file != null, 'a motion needs its file');

  /// The workspace-relative package path whose motions are shown.
  final String package;

  /// The package-relative source file, `/`-separated, or null for the list.
  final String? file;

  /// The `motion:` identifier within [file], or null for the whole file.
  final String? motion;

  /// Where the playhead is, 0..1, or null for "wherever it was".
  ///
  /// Null rather than 0, and the difference is the whole point: an address that
  /// defaulted to the start would rewind the motion every time anybody clicked
  /// a link to it.
  final double? t;

  MotionPlace withT(double? t) =>
      MotionPlace(package, file: file, motion: motion, t: t);

  @override
  bool operator ==(Object other) =>
      other is MotionPlace &&
      other.package == package &&
      other.file == file &&
      other.motion == motion &&
      other.t == t;

  @override
  int get hashCode => Object.hash(package, file, motion, t);

  @override
  String toString() =>
      'MotionPlace($package'
      '${file == null ? '' : '/$file'}'
      '${motion == null ? '' : '#$motion'}'
      '${t == null ? '' : '@$t'})';
}

/// The address segments naming [package] and, if given, where inside it.
List<String> motionSegments(String package, {String? file, String? motion}) {
  assert(motion == null || file != null, 'a motion needs its file');
  return [package, ...?file?.split('/'), ?motion];
}

/// The inverse of [motionSegments], with [t] read off the parameters.
///
/// A tail this does not recognise — no `.dart` segment, or trailing segments
/// past the identifier — reads as the nearest place it does recognise, which
/// leaves the panel showing something rather than nothing. A `t` that is not a
/// number in 0..1 is dropped for the same reason: a bad playhead should lose
/// the playhead, not the screen.
MotionPlace? motionPlace(List<String> segments, {String? t}) {
  if (segments.isEmpty) return null;
  var package = segments.first;
  var rest = segments.skip(1).toList();
  var parsed = switch (double.tryParse(t ?? '')) {
    var value? when value >= 0 && value <= 1 => value,
    _ => null,
  };

  var dartIndex = rest.indexWhere((segment) => segment.endsWith('.dart'));
  if (dartIndex < 0) return MotionPlace(package, t: parsed);
  var file = rest.take(dartIndex + 1).join('/');
  var motion = dartIndex + 1 < rest.length ? rest[dartIndex + 1] : null;
  return MotionPlace(package, file: file, motion: motion, t: parsed);
}

/// How `t` is written into an address, and the reason it is not `toString()`.
///
/// Three decimals is a millisecond either way on a one-second motion, which is
/// finer than the playhead can be dragged and far shorter than
/// `0.4166666666666667`. An address is something people paste into messages.
String? formatMotionT(double? t) =>
    t?.toStringAsFixed(3).replaceFirst(RegExp(r'\.?0+$'), '');
