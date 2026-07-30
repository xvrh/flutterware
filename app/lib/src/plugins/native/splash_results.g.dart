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
      'blocksGeneration': instance.blocksGeneration,
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
  'density': ?instance.density,
  'modified': instance.modified,
};
