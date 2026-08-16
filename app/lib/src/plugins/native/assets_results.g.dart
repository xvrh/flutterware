// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'assets_results.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Map<String, dynamic> _$AssetListResultToJson(AssetListResult instance) =>
    <String, dynamic>{
      'packages': instance.packages.map((e) => e.toJson()).toList(),
    };

Map<String, dynamic> _$AssetListPackageToJson(AssetListPackage instance) =>
    <String, dynamic>{
      'path': instance.path,
      'own': instance.own,
      'fromPackages': instance.fromPackages,
      'bytes': instance.bytes,
      'assets': instance.assets.map((e) => e.toJson()).toList(),
      'error': ?instance.error,
    };

Map<String, dynamic> _$AssetEntryToJson(AssetEntry instance) =>
    <String, dynamic>{
      'key': instance.key,
      'kind': instance.kind,
      'bytes': instance.bytes,
      'address': instance.address,
      'package': ?instance.package,
      'densities': instance.densities,
    };

Map<String, dynamic> _$AssetDescriptionToJson(AssetDescription instance) =>
    <String, dynamic>{
      'key': instance.key,
      'kind': instance.kind,
      'address': instance.address,
      'declaration': instance.declaration,
      'file': instance.file,
      'bytes': instance.bytes,
      'totalBytes': instance.totalBytes,
      'code': instance.code,
      'package': ?instance.package,
      'densities': instance.densities.map((e) => e.toJson()).toList(),
      'raster': ?instance.raster?.toJson(),
      'animation': ?instance.animation?.toJson(),
      'font': ?instance.font?.toJson(),
    };

Map<String, dynamic> _$AssetDensityToJson(AssetDensity instance) =>
    <String, dynamic>{
      'scale': ?instance.scale,
      'file': instance.file,
      'bytes': instance.bytes,
    };

Map<String, dynamic> _$RasterFactsResultToJson(RasterFactsResult instance) =>
    <String, dynamic>{
      'width': instance.width,
      'height': instance.height,
      'frames': instance.frames,
    };

Map<String, dynamic> _$AnimationFactsResultToJson(
  AnimationFactsResult instance,
) => <String, dynamic>{
  'width': instance.width,
  'height': instance.height,
  'frameRate': instance.frameRate,
  'frames': instance.frames,
  'durationMs': instance.durationMs,
  'version': ?instance.version,
  'layers': instance.layers.map((e) => e.toJson()).toList(),
  'markers': instance.markers,
};

Map<String, dynamic> _$AnimationLayerResultToJson(
  AnimationLayerResult instance,
) => <String, dynamic>{'name': instance.name, 'type': instance.type};

Map<String, dynamic> _$FontFactsResultToJson(FontFactsResult instance) =>
    <String, dynamic>{
      'family': instance.family,
      'weight': ?instance.weight,
      'style': ?instance.style,
    };

Map<String, dynamic> _$AssetAuditResultToJson(AssetAuditResult instance) =>
    <String, dynamic>{
      'checked': instance.checked,
      'bytes': instance.bytes,
      'findings': instance.findings.map((e) => e.toJson()).toList(),
      'unreadable': instance.unreadable,
      'ok': instance.ok,
    };

Map<String, dynamic> _$AssetFindingToJson(AssetFinding instance) =>
    <String, dynamic>{
      'kind': instance.kind,
      'summary': instance.summary,
      'detail': instance.detail,
      'package': ?instance.package,
      'key': ?instance.key,
      'address': ?instance.address,
      'path': ?instance.path,
    };
