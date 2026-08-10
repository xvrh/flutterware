import 'package:clock/clock.dart';

/// What `clock.now()` reads inside a preview: **always this instant, never the
/// wall clock**.
///
/// A preview exists to be looked at twice — beside yesterday's screenshot, on
/// the other side of a branch, in a comparison against the base — and a screen
/// showing today's date differs every one of those times for a reason that has
/// nothing to do with the code. Pinning it is what makes "these two pictures
/// differ" mean "somebody changed something".
///
/// Constructed **local**, so every machine renders the same wall clock —
/// 9:41 on the first of the month, the hour a screenshot has been taken at
/// since the first iPhone keynote. Two machines in different zones therefore
/// pin different *instants*, which is the right trade: shots are compared
/// against other shots from the same machine, and what a human reads off the
/// picture should be the same everywhere.
///
/// Reaches code that reads `package:clock` — the ecosystem's convention, and
/// what `flutter_test` itself uses. A direct `DateTime.now()` cannot be
/// intercepted by anything, in any test, so a preview that calls it is still
/// unpinned and there is nothing this or any other library can do about it.
final previewClockOrigin = DateTime(2026, 1, 1, 9, 41);

/// Runs [body] with the preview clock pinned.
///
/// **Must wrap the whole of the guest's `main`, binding included.**
/// `PlatformDispatcher.onBeginFrame` captures `Zone.current` when it is *set*,
/// and the binding sets it in `initInstances` — so a zone entered after
/// `ensureInitialized` would leave every build, layout and paint callback
/// running in the zone that came before it, which is exactly where a demo
/// reads the clock.
T withPreviewClock<T>(T Function() body) =>
    withClock(Clock.fixed(previewClockOrigin), body);
