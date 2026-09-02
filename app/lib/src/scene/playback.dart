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
    GroupRef r => r.name,
    ParExpr p => 'par(${p.children.map(_exprShape).join(',')})',
    SeqExpr s => 'seq(${s.children.map(_exprShape).join(',')})',
    AtExpr a => 'at${a.offset.inMicroseconds}(${_exprShape(a.child)})',
    SpeedExpr s => 'x${s.factor}(${_exprShape(s.child)})',
    RepeatExpr r => 'rep${r.times}(${_exprShape(r.child)})',
  };

  void _onEdit() {
    var shape = _shapeOf();
    if (shape == _shape) return;
    _shape = shape;
    rebind();
  }

  final SceneEditor editor;
  final String motionName;
  final TickerProvider vsync;

  late BoundMotion _bound;
  late MotionPlayer _player;

  MotionDocument get motion => editor.motions[motionName]!;

  void _bind() {
    _bound = BoundMotion.bind(motion, editor.doc);
    _player = MotionPlayer(_bound, vsync: vsync);
  }

  /// Rebinds after the motion's shape changed — a group placed or removed.
  /// A moved key needs none of this: the binding reads the track it holds.
  void rebind() {
    var at = position;
    var wasPlaying = isPlaying;
    _player.dispose();
    _bind();
    seek(at);
    if (wasPlaying) play();
    notifyListeners();
  }

  Duration get duration => _bound.duration;
  Duration get position => _player.position;
  bool get isPlaying => _player.status == MotionPlayerStatus.playing;
  bool get isIdle => _player.status == MotionPlayerStatus.idle;

  double get rate => _player.rate;
  set rate(double value) {
    _player.rate = value;
    notifyListeners();
  }

  /// 0..1 along the motion; 0 for a motion of no length.
  double get t => duration == Duration.zero
      ? 0
      : position.inMicroseconds / duration.inMicroseconds;

  void play() {
    _player.play();
    notifyListeners();
  }

  void pause() {
    _player.pause();
    notifyListeners();
  }

  void toggle() => isPlaying ? pause() : play();

  void stop() {
    _player.stop();
    notifyListeners();
  }

  void seek(Duration at) {
    _player.seek(at);
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
