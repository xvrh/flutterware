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
