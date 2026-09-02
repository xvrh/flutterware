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
  ordinal: (json['ordinal'] as num?)?.toInt() ?? 0,
  knobs:
      (json['knobs'] as List<dynamic>?)
          ?.map((e) => KnobDescriptor.fromJson(e as Map<String, dynamic>))
          .toList() ??
      const [],
  line: (json['line'] as num?)?.toInt() ?? 0,
  endLine: (json['endLine'] as num?)?.toInt() ?? 0,
);

Map<String, dynamic> _$CatalogEntryToJson(CatalogEntry instance) =>
    <String, dynamic>{
      'path': instance.path,
      'symbol': instance.symbol,
      'knobs': instance.knobs,
      'annotation': instance.annotation,
      'name': instance.name,
      'group': instance.group,
      'declaredId': instance.declaredId,
      'ordinal': instance.ordinal,
      'line': instance.line,
      'endLine': instance.endLine,
    };
