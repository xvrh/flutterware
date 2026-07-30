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
      'name': ?instance.name,
      'auto': instance.auto,
      'tags': instance.tags,
      'png': instance.png,
      'tree': instance.tree,
      'texts': instance.texts,
      'address': instance.address,
    };

Map<String, dynamic> _$ScenarioRunErrorToJson(ScenarioRunError instance) =>
    <String, dynamic>{'error': instance.error, 'stack': ?instance.stack};

Map<String, dynamic> _$ScenarioRestartResultToJson(
  ScenarioRestartResult instance,
) => <String, dynamic>{'restarted': instance.restarted};
