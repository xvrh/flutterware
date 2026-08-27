// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'store_results.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Map<String, dynamic> _$StoreExportResultToJson(StoreExportResult instance) =>
    <String, dynamic>{
      'packages': instance.packages.map((e) => e.toJson()).toList(),
      'count': instance.count,
    };

Map<String, dynamic> _$StoreExportPackageToJson(StoreExportPackage instance) =>
    <String, dynamic>{
      'path': instance.path,
      'output': instance.output,
      'sets': instance.sets.map((e) => e.toJson()).toList(),
      'error': ?instance.error,
    };

Map<String, dynamic> _$StoreExportSetToJson(StoreExportSet instance) =>
    <String, dynamic>{
      'store': instance.store,
      'deviceClass': instance.deviceClass,
      'locale': instance.locale,
      'directory': instance.directory,
      'width': instance.width,
      'height': instance.height,
      'images': instance.images,
      'failed': instance.failed,
      'framesFailed': instance.framesFailed,
    };

Map<String, dynamic> _$StoreOpenResultToJson(StoreOpenResult instance) =>
    <String, dynamic>{'paths': instance.paths};
