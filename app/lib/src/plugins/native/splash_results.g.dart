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
      'device': ?instance.device,
      'fix': ?instance.fix,
      'fixLabel': ?instance.fixLabel,
      'blocksGeneration': instance.blocksGeneration,
    };

Map<String, dynamic> _$SplashFixResultToJson(SplashFixResult instance) =>
    <String, dynamic>{
      'package': instance.package,
      'flavor': ?instance.flavor,
      'fix': instance.fix,
      'label': instance.label,
      'configPath': instance.configPath,
      'writes': instance.writes.map((e) => e.toJson()).toList(),
      'remainingProblems': instance.remainingProblems,
    };

Map<String, dynamic> _$SplashSetResultToJson(SplashSetResult instance) =>
    <String, dynamic>{
      'package': instance.package,
      'flavor': ?instance.flavor,
      'key': instance.key,
      'value': ?instance.value,
      'configPath': instance.configPath,
      'remainingProblems': instance.remainingProblems,
    };

Map<String, dynamic> _$SplashPrepareResultToJson(
  SplashPrepareResult instance,
) => <String, dynamic>{
  'package': instance.package,
  'flavor': ?instance.flavor,
  'target': instance.target,
  'theme': instance.theme,
  'key': instance.key,
  'output': instance.output,
  'width': instance.width,
  'height': instance.height,
  'explanation': instance.explanation,
  'sourceCopiedTo': ?instance.sourceCopiedTo,
  'cornerOverhang': instance.cornerOverhang,
  'remainingProblems': instance.remainingProblems,
};

Map<String, dynamic> _$SplashWriteEntryToJson(SplashWriteEntry instance) =>
    <String, dynamic>{'key': instance.key, 'value': ?instance.value};

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
