import 'package:clock/clock.dart';

import '../clock.dart';

export '../clock.dart' show pinnedClockOrigin;

/// Runs [body] with the preview clock pinned to [pinnedClockOrigin].
///
/// Must wrap the whole of the guest's `main`, binding included.
/// `PlatformDispatcher.onBeginFrame` captures `Zone.current` when it is *set*,
/// and the binding sets it in `initInstances` — so a zone entered after
/// `ensureInitialized` would leave every build, layout and paint callback
/// running in the zone that came before it, which is exactly where a demo
/// reads the clock.
T withPreviewClock<T>(T Function() body) =>
    withClock(Clock.fixed(pinnedClockOrigin), body);
