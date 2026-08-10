// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'splash_results.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Map<String, dynamic> _$SplashDescribeResultToJson(
  SplashDescribeResult instance,
) => <String, dynamic>{
  'package': instance.package,
  'address': instance.address,
  'surface': instance.surface,
  'theme': instance.theme,
  'configPath': instance.configPath,
  'configKind': instance.configKind,
  'flavor': ?instance.flavor,
  'enabled': instance.enabled,
  'placement': instance.placement,
  'generated': instance.generated,
  'predictedBecause': ?instance.predictedBecause,
  'properties': instance.properties.map((e) => e.toJson()).toList(),
  'fallsBackToLight': instance.fallsBackToLight,
  'problems': instance.problems.map((e) => e.toJson()).toList(),
};

Map<String, dynamic> _$SplashPropertyToJson(SplashProperty instance) =>
    <String, dynamic>{
      'name': instance.name,
      'value': instance.value,
      'from': ?instance.from,
    };

Map<String, dynamic> _$SplashProblemEntryToJson(SplashProblemEntry instance) =>
    <String, dynamic>{
      'tone': instance.tone,
      'message': instance.message,
      'key': ?instance.key,
      'surface': ?instance.surface,
      'theme': ?instance.theme,
      'device': ?instance.device,
      'blocksGeneration': instance.blocksGeneration,
    };

Map<String, dynamic> _$SplashReloadResultToJson(SplashReloadResult instance) =>
    <String, dynamic>{
      'package': instance.package,
      'configPath': ?instance.configPath,
      'scannedAt': instance.scannedAt,
      'changed': instance.changed,
    };

Map<String, dynamic> _$SplashGenerateResultToJson(
  SplashGenerateResult instance,
) => <String, dynamic>{
  'package': instance.package,
  'flavor': ?instance.flavor,
  'ok': instance.ok,
  'exitCode': instance.exitCode,
  'output': instance.output,
  'artifacts': instance.artifacts.map((e) => e.toJson()).toList(),
};

Map<String, dynamic> _$SplashArtifactsResultToJson(
  SplashArtifactsResult instance,
) => <String, dynamic>{
  'package': instance.package,
  'flavor': ?instance.flavor,
  'generated': instance.generated,
  'stale': instance.stale,
  'artifacts': instance.artifacts.map((e) => e.toJson()).toList(),
};

Map<String, dynamic> _$SplashArtifactEntryToJson(
  SplashArtifactEntry instance,
) => <String, dynamic>{
  'path': instance.path,
  'surface': instance.surface,
  'theme': instance.theme,
  'role': instance.role,
  'density': ?instance.density,
  'pixelWidth': ?instance.pixelWidth,
  'pixelHeight': ?instance.pixelHeight,
  'logicalWidth': ?instance.logicalWidth,
  'modified': instance.modified,
};
