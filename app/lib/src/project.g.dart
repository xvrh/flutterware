// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'project.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Project _$ProjectFromJson(Map<String, dynamic> json) => Project(
      json['directory'] as String,
      FlutterSdkPath.fromJson(json['flutterSdkPath'] as Map<String, dynamic>),
    );

Map<String, dynamic> _$ProjectToJson(Project instance) => <String, dynamic>{
      'directory': instance.directory,
      'flutterSdkPath': instance.flutterSdkPath,
    };
