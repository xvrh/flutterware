// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'events.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

DaemonConnectedEvent _$DaemonConnectedEventFromJson(
        Map<String, dynamic> json) =>
    DaemonConnectedEvent(
      json['version'] as String,
      json['pid'] as int,
    );

DaemonLogEvent _$DaemonLogEventFromJson(Map<String, dynamic> json) =>
    DaemonLogEvent(
      json['log'] as String,
      error: json['error'] as bool?,
    );

DaemonLogMessageEvent _$DaemonLogMessageEventFromJson(
        Map<String, dynamic> json) =>
    DaemonLogMessageEvent(
      $enumDecode(_$MessageLevelEnumMap, json['level']),
      json['message'] as String,
      json['stackTrace'] as String?,
    );

const _$MessageLevelEnumMap = {
  MessageLevel.info: 'info',
  MessageLevel.warning: 'warning',
  MessageLevel.error: 'error',
};

AppStartEvent _$AppStartEventFromJson(Map<String, dynamic> json) =>
    AppStartEvent(
      json['appId'] as String,
      json['deviceId'] as String,
      json['directory'] as String,
      json['supportsRestart'] as bool,
      json['launchMode'] as String,
    );

AppDebugPortEvent _$AppDebugPortEventFromJson(Map<String, dynamic> json) =>
    AppDebugPortEvent(
      json['appId'] as String,
      json['port'] as int,
      Uri.parse(json['wsUri'] as String),
      Uri.parse(json['baseUri'] as String),
    );

AppProgressEvent _$AppProgressEventFromJson(Map<String, dynamic> json) =>
    AppProgressEvent(
      json['appId'] as String,
      json['id'] as String,
      json['progressId'] as String?,
      json['message'] as String,
      json['finished'] as bool,
    );

AppStartedEvent _$AppStartedEventFromJson(Map<String, dynamic> json) =>
    AppStartedEvent(
      json['appId'] as String,
    );
