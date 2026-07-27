// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'protocol.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

SelectRequest _$SelectRequestFromJson(Map<String, dynamic> json) =>
    SelectRequest(json['id'] as String, full: json['full'] as bool? ?? false);

Map<String, dynamic> _$SelectRequestToJson(SelectRequest instance) =>
    <String, dynamic>{'id': instance.id, 'full': instance.full};

DaemonReady _$DaemonReadyFromJson(Map<String, dynamic> json) => DaemonReady(
  hostPath: json['hostPath'] as String,
  assetsDir: json['assetsDir'] as String,
  icuData: json['icuData'] as String,
  coldCompile: _millis.fromJson((json['coldCompile'] as num).toInt()),
  entries: (json['entries'] as List<dynamic>)
      .map((e) => CatalogEntry.fromJson(e as Map<String, dynamic>))
      .toList(),
  diagnostics:
      (json['diagnostics'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList() ??
      const [],
);

Map<String, dynamic> _$DaemonReadyToJson(DaemonReady instance) =>
    <String, dynamic>{
      'hostPath': instance.hostPath,
      'assetsDir': instance.assetsDir,
      'icuData': instance.icuData,
      'coldCompile': _millis.toJson(instance.coldCompile),
      'entries': instance.entries.map((e) => e.toJson()).toList(),
      'diagnostics': instance.diagnostics,
    };

DaemonCompiled _$DaemonCompiledFromJson(Map<String, dynamic> json) =>
    DaemonCompiled(
      id: json['id'] as String,
      compile: _millis.fromJson((json['compile'] as num).toInt()),
      newSourceCount: (json['newSourceCount'] as num).toInt(),
      dill: json['dill'] as String?,
      error: json['error'] as String?,
    );

Map<String, dynamic> _$DaemonCompiledToJson(DaemonCompiled instance) =>
    <String, dynamic>{
      'id': instance.id,
      'dill': instance.dill,
      'compile': _millis.toJson(instance.compile),
      'newSourceCount': instance.newSourceCount,
      'error': instance.error,
    };

DaemonFailed _$DaemonFailedFromJson(Map<String, dynamic> json) => DaemonFailed(
  message: json['message'] as String,
  stackTrace: json['stackTrace'] as String?,
);

Map<String, dynamic> _$DaemonFailedToJson(DaemonFailed instance) =>
    <String, dynamic>{
      'message': instance.message,
      'stackTrace': instance.stackTrace,
    };

DaemonConfig _$DaemonConfigFromJson(Map<String, dynamic> json) => DaemonConfig(
  appPackageRoot: json['appPackageRoot'] as String,
  projectRoot: json['projectRoot'] as String,
  packageConfig: json['packageConfig'] as String,
  flutterSdkRoot: json['flutterSdkRoot'] as String,
  roots:
      (json['roots'] as List<dynamic>?)?.map((e) => e as String).toList() ??
      const ['demo'],
  previewAnnotations:
      (json['previewAnnotations'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList() ??
      const ['Preview', 'Demo'],
  emitProbe: json['emitProbe'] as bool? ?? false,
);

Map<String, dynamic> _$DaemonConfigToJson(DaemonConfig instance) =>
    <String, dynamic>{
      'appPackageRoot': instance.appPackageRoot,
      'projectRoot': instance.projectRoot,
      'packageConfig': instance.packageConfig,
      'flutterSdkRoot': instance.flutterSdkRoot,
      'roots': instance.roots,
      'previewAnnotations': instance.previewAnnotations,
      'emitProbe': instance.emitProbe,
    };
