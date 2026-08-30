// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'motion_results.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Map<String, dynamic> _$MotionListResultToJson(MotionListResult instance) =>
    <String, dynamic>{
      'packages': instance.packages.map((e) => e.toJson()).toList(),
    };

Map<String, dynamic> _$MotionListPackageToJson(MotionListPackage instance) =>
    <String, dynamic>{
      'path': instance.path,
      'directory': instance.directory,
      'motions': instance.motions.map((e) => e.toJson()).toList(),
      'diagnostics': instance.diagnostics,
      'error': ?instance.error,
    };

Map<String, dynamic> _$MotionListMotionToJson(MotionListMotion instance) =>
    <String, dynamic>{
      'file': instance.file,
      'line': instance.line,
      'values': ?instance.values,
      'address': ?instance.address,
      'targets': instance.targets.map((e) => e.toJson()).toList(),
    };

Map<String, dynamic> _$MotionListTargetToJson(MotionListTarget instance) =>
    <String, dynamic>{
      'name': instance.name,
      'line': instance.line,
      'properties': instance.properties,
      'boxed': instance.boxed,
    };

Map<String, dynamic> _$MotionVerifyResultToJson(MotionVerifyResult instance) =>
    <String, dynamic>{
      'motion': instance.motion,
      'file': instance.file,
      'stops': instance.stops,
      'durationMs': instance.durationMs,
      'repeats': instance.repeats,
      'orderFree': instance.orderFree,
      'differingStops': instance.differingStops,
      'scope': ?instance.scope,
      'scopes': instance.scopes,
      'ok': instance.ok,
    };
