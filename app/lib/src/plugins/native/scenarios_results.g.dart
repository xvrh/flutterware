// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'scenarios_results.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Map<String, dynamic> _$ScenarioListResultToJson(ScenarioListResult instance) =>
    <String, dynamic>{
      'packages': instance.packages.map((e) => e.toJson()).toList(),
    };

Map<String, dynamic> _$ScenarioListPackageToJson(
  ScenarioListPackage instance,
) => <String, dynamic>{
  'path': instance.path,
  'directory': instance.directory,
  'scenarios': instance.scenarios.map((e) => e.toJson()).toList(),
  'diagnostics': instance.diagnostics,
  'error': ?instance.error,
  'authoring': ?instance.authoring,
};

Map<String, dynamic> _$ScenarioListEntryToJson(ScenarioListEntry instance) =>
    <String, dynamic>{
      'name': instance.name,
      'file': instance.file,
      'line': instance.line,
    };

Map<String, dynamic> _$ScenarioRunResultToJson(ScenarioRunResult instance) =>
    <String, dynamic>{
      'packages': instance.packages.map((e) => e.toJson()).toList(),
      'ok': instance.ok,
      'axes': ?instance.axes,
    };

Map<String, dynamic> _$ScenarioRunPackageToJson(ScenarioRunPackage instance) =>
    <String, dynamic>{
      'path': instance.path,
      'output': instance.output,
      'axes': ?instance.axes,
      'ms': instance.ms,
      'scenarios': instance.scenarios.map((e) => e.toJson()).toList(),
      'error': ?instance.error,
    };

Map<String, dynamic> _$ScenarioRunOutcomeToJson(ScenarioRunOutcome instance) =>
    <String, dynamic>{
      'file': instance.file,
      'name': instance.name,
      'ok': instance.ok,
      'device': ?instance.device,
      'ms': instance.ms,
      'steps': instance.steps.map((e) => e.toJson()).toList(),
      'errors': instance.errors.map((e) => e.toJson()).toList(),
    };

Map<String, dynamic> _$ScenarioRunStepToJson(ScenarioRunStep instance) =>
    <String, dynamic>{
      'index': instance.index,
      'position': instance.position,
      'parent': ?instance.parent,
      'branch': ?instance.branch,
      'name': ?instance.name,
      'auto': instance.auto,
      'action': ?instance.action?.toJson(),
      'tags': instance.tags,
      'image': instance.image,
      'format': instance.format,
      'width': instance.width,
      'height': instance.height,
      'tree': instance.tree,
      'semantics': ?instance.semantics,
      'texts': instance.texts,
      'verb': ?instance.verb,
      'target': ?instance.target,
      'events': ?instance.events,
      'eventCount': ?instance.eventCount,
      'eventChannels': ?instance.eventChannels,
      'eventTitles': ?instance.eventTitles,
      'eventsDropped': ?instance.eventsDropped,
      'frames': ?instance.frames,
      'frameCount': ?instance.frameCount,
      'frameWidth': ?instance.frameWidth,
      'frameHeight': ?instance.frameHeight,
      'frameIntervalMs': ?instance.frameIntervalMs,
      'framesDropped': ?instance.framesDropped,
      'address': instance.address,
      'statusBrightness': ?instance.statusBrightness,
      'navBrightness': ?instance.navBrightness,
      'settled': instance.settled,
      'strayFrames': instance.strayFrames,
      'failure': ?instance.failure,
    };

Map<String, dynamic> _$ScenarioStepActionToJson(ScenarioStepAction instance) =>
    <String, dynamic>{
      'verb': instance.verb,
      'target': ?instance.target,
      'kind': ?instance.kind,
    };

Map<String, dynamic> _$ScenarioRunErrorToJson(ScenarioRunError instance) =>
    <String, dynamic>{'error': instance.error, 'stack': ?instance.stack};

Map<String, dynamic> _$ScenarioNewResultToJson(ScenarioNewResult instance) =>
    <String, dynamic>{
      'package': instance.package,
      'file': instance.file,
      'name': instance.name,
      'next': instance.next,
    };

Map<String, dynamic> _$ScenarioRestartResultToJson(
  ScenarioRestartResult instance,
) => <String, dynamic>{'restarted': instance.restarted};

Map<String, dynamic> _$ScenarioShotsResultToJson(
  ScenarioShotsResult instance,
) => <String, dynamic>{
  'packages': instance.packages.map((e) => e.toJson()).toList(),
  'count': instance.count,
};

Map<String, dynamic> _$ScenarioShotsPackageToJson(
  ScenarioShotsPackage instance,
) => <String, dynamic>{
  'path': instance.path,
  'output': instance.output,
  'sets': instance.sets.map((e) => e.toJson()).toList(),
  'error': ?instance.error,
};

Map<String, dynamic> _$ScenarioShotSetToJson(ScenarioShotSet instance) =>
    <String, dynamic>{
      'directory': instance.directory,
      'axes': instance.axes,
      'images': instance.images,
      'failed': instance.failed,
    };
