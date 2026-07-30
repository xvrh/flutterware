import 'package:flutter/widgets.dart';

/// Marks a tree that exists to be photographed.
///
/// **A signal, not a policy.** This says only that the window was launched to
/// produce a picture; what to do about it belongs to each widget, because only
/// the widget knows which of the things it draws are facts about the project
/// and which are facts about this run. The capture code deliberately has no
/// list of what to hide — a panel added next year would not be on it.
///
/// The case that motivated it: the catalog's status bar draws `cold 3421ms`,
/// and the same command a minute later drew `cold 6554ms`. Nothing was wrong;
/// a timing is simply not a property of the thing being photographed. Committed
/// screenshots that disagree on it churn the repository on every regeneration.
///
/// **Absent means false**, so every widget that has never heard of this keeps
/// behaving exactly as it does now, and [isCapturing] needs no null handling at
/// the call site.
///
/// Guidance for a widget deciding what to do with it, since "do what you want"
/// is easy to take too far: hide what *varies without meaning* — elapsed times,
/// counters, anything sampled from a clock. Do not hide state a reader would
/// want in the picture. A demo that failed to compile should still say so in a
/// screenshot; how many milliseconds it took not to compile should not.
class CaptureMode extends InheritedWidget {
  const CaptureMode({super.key, required super.child});

  /// Whether this frame is going to be photographed.
  ///
  /// True for the whole life of a capture process rather than only for the
  /// instant the shutter fires. Flipping it at capture time would rebuild the
  /// tree in the moment it most needs to be still, which is the opposite of
  /// what it is for.
  static bool isCapturing(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<CaptureMode>() != null;

  @override
  bool updateShouldNotify(CaptureMode oldWidget) => false;
}
