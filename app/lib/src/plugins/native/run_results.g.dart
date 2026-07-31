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
      'kind': instance.kind,
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

Map<String, dynamic> _$RunEntrypointsResultToJson(
  RunEntrypointsResult instance,
) => <String, dynamic>{
  'packages': instance.packages.map((e) => e.toJson()).toList(),
  'note': ?instance.note,
};

Map<String, dynamic> _$RunEntrypointPackageToJson(
  RunEntrypointPackage instance,
) => <String, dynamic>{
  'path': instance.path,
  'declared': instance.declared,
  'entrypoints': instance.entrypoints.map((e) => e.toJson()).toList(),
};

Map<String, dynamic> _$RunEntrypointEntryToJson(RunEntrypointEntry instance) =>
    <String, dynamic>{
      'path': instance.path,
      'name': instance.name,
      'description': ?instance.description,
      'knobs': instance.knobs.map((e) => e.toJson()).toList(),
    };

Map<String, dynamic> _$RunKnobEntryToJson(RunKnobEntry instance) =>
    <String, dynamic>{
      'define': instance.define,
      'label': ?instance.label,
      'description': ?instance.description,
      'default': ?instance.defaultValue,
      'options': instance.options,
    };

Map<String, dynamic> _$RunLaunchResultToJson(RunLaunchResult instance) =>
    <String, dynamic>{
      'app': instance.app.toJson(),
      'status': instance.status,
      'waited': instance.waited,
      'progress': ?instance.progress,
      'error': ?instance.error,
      'note': ?instance.note,
    };

Map<String, dynamic> _$RunControlResultToJson(RunControlResult instance) =>
    <String, dynamic>{
      'action': instance.action,
      'device': instance.device,
      'entrypoint': instance.entrypoint,
      'ok': instance.ok,
      'ms': instance.ms,
      'error': ?instance.error,
      'note': ?instance.note,
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

Map<String, dynamic> _$RunScreenshotResultToJson(
  RunScreenshotResult instance,
) => <String, dynamic>{
  'device': instance.device,
  'entrypoint': instance.entrypoint,
  'path': instance.path,
  'bytes': instance.bytes,
  'ms': instance.ms,
  'note': ?instance.note,
};

Map<String, dynamic> _$RunLogEntryToJson(RunLogEntry instance) =>
    <String, dynamic>{
      'source': instance.source,
      'text': instance.text,
      'error': instance.error,
    };

Map<String, dynamic> _$RunEmulatorsResultToJson(RunEmulatorsResult instance) =>
    <String, dynamic>{
      'emulators': instance.emulators.map((e) => e.toJson()).toList(),
      'note': ?instance.note,
    };

Map<String, dynamic> _$RunEmulatorEntryToJson(RunEmulatorEntry instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'platform': ?instance.platform,
      'booted': ?instance.booted,
    };

Map<String, dynamic> _$RunBootResultToJson(RunBootResult instance) =>
    <String, dynamic>{
      'emulator': instance.emulator,
      'started': instance.started,
      'device': ?instance.device,
      'deviceName': ?instance.deviceName,
      'ms': instance.ms,
      'note': ?instance.note,
    };

Map<String, dynamic> _$RunInspectResultToJson(RunInspectResult instance) =>
    <String, dynamic>{
      'device': instance.device,
      'entrypoint': instance.entrypoint,
      'worktree': ?instance.worktree,
      'mine': ?instance.mine,
      'up': instance.up,
      'reloadable': instance.reloadable,
      'progress': ?instance.progress,
      'tree': ?instance.tree,
      'nodes': ?instance.nodes,
      'summary': ?instance.summary,
      'screenshot': ?instance.screenshot,
      'logs': ?instance.logs?.map((e) => e.toJson()).toList(),
      'logLines': ?instance.logLines,
      'errors': ?instance.errors?.map((e) => e.toJson()).toList(),
      'log': ?instance.log,
      'note': ?instance.note,
    };
