import 'status.dart';
import 'status_badge.dart';

/// A sub-entry of a plugin — in practice, one of its packages.
///
/// A plugin with several packages has no single honest status: summing
/// "direct dependencies" across packages double-counts everything shared, and
/// "3 failing" without saying *where* is a dead end in a large repo. Children
/// let the sidebar collapse to a summary and expand to the breakdown, and
/// because they are data the CLI and an agent get the same breakdown.
///
/// Selecting a child is what raises that package's work — children and
/// laziness are the same mechanism seen from two sides.
class PluginChild {
  const PluginChild({
    required this.id,
    required this.label,
    this.status = Status.none,
    this.badge = StatusBadge.none,
  });

  /// Stable within the plugin — the package path, for package-scoped plugins.
  final String id;

  final String label;
  final Status status;
  final StatusBadge badge;

  Map<String, Object?> toJson() => {
    'id': id,
    'label': label,
    'status': status.toJson(),
    if (!badge.isEmpty) 'badge': badge.toJson(),
  };

  static PluginChild fromJson(Map<String, Object?> json) => PluginChild(
    id: json['id']! as String,
    label: json['label']! as String,
    status: Status.fromJson((json['status']! as Map).cast<String, Object?>()),
    badge: json['badge'] == null
        ? StatusBadge.none
        : StatusBadge.fromJson((json['badge']! as Map).cast<String, Object?>()),
  );
}
