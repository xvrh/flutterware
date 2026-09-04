import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutterware/scene.dart';
import 'package:flutterware/scene_authoring.dart';

import 'editor.dart';

/// One motion of the editor's file, bound and given a clock.
///
/// The transport and the timeline both draw from this and drive it; the
/// scene document is what they *listen* to for position, because every tick
/// lands on the fx plane and the plane notifies. This notifies only for the
/// things a tick does not change — status and rate.
class ScenePlayback extends ChangeNotifier {
  ScenePlayback(this.editor, this.motionName, {required this.vsync}) {
    _bind();
    _shape = _shapeOf();
    editor.addListener(_onEdit);
  }

  /// The binding walks groups and the timeline by reference, so a moved key
  /// needs nothing — but a group added, a track created or the timeline
  /// rearranged (including by undo) is a different structure, and only a
  /// rebind knows it. Cheap to check on every edit; done only when it moved.
  late String _shape;

  String _shapeOf() {
    var m = motion;
    return [
      for (var g in m.groups)
        '${g.name}:${g.tracks.keys.join(',')}/${g.args.keys.join(',')}',
      _exprShape(m.timeline),
    ].join('|');
  }

  static String _exprShape(TimelineExpr e) => switch (e) {
    AnimateGroup g => g.name,
    ParExpr p => 'par(${p.children.map(_exprShape).join(',')})',
    SeqExpr s => 'seq(${s.children.map(_exprShape).join(',')})',
    AtExpr a => 'at${a.offset.inMicroseconds}(${_exprShape(a.child)})',
    SpeedExpr s => 'x${s.factor}(${_exprShape(s.child)})',
    RepeatExpr r => 'rep${r.times}(${_exprShape(r.child)})',
  };

  void _onEdit() {
    // The motion was deleted or renamed out from under this playback; the
    // owner drops it on its next look, and until then there is nothing here
    // to apply.
    if (!editor.motions.containsKey(motionName)) return;
    var shape = _shapeOf();
    if (shape != _shape) {
      _shape = shape;
      rebind();
      return;
    }
    // Stopped: the fx are off the scene and only [apply] puts them back.
    // This listens to the EDITOR, which notifies for hovering a node and
    // for closing the motion as much as for editing a key — so without
    // this the pose came back inside the very gesture that dropped it.
    if (!_applied) return;
    // A key's value changed under a parked playhead: the picture is stale
    // until the motion is applied again. Playing re-applies every tick.
    if (!isPlaying) _player.position = _player.position;
  }

  final SceneEditor editor;
  final String motionName;
  final TickerProvider vsync;

  late BoundMotion _bound;
  late MotionPlayer _player;

  MotionDocument get motion => editor.motions[motionName]!;

  void _bind() {
    _bound = BoundMotion.bind(motion, editor.doc);
    _player = MotionPlayer.bound(_bound, vsync: vsync)
      ..addListener(() => editor.playhead = _player.position);
    editor.playhead = _player.position;
  }

  /// Rebinds after the motion's shape changed — a group placed or removed.
  /// A moved key needs none of this: the binding reads the track it holds.
  void rebind() {
    var at = position;
    var wasPlaying = isPlaying;
    var wasApplied = _applied;
    // Disposing stops the old player, which drops the fx it wrote.
    _player.dispose();
    _bind();
    if (wasApplied) {
      seek(at);
      if (wasPlaying) play();
    }
    notifyListeners();
  }

  Duration get duration => _bound.duration;
  Duration get position => _player.position;
  bool get isPlaying => _player.status == MotionPlayerStatus.playing;
  bool get isIdle => _player.status == MotionPlayerStatus.idle;

  /// Whether the motion is on the picture — its fx written to the nodes.
  ///
  /// What the stop button undoes, and the one thing that says whether this
  /// playback may write to the scene at all. Not derivable from the
  /// player's status: a seek applies a pose and leaves the player idle, so
  /// idle-at-zero is both "stopped" and "parked on the first frame".
  bool get isApplied => _applied;
  var _applied = true;

  double get rate => _player.rate;
  set rate(double value) {
    _player.rate = value;
    notifyListeners();
  }

  /// 0..1 along the motion; 0 for a motion of no length, past 1 beyond it.
  double get t => duration == Duration.zero
      ? 0
      : position.inMicroseconds / duration.inMicroseconds;

  bool get autoKey => editor.autoKey;
  set autoKey(bool value) => editor.autoKey = value;

  /// Puts the motion back on the picture at the playhead — what opening a
  /// motion does, including reopening one that was closed.
  void apply() {
    _applied = true;
    _player.position = _player.position;
    notifyListeners();
  }

  void play() {
    _applied = true;
    _player.play();
    notifyListeners();
  }

  void pause() {
    _player.pause();
    notifyListeners();
  }

  void toggle() => isPlaying ? pause() : play();

  /// Cancel: the fx come off and nothing puts them back until [apply],
  /// [play] or a [seek].
  void stop() {
    _applied = false;
    _player.stop();
    notifyListeners();
  }

  void seek(Duration at) {
    _applied = true;
    _player.position = at;
    notifyListeners();
  }

  void seekT(double t) => seek(duration * t.clamp(0.0, 1.0));

  @override
  void dispose() {
    editor.removeListener(_onEdit);
    _player.dispose();
    super.dispose();
  }
}
