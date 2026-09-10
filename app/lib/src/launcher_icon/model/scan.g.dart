// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'scan.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

IconFile _$IconFileFromJson(Map<String, dynamic> json) => IconFile(
  path: json['path'] as String,
  absolutePath: json['absolutePath'] as String,
  modified: DateTime.parse(json['modified'] as String),
  width: (json['width'] as num?)?.toInt(),
  height: (json['height'] as num?)?.toInt(),
  hasAlpha: json['hasAlpha'] as bool? ?? false,
  density: json['density'] as String?,
  resourceType: json['resourceType'] as String?,
  icoFrames:
      (json['icoFrames'] as List<dynamic>?)
          ?.map((e) => (e as num).toInt())
          .toList() ??
      const [],
  declaredSize: (json['declaredSize'] as num?)?.toInt(),
  inherited: json['inherited'] as bool? ?? false,
);

Map<String, dynamic> _$IconFileToJson(IconFile instance) => <String, dynamic>{
  'path': instance.path,
  'absolutePath': instance.absolutePath,
  'modified': instance.modified.toIso8601String(),
  'width': ?instance.width,
  'height': ?instance.height,
  'hasAlpha': instance.hasAlpha,
  'density': ?instance.density,
  'resourceType': ?instance.resourceType,
  'icoFrames': instance.icoFrames,
  'declaredSize': ?instance.declaredSize,
  'inherited': instance.inherited,
};

IconRoleScan _$IconRoleScanFromJson(Map<String, dynamic> json) => IconRoleScan(
  role: _roleFromJson(json['role'] as String),
  files: (json['files'] as List<dynamic>)
      .map((e) => IconFile.fromJson(e as Map<String, dynamic>))
      .toList(),
  color: json['color'] as String?,
  referenced: json['referenced'] as bool?,
);

Map<String, dynamic> _$IconRoleScanToJson(IconRoleScan instance) =>
    <String, dynamic>{
      'role': _roleToJson(instance.role),
      'files': instance.files.map((e) => e.toJson()).toList(),
      'color': ?instance.color,
      'referenced': ?instance.referenced,
    };

IconFinding _$IconFindingFromJson(Map<String, dynamic> json) => IconFinding(
  $enumDecode(_$ToneEnumMap, json['tone']),
  json['message'] as String,
  role: _roleOrNullFromJson(json['role'] as String?),
);

Map<String, dynamic> _$IconFindingToJson(IconFinding instance) =>
    <String, dynamic>{
      'tone': _$ToneEnumMap[instance.tone]!,
      'message': instance.message,
      'role': ?_roleOrNullToJson(instance.role),
    };

const _$ToneEnumMap = {
  Tone.neutral: 'neutral',
  Tone.good: 'good',
  Tone.info: 'info',
  Tone.warn: 'warn',
  Tone.error: 'error',
};

IconScan _$IconScanFromJson(Map<String, dynamic> json) => IconScan(
  packagePath: json['packagePath'] as String,
  roles: (json['roles'] as List<dynamic>)
      .map((e) => IconRoleScan.fromJson(e as Map<String, dynamic>))
      .toList(),
  findings: (json['findings'] as List<dynamic>)
      .map((e) => IconFinding.fromJson(e as Map<String, dynamic>))
      .toList(),
  flavor: json['flavor'] as String?,
  flavors:
      (json['flavors'] as List<dynamic>?)
          ?.map((e) => IconFlavor.fromJson(e as Map<String, dynamic>))
          .toList() ??
      const [],
  android: json['android'] == null
      ? null
      : AndroidWiring.fromJson(json['android'] as Map<String, dynamic>),
  ios: $enumDecodeNullable(_$IosCatalogEnumMap, json['ios']) ?? IosCatalog.none,
  iconBundles:
      (json['iconBundles'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList() ??
      const [],
);

Map<String, dynamic> _$IconScanToJson(IconScan instance) => <String, dynamic>{
  'packagePath': instance.packagePath,
  'flavor': ?instance.flavor,
  'flavors': instance.flavors.map((e) => e.toJson()).toList(),
  'roles': instance.roles.map((e) => e.toJson()).toList(),
  'findings': instance.findings.map((e) => e.toJson()).toList(),
  'android': ?instance.android?.toJson(),
  'ios': _$IosCatalogEnumMap[instance.ios]!,
  'iconBundles': instance.iconBundles,
};

const _$IosCatalogEnumMap = {
  IosCatalog.none: 'none',
  IosCatalog.appIconSet: 'appIconSet',
  IosCatalog.iconComposer: 'iconComposer',
  IosCatalog.both: 'both',
};

IconFlavor _$IconFlavorFromJson(Map<String, dynamic> json) => IconFlavor(
  json['name'] as String,
  (json['sources'] as List<dynamic>)
      .map((e) => $enumDecode(_$IconFlavorSourceEnumMap, e))
      .toSet(),
);

Map<String, dynamic> _$IconFlavorToJson(IconFlavor instance) =>
    <String, dynamic>{
      'name': instance.name,
      'sources': instance.sources
          .map((e) => _$IconFlavorSourceEnumMap[e]!)
          .toList(),
    };

const _$IconFlavorSourceEnumMap = {
  IconFlavorSource.config: 'config',
  IconFlavorSource.androidSourceSet: 'androidSourceSet',
  IconFlavorSource.iosCatalog: 'iosCatalog',
};
