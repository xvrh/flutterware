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
);

Map<String, dynamic> _$CatalogEntryToJson(CatalogEntry instance) =>
    <String, dynamic>{
      'path': instance.path,
      'symbol': instance.symbol,
      'annotation': instance.annotation,
      'name': instance.name,
    };
