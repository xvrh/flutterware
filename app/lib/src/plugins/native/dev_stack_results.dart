import 'package:flutterware/plugins.dart';

/// What state a [DevStack] is in.
///
/// Five, not four, and the fifth is the one a first draft leaves out.
/// [unavailable] is *the probe failed*, which is not the same fact as [down]:
/// a health check that cannot reach the docker daemon fails exactly like one
/// that finds nothing running, and reporting "down" there offers a Bring-up
/// button that cannot work. The worktree explorer draws the same distinction
/// with `FactState.unavailable`, for the same reason.
enum StackState {
  /// Nothing has looked yet. Distinct from [down] — an empty sidebar should not
  /// claim the stack is not running.
  unknown,

  down,

  /// A `start` is in flight. `docker compose up --wait` takes tens of seconds,
  /// which is why this is a state and not a spinner on a button.
  starting,

  up,

  stopping,

  /// The probe itself failed or could not be read.
  unavailable;

  static StackState byName(String? name) =>
      values.firstWhere((v) => v.name == name, orElse: () => unknown);

  bool get isMoving => this == starting || this == stopping;
}

/// One service inside a stack, when the probe says that much.
///
/// Only [Probe.json] produces these; an exit-code probe has nothing to build
/// them from and reports the stack as a whole.
class StackService {
  const StackService({required this.name, this.port, this.state});

  final String name;
  final int? port;

  /// The service's own state where the probe reports one — a compose project
  /// can be half up, and "3 of 4" is the fact that explains a slow start.
  final StackState? state;

  Map<String, Object?> toJson() => {
    'name': name,
    if (port != null) 'port': port,
    if (state != null) 'state': state!.name,
  };

  static StackService? fromJson(Map<String, Object?> json) {
    var name = json['name'];
    if (name is! String || name.isEmpty) return null;
    return StackService(
      name: name,
      port: json['port'] is int ? json['port']! as int : null,
      state: json['state'] == null
          ? null
          : StackState.byName(json['state'] as String?),
    );
  }
}

/// One run of the probe — the whole of what this plugin knows.
///
/// Carries [at] because a reading is **a fact that happened, and it gets old
/// rather than becoming wrong**. That is the same rule `RunCore`'s device cache
/// follows, and it is what lets a cold `fw status` and a freshly opened sidebar
/// say something true without spawning anything.
class StackReading implements PluginResult {
  const StackReading({
    required this.state,
    required this.at,
    this.detail,
    this.services = const [],
    this.failure,
  });

  const StackReading.unknown() : this(state: StackState.unknown, at: null);

  final StackState state;

  /// One line beside the status — `slot 8200-8208 · 4 containers`. For an
  /// exit-code probe this is the command's last non-empty output line, which
  /// is where a health check usually puts its summary.
  final String? detail;

  final List<StackService> services;

  /// Why the probe could not be believed. Only set with
  /// [StackState.unavailable].
  final String? failure;

  /// When this was read. Null only for [StackState.unknown].
  final DateTime? at;

  bool get isKnown => state != StackState.unknown;

  @override
  Map<String, Object?> toJson() => {
    'state': state.name,
    if (detail != null) 'detail': detail,
    if (services.isNotEmpty) 'services': [for (var s in services) s.toJson()],
    if (failure != null) 'failure': failure,
    if (at != null) 'checkedAt': at!.toIso8601String(),
  };

  static StackReading fromJson(Map<String, Object?> json) => StackReading(
    state: StackState.byName(json['state'] as String?),
    detail: json['detail'] as String?,
    services: [
      for (var entry in (json['services'] as List? ?? const []))
        if (entry is Map) ?StackService.fromJson(entry.cast<String, Object?>()),
    ],
    failure: json['failure'] as String?,
    at: DateTime.tryParse('${json['checkedAt']}'),
  );
}

/// `start`, `stop` and every declared command hand this back.
class DevStackRunResult implements PluginResult {
  const DevStackRunResult({
    required this.command,
    required this.exitCode,
    this.output = '',
    this.reading,
  });

  /// What was actually run, joined — so a caller that wants to do it themselves
  /// next time can, which is the point of delegating rather than supervising.
  final String command;

  final int exitCode;

  bool get ok => exitCode == 0;

  /// Combined stdout and stderr, trimmed to the tail. The full text is on
  /// screen and in the process' own log; this is what fits in a result.
  final String output;

  /// The probe run immediately afterwards, when the command was one that
  /// changes the state. A caller asking to bring the stack up wants to be told
  /// whether it came up, not merely that the command exited.
  final StackReading? reading;

  @override
  Map<String, Object?> toJson() => {
    'command': command,
    'exitCode': exitCode,
    'ok': ok,
    if (output.isNotEmpty) 'output': output,
    if (reading != null) 'reading': reading!.toJson(),
  };
}
