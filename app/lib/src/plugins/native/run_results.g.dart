// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'run_results.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Map<String, dynamic> _$RunDevicesResultToJson(RunDevicesResult instance) =>
    <String, dynamic>{
      'devices': instance.devices.map((e) => e.toJson()).toList(),
      'live': instance.live,
      'updatedAt': ?instance.updatedAt,
      'age': ?instance.age,
      'note': ?instance.note,
    };

Map<String, dynamic> _$RunDeviceEntryToJson(RunDeviceEntry instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'platform': ?instance.platform,
      'sdk': ?instance.sdk,
      'emulator': instance.emulator,
      'physical': instance.physical,
      'connected': instance.connected,
      'connection': ?instance.connection,
      'running': instance.running.map((e) => e.toJson()).toList(),
    };

Map<String, dynamic> _$RunHolderToJson(RunHolder instance) => <String, dynamic>{
  'worktree': instance.worktree,
  'entrypoint': instance.entrypoint,
  'entrypointName': ?instance.entrypointName,
  'package': ?instance.package,
  'since': instance.since,
  'canReload': instance.canReload,
  'canInspect': instance.canInspect,
};

Map<String, dynamic> _$RunAppsResultToJson(RunAppsResult instance) =>
    <String, dynamic>{
      'apps': instance.apps.map((e) => e.toJson()).toList(),
      'swept': instance.swept,
      'note': ?instance.note,
    };

Map<String, dynamic> _$RunAppEntryToJson(RunAppEntry instance) =>
    <String, dynamic>{
      'device': instance.device,
      'deviceName': ?instance.deviceName,
      'worktree': instance.worktree,
      'mine': instance.mine,
      'package': ?instance.package,
      'entrypoint': instance.entrypoint,
      'entrypointName': ?instance.entrypointName,
      'knobs': instance.knobs,
      'since': instance.since,
      'app': instance.app,
      'launcher': instance.launcher,
      'vmService': ?instance.vmService,
      'log': ?instance.log,
      'error': ?instance.error,
    };
