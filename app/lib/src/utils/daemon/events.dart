import 'package:json_annotation/json_annotation.dart';

import 'device.dart';

part 'events.g.dart';

sealed class Event {
  static Event? decode(String event, Map<String, dynamic> params) {
    switch (event) {
      case 'daemon.connected':
        return DaemonConnectedEvent.fromJson(params);
      case 'daemon.log':
        return DaemonLogEvent.fromJson(params);
      case 'daemon.logMessage':
        return DaemonLogMessageEvent.fromJson(params);
      case 'app.start':
        return AppStartEvent.fromJson(params);
      case 'app.debugPort':
        return AppDebugPortEvent.fromJson(params);
      case 'app.started':
        return AppStartedEvent.fromJson(params);
      case 'app.progress':
        return AppProgressEvent.fromJson(params);
      case 'device.added':
        return DeviceAddedEvent.tryRead(params);
      case 'device.removed':
        return DeviceRemovedEvent.tryRead(params);
    }
    return null;
  }
}

/// A device appeared — plugged in, booted, or found on the network.
///
/// The event's params *are* the device map, not a wrapper around one.
class DeviceAddedEvent implements Event {
  DeviceAddedEvent(this.device);

  final DaemonDevice device;

  /// Null for a device map with no id, which is nothing we can act on. An
  /// unreadable event is dropped rather than raised: the next `getDevices`
  /// is the authority anyway.
  static DeviceAddedEvent? tryRead(Map<String, dynamic> json) {
    var device = DaemonDevice.tryRead(json);
    return device == null ? null : DeviceAddedEvent(device);
  }
}

/// A device went away — unplugged, shut down, or off the network.
class DeviceRemovedEvent implements Event {
  DeviceRemovedEvent(this.device);

  final DaemonDevice device;

  static DeviceRemovedEvent? tryRead(Map<String, dynamic> json) {
    var device = DaemonDevice.tryRead(json);
    return device == null ? null : DeviceRemovedEvent(device);
  }
}

@JsonSerializable(createToJson: false)
class DaemonConnectedEvent implements Event {
  final String version;
  final int pid;

  DaemonConnectedEvent(this.version, this.pid);

  factory DaemonConnectedEvent.fromJson(Map<String, dynamic> json) =>
      _$DaemonConnectedEventFromJson(json);
}

@JsonSerializable(createToJson: false)
class DaemonLogEvent implements Event {
  final String log;
  final bool error;

  DaemonLogEvent(this.log, {bool? error}) : error = error ?? false;

  factory DaemonLogEvent.fromJson(Map<String, dynamic> json) =>
      _$DaemonLogEventFromJson(json);
}

/// What the daemon's own logger tags a line with.
///
/// The full set the tool actually sends is `trace`, `status`, `warning` and
/// `error` — see `NotifyingLogger` in `commands/daemon.dart`. `info` is here
/// only because this enum was written before anyone read that list; nothing
/// emits it, and removing it would be a breaking change for no gain.
///
/// It used to stop at `info, warning, error`, and the first `status` line the
/// device daemon sent threw out of `Event.decode` and killed the whole
/// protocol subscription.
enum MessageLevel { trace, status, info, warning, error }

@JsonSerializable(createToJson: false)
class DaemonLogMessageEvent implements Event {
  /// A level this build has never heard of reads as [MessageLevel.status] —
  /// the tool's own "ordinary progress" — rather than failing the decode.
  @JsonKey(unknownEnumValue: MessageLevel.status)
  final MessageLevel level;

  final String message;
  final String? stackTrace;

  DaemonLogMessageEvent(this.level, this.message, this.stackTrace);

  factory DaemonLogMessageEvent.fromJson(Map<String, dynamic> json) =>
      _$DaemonLogMessageEventFromJson(json);
}

@JsonSerializable(createToJson: false)
class AppStartEvent implements Event {
  final String appId;
  final String deviceId;
  final String directory;
  final bool supportsRestart;
  final String launchMode;

  AppStartEvent(
    this.appId,
    this.deviceId,
    this.directory,
    this.supportsRestart,
    this.launchMode,
  );

  factory AppStartEvent.fromJson(Map<String, dynamic> json) =>
      _$AppStartEventFromJson(json);
}

@JsonSerializable(createToJson: false)
class AppDebugPortEvent implements Event {
  final String appId;
  final int port;
  final Uri wsUri;
  final Uri baseUri;

  AppDebugPortEvent(this.appId, this.port, this.wsUri, this.baseUri);

  factory AppDebugPortEvent.fromJson(Map<String, dynamic> json) =>
      _$AppDebugPortEventFromJson(json);
}

@JsonSerializable(createToJson: false)
class AppProgressEvent implements Event {
  final String appId;
  final String id;
  final String? progressId;
  final String? message;
  final bool finished;

  AppProgressEvent(
    this.appId,
    this.id,
    this.progressId,
    this.message,
    this.finished,
  );

  factory AppProgressEvent.fromJson(Map<String, dynamic> json) =>
      _$AppProgressEventFromJson(json);
}

@JsonSerializable(createToJson: false)
class AppStartedEvent implements Event {
  final String appId;

  AppStartedEvent(this.appId);

  factory AppStartedEvent.fromJson(Map<String, dynamic> json) =>
      _$AppStartedEventFromJson(json);
}
