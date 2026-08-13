/// The permissions-panel recipe, dogfooded.
///
/// This is the whole of what an app writes to get the *observed* column — the
/// third of `docs/superpowers/specs/2026-08-12-run-permissions-design.md` that
/// only the app can answer. flutterware has no permissions dependency of its
/// own; the mapping below is the adapter's entire job.
library;

import 'package:flutter/foundation.dart';
import 'package:flutterware/devbar.dart';
import 'package:permission_handler/permission_handler.dart';

/// The capability ids the cockpit's `permissions` action reports, and the
/// `permission_handler` value behind each.
///
/// Keyed by *those* ids on purpose: it is what joins this column to the
/// declared and held ones. A name nothing else knows still shows up, in a row
/// of its own.
const _permissions = <String, Permission>{
  'camera': Permission.camera,
  'location': Permission.locationWhenInUse,
  'notifications': Permission.notification,
};

PermissionAdapter buildPermissionAdapter() => PermissionAdapter(
  permissions: _permissions.keys.toList(),
  status: (name) async => _map(await _lookUp(name).status),
  request: (name) async => _map(await _lookUp(name).request()),
  openSettings: openAppSettings,
);

Permission _lookUp(String name) {
  var permission = _permissions[name];
  // Thrown rather than defaulted: the panel turns a throw into `unknown` for
  // that row and leaves the others alone, which is the honest report.
  if (permission == null) throw ArgumentError('no permission named "$name"');
  return permission;
}

/// `permission_handler`'s six states onto the five the cockpit speaks.
///
/// Four of these need a decision, and making them is the whole reason an
/// adapter is a thing the app writes rather than something flutterware
/// guesses:
///
/// - **`limited`** — iOS's "selected photos only" — is granted, because the
///   app can read something. The host side makes the same call for a TCC
///   `auth_value` of 3.
/// - **`restricted`** — parental controls, MDM — is denied rather than
///   denied-forever. The app cannot have it, but the reason is not "the user
///   refused twice", and `deniedForever` is read as exactly that everywhere
///   else in this feature.
/// - **`denied` is reported as `unknown`, deliberately.**
///   `permission_handler` has no *undetermined*: a permission nobody has ever
///   been asked for and one the user turned down both arrive as `denied`.
///   Mapping that to `denied` would make **every app in `first-run` show a
///   permanent, meaningless disagreement** with the host — and `first-run` is
///   the state this whole feature exists to make easy. `unknown` says what is
///   true: this app cannot tell those two apart. An app whose permissions
///   package *can* should map them properly and get a sharper column.
/// - **`permanentlyDenied` is `unknown` on Android and denied-forever
///   everywhere else** — the same rule as above, applied where the matrix
///   found it. Android has no *permanently denied* bit: `permission_handler`
///   derives it from `shouldShowRequestPermissionRationale`, which is false
///   **both** before the first ask and after a "don't ask again". So a
///   brand-new install reports every permission as permanently denied — the
///   matrix's `first-run` cell showed exactly that against a host reading
///   *will prompt*, in red, on all three. iOS is not like this: there the
///   status comes from a real stored answer, so it keeps its meaning.
///
///   The cost is that Android's observed column is now **granted or
///   unknown**, and that is the honest size of what this package can tell you
///   there. An app that asks the platform itself — or tracks its own first
///   ask — can do better, and this is the line it would change.
AppPermissionStatus _map(PermissionStatus status) => switch (status) {
  PermissionStatus.granted ||
  PermissionStatus.limited ||
  PermissionStatus.provisional => AppPermissionStatus.granted,
  PermissionStatus.permanentlyDenied =>
    defaultTargetPlatform == TargetPlatform.android
        ? AppPermissionStatus.unknown
        : AppPermissionStatus.deniedForever,
  PermissionStatus.restricted => AppPermissionStatus.denied,
  PermissionStatus.denied => AppPermissionStatus.unknown,
};
