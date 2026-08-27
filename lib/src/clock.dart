/// What `clock.now()` reads wherever flutterware renders something twice —
/// **always this instant, never the wall clock**.
///
/// A preview, a scenario step and a store shot all exist to be looked at more
/// than once: beside yesterday's screenshot, on the other side of a branch, in
/// a comparison against the base. A screen showing today's date differs at
/// every one of those readings for a reason that has nothing to do with the
/// code, and then nobody can tell a real change from a re-run. Pinning is what
/// makes "these two pictures differ" mean "the code changed".
///
/// Pinned **by default**, which is the whole of the policy: a default of "now"
/// is a default of "no two runs are comparable", and every consumer that
/// noticed had to pin it again by hand — three did, at two different instants,
/// without coordinating. A project that wants another date says so once, with
/// `fw.clock(...)` in `tool/flutterware.dart`; a single run says so with
/// `--clock`, which also takes `now` for the wall clock.
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
/// intercepted by anything, in any test, so a screen that calls it is still
/// unpinned and there is nothing this or any other library can do about it.
final pinnedClockOrigin = DateTime(2026, 1, 1, 9, 41);
