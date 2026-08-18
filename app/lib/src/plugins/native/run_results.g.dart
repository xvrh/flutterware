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
      'flavor': ?instance.flavor,
      'flavorSource': ?instance.flavorSource,
      'flavorByPlatform': ?instance.flavorByPlatform,
      'platforms': instance.platforms,
      'devices': instance.devices,
      'knobs': instance.knobs.map((e) => e.toJson()).toList(),
    };

Map<String, dynamic> _$RunKnobEntryToJson(RunKnobEntry instance) =>
    <String, dynamic>{
      'knob': instance.name,
      'label': ?instance.label,
      'description': ?instance.description,
      'kind': ?instance.kind,
      'default': ?instance.defaultValue,
      'defaultSource': ?instance.defaultSource,
      'options': instance.options,
      'problem': ?instance.problem,
      'required': ?RunKnobEntry._ifRequired(instance.required),
    };

Map<String, dynamic> _$RunLaunchResultToJson(RunLaunchResult instance) =>
    <String, dynamic>{
      'app': instance.app.toJson(),
      'status': instance.status,
      'waited': instance.waited,
      'progress': ?instance.progress,
      'error': ?instance.error,
      'headline': ?instance.headline,
      'logPath': ?instance.logPath,
      'note': ?instance.note,
    };

Map<String, dynamic> _$RunControlResultToJson(RunControlResult instance) =>
    <String, dynamic>{
      'action': instance.action,
      'run': instance.run,
      'device': instance.device,
      'entrypoint': instance.entrypoint,
      'ok': instance.ok,
      'ms': instance.ms,
      'error': ?instance.error,
      'note': ?instance.note,
      'knobs': ?instance.knobs,
    };

Map<String, dynamic> _$RunAppsResultToJson(RunAppsResult instance) =>
    <String, dynamic>{
      'apps': instance.apps.map((e) => e.toJson()).toList(),
      'swept': instance.swept,
      'note': ?instance.note,
    };

Map<String, dynamic> _$RunAppEntryToJson(RunAppEntry instance) =>
    <String, dynamic>{
      'run': instance.run,
      'device': instance.device,
      'deviceName': ?instance.deviceName,
      'worktree': instance.worktree,
      'mine': instance.mine,
      'package': ?instance.package,
      'entrypoint': instance.entrypoint,
      'entrypointName': ?instance.entrypointName,
      'defines': instance.defines,
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
      'nativeLog': ?instance.nativeLog,
      'note': ?instance.note,
    };

Map<String, dynamic> _$RunActResultToJson(RunActResult instance) =>
    <String, dynamic>{
      'device': instance.device,
      'entrypoint': instance.entrypoint,
      'worktree': ?instance.worktree,
      'verb': instance.verb,
      'target': ?instance.target,
      'ok': instance.ok,
      'error': ?instance.error,
      'failure': ?instance.failure,
      'attempts': ?instance.attempts,
      'elapsedMs': ?instance.elapsedMs,
      'settled': ?instance.settled,
      'settleMs': ?instance.settleMs,
      'frames': ?instance.frames,
      'framesEnabled': ?instance.framesEnabled,
      'lifecycle': ?instance.lifecycle,
      'human': ?instance.human,
      'texts': ?instance.texts,
      'capture': ?instance.capture,
      'lens': ?instance.lens,
      'screen': ?instance.screen?.toJson(),
      'tree': ?instance.tree,
      'find': ?instance.find,
      'at': ?instance.at,
      'styles': ?instance.styles?.map((e) => e.toJson()).toList(),
      'nodes': ?instance.nodes,
      'screenshot': ?instance.screenshot,
      'logs': ?instance.logs?.map((e) => e.toJson()).toList(),
      'errors': ?instance.errors?.map((e) => e.toJson()).toList(),
      'journal': ?instance.journal,
      'next': ?instance.next,
      'note': ?instance.note,
      'layer': ?instance.layer,
      'coordinateSpace': ?instance.coordinateSpace,
      'screenshotScale': ?instance.screenshotScale,
      'nativeTree': ?instance.nativeTree,
      'reconciled': ?instance.reconciled,
    };

Map<String, dynamic> _$RunPanelsResultToJson(RunPanelsResult instance) =>
    <String, dynamic>{
      'device': instance.device,
      'entrypoint': instance.entrypoint,
      'panels': instance.panels,
      'events': instance.events,
      'note': ?instance.note,
    };

Map<String, dynamic> _$RunPanelResultToJson(RunPanelResult instance) =>
    <String, dynamic>{
      'device': instance.device,
      'entrypoint': instance.entrypoint,
      'panel': instance.panel,
      'result': instance.result,
      'knobs': ?instance.knobs,
      'note': ?instance.note,
    };

Map<String, dynamic> _$RunNetworkResultToJson(RunNetworkResult instance) =>
    <String, dynamic>{
      'device': instance.device,
      'entrypoint': instance.entrypoint,
      'requests': instance.requests,
      'cursor': instance.cursor,
      'note': ?instance.note,
    };

Map<String, dynamic> _$RunNetworkRequestResultToJson(
  RunNetworkRequestResult instance,
) => <String, dynamic>{
  'device': instance.device,
  'entrypoint': instance.entrypoint,
  'request': instance.request,
  'note': ?instance.note,
};

Map<String, dynamic> _$RunLensResultToJson(RunLensResult instance) =>
    <String, dynamic>{
      'device': instance.device,
      'entrypoint': instance.entrypoint,
      'lens': instance.lens,
      'pinned': instance.pinned,
      'was': ?instance.was,
      'lenses': instance.lenses,
    };
