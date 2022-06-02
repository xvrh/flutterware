// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'commands.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Map<String, dynamic> _$AppRestartCommandToJson(AppRestartCommand instance) =>
    <String, dynamic>{
      'appId': instance.appId,
      'fullRestart': instance.fullRestart,
      'reason': instance.reason,
      'pause': instance.pause,
      'debounce': instance.debounce,
      'methodName': instance.methodName,
    };

AppRestartResult _$AppRestartResultFromJson(Map<String, dynamic> json) =>
    AppRestartResult(
      json['code'] as int,
      json['message'] as String,
    );

Map<String, dynamic> _$AppStopCommandToJson(AppStopCommand instance) =>
    <String, dynamic>{
      'appId': instance.appId,
      'methodName': instance.methodName,
    };
