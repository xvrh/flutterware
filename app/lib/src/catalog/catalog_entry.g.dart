// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'catalog_entry.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

CatalogEntry _$CatalogEntryFromJson(Map<String, dynamic> json) => CatalogEntry(
  path: json['path'] as String,
  symbol: json['symbol'] as String,
  annotation: json['annotation'] as String,
  name: json['name'] as String,
  group: json['group'] as String?,
  declaredId: json['declaredId'] as String?,
  formFactor: json['formFactor'] as String?,
  wrapper: json['wrapper'] as String?,
  shellId: json['shellId'] as String?,
);

Map<String, dynamic> _$CatalogEntryToJson(CatalogEntry instance) =>
    <String, dynamic>{
      'path': instance.path,
      'symbol': instance.symbol,
      'annotation': instance.annotation,
      'name': instance.name,
      'group': instance.group,
      'declaredId': instance.declaredId,
      'formFactor': instance.formFactor,
      'wrapper': instance.wrapper,
      'shellId': instance.shellId,
    };
