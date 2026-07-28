// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'ui_catalog_results.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Map<String, dynamic> _$CatalogEntriesResultToJson(
  CatalogEntriesResult instance,
) => <String, dynamic>{
  'packages': instance.packages.map((e) => e.toJson()).toList(),
};

Map<String, dynamic> _$CatalogPackageEntriesToJson(
  CatalogPackageEntries instance,
) => <String, dynamic>{
  'path': instance.path,
  'entries': instance.entries.map((e) => e.toJson()).toList(),
  'diagnostics': instance.diagnostics,
  'error': ?instance.error,
};

Map<String, dynamic> _$CatalogEntrySummaryToJson(
  CatalogEntrySummary instance,
) => <String, dynamic>{
  'id': instance.id,
  'name': instance.name,
  'address': instance.address,
  'group': ?instance.group,
  'formFactor': ?instance.formFactor,
};

Map<String, dynamic> _$CatalogCheckResultToJson(CatalogCheckResult instance) =>
    <String, dynamic>{
      'packages': instance.packages.map((e) => e.toJson()).toList(),
    };

Map<String, dynamic> _$CatalogPackageCheckToJson(
  CatalogPackageCheck instance,
) => <String, dynamic>{
  'path': instance.path,
  'ok': instance.ok,
  'servable': instance.servable,
  'broken': instance.broken.map((e) => e.toJson()).toList(),
  'error': ?instance.error,
};

Map<String, dynamic> _$CatalogBrokenEntryToJson(CatalogBrokenEntry instance) =>
    <String, dynamic>{'id': instance.id, 'error': instance.error};

Map<String, dynamic> _$CatalogEntryDescriptionToJson(
  CatalogEntryDescription instance,
) => <String, dynamic>{
  'id': instance.id,
  'name': instance.name,
  'package': instance.package,
  'file': instance.file,
  'symbol': instance.symbol,
  'annotation': instance.annotation,
  'address': instance.address,
  'group': ?instance.group,
  'formFactor': ?instance.formFactor,
  'knobs': ?instance.knobs?.map((e) => e.toJson()).toList(),
};

Map<String, dynamic> _$CatalogKnobToJson(CatalogKnob instance) =>
    <String, dynamic>{
      'name': instance.name,
      'kind': instance.kind,
      'value': ?instance.value,
      'default': ?instance.defaultValue,
      'min': ?instance.min,
      'max': ?instance.max,
      'options': instance.options,
    };
