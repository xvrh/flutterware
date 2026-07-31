// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'scenarios_results.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Map<String, dynamic> _$ScenarioListResultToJson(ScenarioListResult instance) =>
    <String, dynamic>{
      'packages': instance.packages.map((e) => e.toJson()).toList(),
    };

Map<String, dynamic> _$ScenarioListPackageToJson(
  ScenarioListPackage instance,
) => <String, dynamic>{
  'path': instance.path,
  'directory': instance.directory,
  'scenarios': instance.scenarios.map((e) => e.toJson()).toList(),
  'diagnostics': instance.diagnostics,
  'error': ?instance.error,
  'authoring': ?instance.authoring,
};

Map<String, dynamic> _$ScenarioListEntryToJson(ScenarioListEntry instance) =>
    <String, dynamic>{
      'name': instance.name,
      'file': instance.file,
      'line': instance.line,
    };

Map<String, dynamic> _$ScenarioRunResultToJson(ScenarioRunResult instance) =>
    <String, dynamic>{
      'packages': instance.packages.map((e) => e.toJson()).toList(),
      'ok': instance.ok,
      'axes': ?instance.axes,
    };

Map<String, dynamic> _$ScenarioRunPackageToJson(ScenarioRunPackage instance) =>
    <String, dynamic>{
      'path': instance.path,
      'output': instance.output,
      'ms': instance.ms,
      'scenarios': instance.scenarios.map((e) => e.toJson()).toList(),
      'error': ?instance.error,
    };

Map<String, dynamic> _$ScenarioRunOutcomeToJson(ScenarioRunOutcome instance) =>
    <String, dynamic>{
      'file': instance.file,
      'name': instance.name,
      'ok': instance.ok,
      'ms': instance.ms,
      'steps': instance.steps.map((e) => e.toJson()).toList(),
      'errors': instance.errors.map((e) => e.toJson()).toList(),
    };

Map<String, dynamic> _$ScenarioRunStepToJson(ScenarioRunStep instance) =>
    <String, dynamic>{
      'index': instance.index,
      'parent': ?instance.parent,
      'branch': ?instance.branch,
      'name': ?instance.name,
      'auto': instance.auto,
      'tags': instance.tags,
      'image': instance.image,
      'format': instance.format,
      'width': instance.width,
      'height': instance.height,
      'tree': instance.tree,
      'texts': instance.texts,
      'address': instance.address,
      'statusBrightness': ?instance.statusBrightness,
      'navBrightness': ?instance.navBrightness,
    };

Map<String, dynamic> _$ScenarioRunErrorToJson(ScenarioRunError instance) =>
    <String, dynamic>{'error': instance.error, 'stack': ?instance.stack};

Map<String, dynamic> _$ScenarioNewResultToJson(ScenarioNewResult instance) =>
    <String, dynamic>{
      'package': instance.package,
      'file': instance.file,
      'name': instance.name,
      'next': instance.next,
    };

Map<String, dynamic> _$ScenarioRestartResultToJson(
  ScenarioRestartResult instance,
) => <String, dynamic>{'restarted': instance.restarted};
