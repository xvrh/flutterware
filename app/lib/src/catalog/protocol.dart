import 'dart:convert';

import 'package:json_annotation/json_annotation.dart';

import 'catalog_entry.dart';

part 'protocol.g.dart';

/// The wire format between the GUI and the compiler daemon.
///
/// Line-delimited JSON over the daemon's stdio: stdout carries the protocol and
/// nothing else, and the daemon's own logging goes to stderr.
///
/// Every message is a typed class with a generated codec — the discriminator is
/// read once, in [DaemonRequest.decode] / [DaemonResponse.decode], and nothing
/// downstream touches a raw map.

/// Anything that can go on the wire as one line.
abstract interface class ProtocolMessage {
  /// The discriminator [DaemonRequest.decode] and [DaemonResponse.decode]
  /// dispatch on.
  String get type;

  Map<String, dynamic> toJson();
}

/// Milliseconds on the wire, a [Duration] in Dart.
class _DurationMillis implements JsonConverter<Duration, int> {
  const _DurationMillis();

  @override
  Duration fromJson(int json) => Duration(milliseconds: json);

  @override
  int toJson(Duration object) => object.inMilliseconds;
}

const _millis = _DurationMillis();

/// GUI → daemon.
sealed class DaemonRequest implements ProtocolMessage {
  const DaemonRequest();

  static DaemonRequest decode(Map<String, dynamic> json) =>
      switch (json['type']) {
        SelectRequest.wireName => SelectRequest.fromJson(json),
        ShutdownRequest.wireName => const ShutdownRequest(),
        var unknown => throw FormatException('unknown request "$unknown"'),
      };
}

/// Make [id] the active entry and compile it into the entrypoint.
@JsonSerializable()
class SelectRequest extends DaemonRequest {
  const SelectRequest(this.id);

  factory SelectRequest.fromJson(Map<String, dynamic> json) =>
      _$SelectRequestFromJson(json);

  static const wireName = 'select';

  /// A [CatalogEntry.id].
  final String id;

  @override
  String get type => wireName;

  @override
  Map<String, dynamic> toJson() => _$SelectRequestToJson(this);
}

class ShutdownRequest extends DaemonRequest {
  const ShutdownRequest();

  static const wireName = 'shutdown';

  @override
  String get type => wireName;

  @override
  Map<String, dynamic> toJson() => const {};
}

/// daemon → GUI.
sealed class DaemonResponse implements ProtocolMessage {
  const DaemonResponse();

  static DaemonResponse decode(Map<String, dynamic> json) =>
      switch (json['type']) {
        DaemonReady.wireName => DaemonReady.fromJson(json),
        DaemonCompiled.wireName => DaemonCompiled.fromJson(json),
        DaemonFailed.wireName => DaemonFailed.fromJson(json),
        var unknown => throw FormatException('unknown response "$unknown"'),
      };
}

/// The daemon finished the slow one-time work; the guest can be launched.
@JsonSerializable(explicitToJson: true)
class DaemonReady extends DaemonResponse {
  const DaemonReady({
    required this.hostPath,
    required this.assetsDir,
    required this.icuData,
    required this.coldCompile,
    required this.entries,
    this.diagnostics = const [],
  });

  factory DaemonReady.fromJson(Map<String, dynamic> json) =>
      _$DaemonReadyFromJson(json);

  static const wireName = 'ready';

  final String hostPath;
  final String assetsDir;
  final String icuData;

  @_millis
  final Duration coldCompile;

  /// Everything discovery found, in tree order. The daemon owns the scan so
  /// the GUI and the CLI read one list rather than each building their own.
  final List<CatalogEntry> entries;

  /// What the scan noticed but did not act on. Errors never reach here — the
  /// daemon refuses to start on those.
  final List<String> diagnostics;

  @override
  String get type => wireName;

  @override
  Map<String, dynamic> toJson() => _$DaemonReadyToJson(this);
}

/// The result of compiling one entry into the accumulating entrypoint.
@JsonSerializable()
class DaemonCompiled extends DaemonResponse {
  const DaemonCompiled({
    required this.id,
    required this.compile,
    required this.newSourceCount,
    this.dill,
    this.error,
  });

  factory DaemonCompiled.fromJson(Map<String, dynamic> json) =>
      _$DaemonCompiledFromJson(json);

  static const wireName = 'compiled';

  final String id;

  /// The kernel to hand the VM service as `rootLibUri`. Null when [ok] is
  /// false — the guest keeps rendering whatever it had.
  final String? dill;

  @_millis
  final Duration compile;

  /// How many libraries this compile added; ~0 when revisiting an entry the
  /// compiler has already seen.
  final int newSourceCount;

  /// Compiler diagnostics when the entry did not build.
  final String? error;

  bool get ok => error == null && dill != null;

  @override
  String get type => wireName;

  @override
  Map<String, dynamic> toJson() => _$DaemonCompiledToJson(this);
}

/// The daemon could not start. Terminal: it exits after sending this.
@JsonSerializable()
class DaemonFailed extends DaemonResponse {
  const DaemonFailed({required this.message, this.stackTrace});

  factory DaemonFailed.fromJson(Map<String, dynamic> json) =>
      _$DaemonFailedFromJson(json);

  static const wireName = 'failed';

  final String message;
  final String? stackTrace;

  @override
  String get type => wireName;

  @override
  Map<String, dynamic> toJson() => _$DaemonFailedToJson(this);

  @override
  String toString() => stackTrace == null ? message : '$message\n$stackTrace';
}

/// What the daemon needs to start, handed over as a file rather than argv so
/// the entry list has somewhere to live.
@JsonSerializable(explicitToJson: true)
class DaemonConfig {
  const DaemonConfig({
    required this.appPackageRoot,
    required this.projectRoot,
    required this.packageConfig,
    this.roots = const ['demo'],
    this.previewAnnotations = const ['Preview', 'Demo'],
    this.emitProbe = false,
  });

  factory DaemonConfig.fromJson(Map<String, dynamic> json) =>
      _$DaemonConfigFromJson(json);

  final String appPackageRoot;
  final String projectRoot;
  final String packageConfig;

  /// Directories to scan for entries, relative to [projectRoot].
  final List<String> roots;

  /// Annotation names that mark an entry. Recognition is by registration.
  final List<String> previewAnnotations;

  /// Makes the generated guest print a periodic `FW-PROBE:` line naming the
  /// live entry and the text it renders. Used by the headless check.
  final bool emitProbe;

  Map<String, dynamic> toJson() => _$DaemonConfigToJson(this);
}

/// Encodes one message as a protocol line, discriminator included.
String encodeLine(ProtocolMessage message) =>
    jsonEncode({'type': message.type, ...message.toJson()});

/// Decodes a protocol line, or null when it is not JSON at all — a daemon that
/// prints something unexpected should not take the session down with it.
Map<String, dynamic>? tryDecodeLine(String line) {
  if (line.trim().isEmpty) return null;
  try {
    var decoded = jsonDecode(line);
    return decoded is Map<String, dynamic> ? decoded : null;
  } on FormatException {
    return null;
  }
}
