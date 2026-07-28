// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'dependencies_results.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Map<String, dynamic> _$DependencyListResultToJson(
  DependencyListResult instance,
) => <String, dynamic>{
  'packages': instance.packages.map((e) => e.toJson()).toList(),
};

Map<String, dynamic> _$DependencyListPackageToJson(
  DependencyListPackage instance,
) => <String, dynamic>{
  'path': instance.path,
  'direct': instance.direct,
  'transitive': instance.transitive,
  'dependencies': instance.dependencies.map((e) => e.toJson()).toList(),
  'error': ?instance.error,
};

Map<String, dynamic> _$DependencyEntryToJson(DependencyEntry instance) =>
    <String, dynamic>{
      'name': instance.name,
      'direct': instance.direct,
      'version': ?instance.version,
      'source': ?instance.source,
    };
