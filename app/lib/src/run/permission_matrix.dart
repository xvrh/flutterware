/// The matrix: the same app, the same screen, once per permission profile.
///
/// "Great for testing all configurations" is one sentence with one honest cost
/// in it — **each cell is a relaunch.** Permission state is read at process
/// start, and on Android a revoke kills the app anyway (measured, S-P1), so
/// there is no cheaper way to see what a denied camera does to the first
/// screen. The sequencing lives in the run core, where the launching and the
/// shelling out are; this file holds the parts that are decisions rather than
/// I/O, so they can be tested with no device and no build.
///
/// Two of those decisions are worth naming:
///
/// - **An unknown profile name is refused, not skipped.** A matrix that
///   quietly ran three of the four cells you asked for would be a report with
///   a hole in it, and the hole would be invisible in the grid.
/// - **The comparison is against the first cell.** A grid of four screenshots
///   is only useful if somebody can see what differs, and the differences are
///   nearly always a handful of strings — an error, a disabled button's label,
///   a prompt that did not appear. Reported as text so an agent gets them for
///   free, next to the picture a human reads.
library;

import 'permission_write.dart';

/// What a matrix runs when nobody narrows it: every profile there is.
///
/// All four rather than a chosen three. `denied` and `denied-forever` look the
/// same until an app calls `request()` — one prompts and one cannot — and
/// which of those an app handles badly is exactly the thing a matrix is for.
/// A caller in a hurry names the two they want.
List<PermissionProfile> get defaultMatrixProfiles => PermissionProfile.values;

/// Reads the `profiles` argument: a comma-separated string, a list, or nothing.
///
/// Duplicates collapse and the caller's order is kept — `granted,first-run`
/// runs granted first, because somebody who wrote it that way is comparing in
/// that direction.
({List<PermissionProfile> profiles, String? error}) parseMatrixProfiles(
  Object? raw,
) {
  var declared = [for (var profile in PermissionProfile.values) profile.id];
  var names = switch (raw) {
    null => const <String>[],
    String text => [
      for (var part in text.split(','))
        if (part.trim().isNotEmpty) part.trim(),
    ],
    Iterable<Object?> items => [
      for (var item in items)
        if ('$item'.trim().isNotEmpty) '$item'.trim(),
    ],
    _ => ['$raw'],
  };
  if (names.isEmpty) return (profiles: defaultMatrixProfiles, error: null);

  var profiles = <PermissionProfile>[];
  for (var name in names) {
    var profile = PermissionProfile.byId(name);
    if (profile == null) {
      return (
        profiles: const [],
        error:
            'No profile "$name". Declared: ${declared.join(', ')}. Omit '
            'profiles to run all of them.',
      );
    }
    if (!profiles.contains(profile)) profiles.add(profile);
  }
  return (profiles: profiles, error: null);
}

/// Texts on [cell]'s screen that were not on [baseline]'s, in [cell]'s order.
///
/// Null on either side means there is nothing to compare — a cell whose launch
/// failed has no screen, and inventing a difference for it would be worse than
/// saying nothing.
List<String> textsAdded(List<String>? baseline, List<String>? cell) {
  if (baseline == null || cell == null) return const [];
  var was = baseline.toSet();
  var added = <String>[];
  for (var text in cell) {
    if (was.contains(text) || added.contains(text)) continue;
    added.add(text);
  }
  return added;
}

/// True when every cell that produced a screen produced the *same* screen.
///
/// A note rather than a verdict, and the note says both readings out loud:
/// either the app does not consult these permissions on the screen that was
/// photographed, or it has not asked for them yet. Needs two screens — one
/// cell agrees with itself and that is not a finding.
bool identicalScreens(Iterable<List<String>?> screens) {
  List<String>? first;
  var seen = 0;
  for (var screen in screens) {
    if (screen == null) continue;
    seen++;
    if (first == null) {
      first = screen;
      continue;
    }
    if (first.length != screen.length) return false;
    for (var i = 0; i < screen.length; i++) {
      if (first[i] != screen[i]) return false;
    }
  }
  return seen >= 2;
}

/// The sentence [identicalScreens] earns, or null when the cells differed.
String? sameScreenNote(Iterable<List<String>?> screens) =>
    identicalScreens(screens)
    ? 'Every profile produced the same visible screen. Either this screen '
          'does not consult these permissions, or the app has not asked for '
          'them yet — drive it to the screen that does and run the matrix '
          'again with a route.'
    : null;
