import 'package:collection/collection.dart';
import 'package:flutterware/plugins.dart';

const _deep = DeepCollectionEquality();

/// What moved between two runs of `tool/flutterware.dart`.
///
/// **This is the whole judgement in a config reload.** Everything downstream is
/// mechanical: an affected plugin is disposed and rebuilt, an unaffected one is
/// left alone. Too coarse an answer here and a plugin keeps running behaviour
/// the file no longer describes; too fine and every save tears down a guest
/// engine. See `2026-07-29-config-reload-findings.md`.
///
/// **Re-running the config is the comparison.** There is no source parsing and
/// no hashing of the compiled kernel — the config is re-run on every change
/// regardless, so comparing what it printed is both cheaper and exact. A
/// comment or a reformat produces an identical manifest and therefore an empty
/// diff, not because anything detected the comment but because nothing about
/// the declarations moved.
class ManifestDiff {
  const ManifestDiff({
    required this.packagesChanged,
    required this.orderChanged,
    required this.added,
    required this.removed,
    required this.changed,
  });

  /// The project's `packages:` list moved.
  ///
  /// **Deliberately blunt: this rebuilds everything.** `Workspace` interns a
  /// `PackageRef` per path so callers can compare identity, and every
  /// `PluginHost` holds the workspace — so a new workspace makes every core's
  /// host stale and there is nothing left to reuse. Do not try to narrow this
  /// without reading `Workspace` first.
  final bool packagesChanged;

  /// The same plugins, declared in a different order.
  ///
  /// Separate from [affected] because it rebuilds *nothing* — the sidebar order
  /// follows the new manifest and every core survives. Collapsing the two would
  /// make a reorder either invisible or expensive.
  final bool orderChanged;

  /// Ids present only in the new manifest.
  final List<String> added;

  /// Ids present only in the old one.
  final List<String> removed;

  /// Ids whose declaration moved, each with the config keys that differ —
  /// sorted, and including `label` when the label itself moved.
  final Map<String, List<String>> changed;

  /// Ids that have to be disposed or built. Excludes [orderChanged], which
  /// costs nothing, and [packagesChanged], which costs everything.
  List<String> get affected => [...added, ...removed, ...changed.keys];

  /// Nothing differs at all, order included — so a reload does nothing.
  bool get isEmpty =>
      !packagesChanged &&
      !orderChanged &&
      added.isEmpty &&
      removed.isEmpty &&
      changed.isEmpty;

  bool get needsFullRebuild => packagesChanged;

  /// Why [id] is being rebuilt, phrased for a log row, or null when it is not.
  String? reasonFor(String id) {
    if (added.contains(id)) return 'newly declared';
    if (removed.contains(id)) return 'no longer declared';
    if (changed[id] case var keys?) return '${keys.join(', ')} changed';
    return null;
  }

  static ManifestDiff between(PluginManifest before, PluginManifest after) {
    var old = _byId(before);
    var now = _byId(after);

    var changed = <String, List<String>>{};
    for (var id in now.keys) {
      if (old[id] case var was?) {
        var keys = _changedKeys(was, now[id]!);
        if (keys.isNotEmpty) changed[id] = keys;
      }
    }

    var added = [
      for (var id in now.keys)
        if (!old.containsKey(id)) id,
    ];
    var removed = [
      for (var id in old.keys)
        if (!now.containsKey(id)) id,
    ];

    // Only meaningful when the sets match: otherwise the order "changed"
    // because something arrived or left, which is already reported.
    var orderChanged =
        added.isEmpty &&
        removed.isEmpty &&
        !const ListEquality<String>().equals(
          old.keys.toList(),
          now.keys.toList(),
        );

    return ManifestDiff(
      packagesChanged: !_deep.equals(
        [for (var pkg in before.packages) pkg.toJson()],
        [for (var pkg in after.packages) pkg.toJson()],
      ),
      orderChanged: orderChanged,
      added: added,
      removed: removed,
      changed: changed,
    );
  }

  /// Declarations keyed by id, in declared order.
  ///
  /// Ids are unique by construction — `FlutterwareConfig.use` refuses a
  /// duplicate — so a duplicate here means the manifest did not come from
  /// `Flutterware.configure` and silently keeping the last one would resolve
  /// one plugin and drop another without saying so.
  static Map<String, PluginDeclaration> _byId(PluginManifest manifest) {
    var byId = <String, PluginDeclaration>{};
    for (var declaration in manifest.plugins) {
      if (byId.containsKey(declaration.id)) {
        throw ArgumentError.value(
          declaration.id,
          'manifest',
          'declared twice; ids must be unique',
        );
      }
      byId[declaration.id] = declaration;
    }
    return byId;
  }

  /// The config keys that differ, plus `label` when it moved.
  ///
  /// Named by *top-level* key even when the change is nested — `packages`
  /// rather than `packages[1].path`. A log row wants to say which part of the
  /// declaration moved, and a plugin is rebuilt whole either way, so a deeper
  /// path would be precision nobody spends.
  static List<String> _changedKeys(PluginDeclaration a, PluginDeclaration b) {
    var keys = <String>{};
    if (a.label != b.label) keys.add('label');
    for (var key in {...a.config.keys, ...b.config.keys}) {
      if (!_deep.equals(a.config[key], b.config[key])) keys.add(key);
    }
    return keys.toList()..sort();
  }
}
