import 'action.dart';
import 'child.dart';
import 'status_badge.dart';
import 'guard.dart';
import 'status.dart';
import 'teardown.dart';
import 'view.dart';

/// Everything a plugin says about itself right now — **all of it data**.
///
/// This is decision 2 of the overhaul plan made concrete. A native plugin draws
/// a real Flutter widget for humans, but it emits one of these too, so the
/// shell, `fw`, a file projection and an agent all read the same thing. Nothing
/// here may become a widget, a `Color`, or a closure: the moment it does, every
/// non-GUI renderer loses that capability permanently.
class PluginReport {
  const PluginReport({
    required this.id,
    required this.label,
    this.status = Status.none,
    this.badge = StatusBadge.none,
    this.actions = const [],
    this.teardown = const [],
    this.guards = const [],
    this.children = const [],
    this.view = PluginView.empty,
  });

  final String id;
  final String label;
  final Status status;
  final StatusBadge badge;
  final List<PluginAction> actions;
  final List<TeardownStep> teardown;
  final List<Guard> guards;

  /// Sub-entries — one per package for a package-scoped plugin. The sidebar
  /// collapses to [status] and expands to these.
  final List<PluginChild> children;

  /// What the panel is currently showing.
  final PluginView view;

  /// [includeActions] is off for a renderer whose caller has another way to
  /// read the declarations, and for whom carrying them is not free.
  ///
  /// **Measured, not tidied.** An action declaration is static — the same bytes
  /// every time — and it dominates a report: on flutterware's own repo the
  /// Previews report is 39k characters of JSON, 38k of it declarations. A
  /// terminal pays nothing for that, so `fw status --json` keeps them. An agent
  /// pays for every one of them in every reply, and already has a tool that
  /// serves them once.
  Map<String, Object?> toJson({bool includeActions = true}) => {
    'id': id,
    'label': label,
    'status': status.toJson(),
    if (!badge.isEmpty) 'badge': badge.toJson(),
    if (includeActions && actions.isNotEmpty)
      'actions': [for (var a in actions) a.toJson()],
    if (teardown.isNotEmpty) 'teardown': [for (var t in teardown) t.toJson()],
    if (guards.isNotEmpty) 'guards': [for (var g in guards) g.toJson()],
    if (children.isNotEmpty) 'children': [for (var c in children) c.toJson()],
    if (!view.isEmpty) 'view': view.toJson(),
  };

  /// The whole plugin as plain text — the shape `fw` prints and an agent reads.
  String toText() {
    var out = StringBuffer();
    out.write(label);
    if (!status.isEmpty) out.write('  ${status.message}');
    out.writeln();
    for (var child in children) {
      out.write('  ${child.label}');
      if (!child.status.isEmpty) out.write('  ${child.status.message}');
      out.writeln();
    }
    var body = view.toText();
    if (body.isNotEmpty) {
      for (var line in body.split('\n')) {
        out.writeln('  $line');
      }
    }
    return out.toString().trimRight();
  }

  @override
  String toString() => toText();
}
