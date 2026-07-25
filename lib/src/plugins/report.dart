import 'action.dart';
import 'badge.dart';
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
    this.badge = Badge.none,
    this.actions = const [],
    this.teardown = const [],
    this.guards = const [],
    this.view = PluginView.empty,
  });

  final String id;
  final String label;
  final Status status;
  final Badge badge;
  final List<PluginAction> actions;
  final List<TeardownStep> teardown;
  final List<Guard> guards;

  /// What the panel is currently showing.
  final PluginView view;

  Map<String, Object?> toJson() => {
    'id': id,
    'label': label,
    'status': status.toJson(),
    if (!badge.isEmpty) 'badge': badge.toJson(),
    if (actions.isNotEmpty) 'actions': [for (var a in actions) a.toJson()],
    if (teardown.isNotEmpty) 'teardown': [for (var t in teardown) t.toJson()],
    if (guards.isNotEmpty) 'guards': [for (var g in guards) g.toJson()],
    if (!view.isEmpty) 'view': view.toJson(),
  };

  /// The whole plugin as plain text — the shape `fw` prints and an agent reads.
  String toText() {
    var out = StringBuffer();
    out.write(label);
    if (!status.isEmpty) out.write('  ${status.message}');
    out.writeln();
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
