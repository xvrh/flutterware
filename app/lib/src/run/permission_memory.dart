/// What the cockpit remembers about an app's permissions between runs.
///
/// Modelled on [FlagMemory] deliberately, and its docstring is the argument:
/// *"a launch-time flag is useless otherwise — and a forgotten one is the
/// worst debugging hour there is, so the cockpit shows which knobs are wished
/// rather than merely overridden."* Every word transfers. A profile you set
/// once should still be in force next launch, and you should be able to see
/// that it is.
///
/// **The wish is host state; the held state is the device's.** They are keyed
/// differently on purpose, and the asymmetry is worth knowing: the wish is per
/// worktree and package, while what it writes to belongs to a device and an
/// application id. Two worktrees pointed at one emulator will overwrite each
/// other's permission state — S-P5 watched exactly that happen with an APK.
/// So the cockpit says which device a state came from rather than implying it
/// belongs to the checkout.
///
/// Its own file rather than a key inside `flags.json` — the design left that
/// open, and two vocabularies in one file would make both harder to read.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'permission_write.dart';

/// One project's remembered permission wish.
class PermissionWish {
  const PermissionWish({this.profile, this.overrides = const {}});

  /// The profile id — `first-run`, `granted` — or null when only individual
  /// permissions were set.
  final String? profile;

  /// Per-capability states set on top of [profile]. "All granted except
  /// camera" is a profile plus one override, and reads as what it is.
  final Map<String, String> overrides;

  bool get isEmpty => profile == null && overrides.isEmpty;

  PermissionProfile? get resolved =>
      profile == null ? null : PermissionProfile.byId(profile!);

  Map<String, Object?> toJson() => {
    if (profile != null) 'profile': profile,
    if (overrides.isNotEmpty) 'overrides': overrides,
  };

  static PermissionWish fromJson(Map<String, Object?> json) => PermissionWish(
    profile: json['profile'] as String?,
    overrides: switch (json['overrides']) {
      Map map => {
        for (var entry in map.entries) '${entry.key}': '${entry.value}',
      },
      _ => const {},
    },
  );
}

/// The wishes this machine is holding, one file for all projects.
class PermissionMemory {
  PermissionMemory(this.runDir);

  /// Beside the run handles and `flags.json`, because it is scoped to this
  /// machine's flutterware rather than to any checkout.
  final String runDir;

  /// Keyed by worktree and package, not by entry point or device: a profile
  /// you set for the app is one you meant for the app, and `main.dart` and
  /// `main_dev.dart` are two builds of one thing.
  static String keyFor(String worktree, String package) =>
      [worktree, package].join(' ');

  File get _file => File(p.join(runDir, 'permissions.json'));

  PermissionWish read(String key) {
    var all = _readAll();
    return switch (all[key]) {
      Map map => PermissionWish.fromJson(map.cast<String, Object?>()),
      _ => const PermissionWish(),
    };
  }

  void write(String key, PermissionWish wish) {
    var all = _readAll();
    if (wish.isEmpty) {
      all.remove(key);
    } else {
      all[key] = wish.toJson();
    }
    try {
      _file.parent.createSync(recursive: true);
      _file.writeAsStringSync(jsonEncode(all));
    } on FileSystemException {
      // Best effort, like FlagMemory: a memory that cannot persist a wish
      // still applied it to the run in front of you.
    }
  }

  void clear(String key) => write(key, const PermissionWish());

  Map<String, Object?> _readAll() {
    try {
      var decoded = jsonDecode(_file.readAsStringSync());
      return decoded is Map ? decoded.cast<String, Object?>() : {};
    } on Object {
      // Absent, torn, or written by a newer shape — none of which is worth
      // failing a launch over.
      return {};
    }
  }
}
