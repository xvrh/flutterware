import 'package:json_annotation/json_annotation.dart';

import 'device.dart';

part 'commands.g.dart';

abstract class Command<TResult> {
  String get methodName;
  TResult decodeResult(covariant Object? result);
  Map<String, dynamic> toJson();
}

@JsonSerializable(createFactory: false)
class AppRestartCommand implements Command<AppRestartResult> {
  final String appId;
  final bool? fullRestart;
  final String? reason;
  final bool? pause;
  final bool? debounce;

  AppRestartCommand({
    required this.appId,
    this.fullRestart,
    this.reason,
    this.pause,
    this.debounce,
  });

  @override
  Map<String, dynamic> toJson() => _$AppRestartCommandToJson(this);

  @override
  String get methodName => 'app.restart';

  @override
  AppRestartResult decodeResult(Map<String, dynamic> result) =>
      AppRestartResult.fromJson(result);
}

@JsonSerializable(createToJson: false)
class AppRestartResult {
  final int code;
  final String message;

  AppRestartResult(this.code, this.message);

  factory AppRestartResult.fromJson(Map<String, dynamic> json) =>
      _$AppRestartResultFromJson(json);
}

@JsonSerializable(createFactory: false)
class AppStopCommand implements Command<bool> {
  final String appId;

  AppStopCommand({required this.appId});

  @override
  Map<String, dynamic> toJson() => _$AppStopCommandToJson(this);

  @override
  String get methodName => 'app.stop';

  @override
  bool decodeResult(bool result) => result;
}

/// Everything the daemon's discoverers can see right now.
///
/// Answers from the discoverers' cache, so it is fast but only as fresh as the
/// last poll. [DeviceEnableCommand] is what makes the daemon keep polling and
/// report `device.added` / `device.removed` as hardware comes and goes.
class DeviceGetDevicesCommand implements Command<List<DaemonDevice>> {
  const DeviceGetDevicesCommand();

  @override
  String get methodName => 'device.getDevices';

  @override
  Map<String, dynamic> toJson() => const {};

  @override
  List<DaemonDevice> decodeResult(Object? result) => [
    for (var entry in (result as List? ?? const []))
      if (entry is Map) ?DaemonDevice.tryRead(entry.cast<String, Object?>()),
  ];
}

/// Starts device polling and the `device.added` / `device.removed` events.
///
/// The daemon discovers nothing until asked: a `flutter daemon` that is never
/// enabled reports an empty device list forever, which reads exactly like a
/// machine with nothing plugged in.
class DeviceEnableCommand implements Command<void> {
  const DeviceEnableCommand();

  @override
  String get methodName => 'device.enable';

  @override
  Map<String, dynamic> toJson() => const {};

  @override
  void decodeResult(Object? result) {}
}
