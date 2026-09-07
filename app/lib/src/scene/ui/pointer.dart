import 'package:flutter/gestures.dart';

/// The devices an editing gesture listens to — a drag that moves a node, a
/// key or the playhead.
///
/// Not the trackpad. Flutter's drag recognizers accept a trackpad's
/// two-finger scroll as a drag (that is how a list scrolls under one), so a
/// detector that took every device turned a scroll over the ruler into a
/// seek to wherever the fingers were, and one over a key strip into a key
/// drag. A trackpad's scroll and pinch reach the editor as pointer signals
/// and pan-zoom events, which the canvas and the timeline handle themselves.
const editingDevices = {
  PointerDeviceKind.mouse,
  PointerDeviceKind.touch,
  PointerDeviceKind.stylus,
};
