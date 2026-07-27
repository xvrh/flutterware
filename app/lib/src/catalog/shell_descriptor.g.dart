// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'shell_descriptor.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ShellDescriptor _$ShellDescriptorFromJson(Map<String, dynamic> json) =>
    ShellDescriptor(
      path: json['path'] as String,
      symbol: json['symbol'] as String,
      axes:
          (json['axes'] as List<dynamic>?)
              ?.map((e) => ShellAxis.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
    );

Map<String, dynamic> _$ShellDescriptorToJson(ShellDescriptor instance) =>
    <String, dynamic>{
      'path': instance.path,
      'symbol': instance.symbol,
      'axes': instance.axes,
    };

ShellAxis _$ShellAxisFromJson(Map<String, dynamic> json) => ShellAxis(
  name: json['name'] as String,
  typeName: json['typeName'] as String,
  defaultSource: json['defaultSource'] as String,
);

Map<String, dynamic> _$ShellAxisToJson(ShellAxis instance) => <String, dynamic>{
  'name': instance.name,
  'typeName': instance.typeName,
  'defaultSource': instance.defaultSource,
};
