import 'package:json_annotation/json_annotation.dart';

part 'events.g.dart';

abstract class Event {
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
    }
    return null;
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

enum MessageLevel { info, warning, error }

@JsonSerializable(createToJson: false)
class DaemonLogMessageEvent implements Event {
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

  AppStartEvent(this.appId, this.deviceId, this.directory, this.supportsRestart,
      this.launchMode);

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
      this.appId, this.id, this.progressId, this.message, this.finished);

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
