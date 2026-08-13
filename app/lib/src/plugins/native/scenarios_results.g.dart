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

ScenarioRunResult _$ScenarioRunResultFromJson(Map<String, dynamic> json) =>
    ScenarioRunResult(
      packages: (json['packages'] as List<dynamic>)
          .map((e) => ScenarioRunPackage.fromJson(e as Map<String, dynamic>))
          .toList(),
      axes: (json['axes'] as Map<String, dynamic>?)?.map(
        (k, e) => MapEntry(k, e as String),
      ),
    );

Map<String, dynamic> _$ScenarioRunResultToJson(ScenarioRunResult instance) =>
    <String, dynamic>{
      'packages': instance.packages.map((e) => e.toJson()).toList(),
      'axes': ?instance.axes,
    };

ScenarioRunPackage _$ScenarioRunPackageFromJson(Map<String, dynamic> json) =>
    ScenarioRunPackage(
      path: json['path'] as String,
      output: json['output'] as String,
      axes: (json['axes'] as Map<String, dynamic>?)?.map(
        (k, e) => MapEntry(k, e as String),
      ),
      ms: (json['ms'] as num?)?.toInt() ?? 0,
      scenarios:
          (json['scenarios'] as List<dynamic>?)
              ?.map(
                (e) => ScenarioRunOutcome.fromJson(e as Map<String, dynamic>),
              )
              .toList() ??
          const [],
      report: json['report'] as String?,
      error: json['error'] as String?,
    );

Map<String, dynamic> _$ScenarioRunPackageToJson(ScenarioRunPackage instance) =>
    <String, dynamic>{
      'path': instance.path,
      'output': instance.output,
      'report': ?instance.report,
      'axes': ?instance.axes,
      'ms': instance.ms,
      'scenarios': instance.scenarios.map((e) => e.toJson()).toList(),
      'error': ?instance.error,
    };

ScenarioRunOutcome _$ScenarioRunOutcomeFromJson(Map<String, dynamic> json) =>
    ScenarioRunOutcome(
      file: json['file'] as String,
      name: json['name'] as String,
      ok: json['ok'] as bool,
      device: json['device'] as String?,
      ms: (json['ms'] as num?)?.toInt() ?? 0,
      steps:
          (json['steps'] as List<dynamic>?)
              ?.map((e) => ScenarioRunStep.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      stepCount: (json['stepCount'] as num?)?.toInt() ?? 0,
      errors:
          (json['errors'] as List<dynamic>?)
              ?.map((e) => ScenarioRunError.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
    );

Map<String, dynamic> _$ScenarioRunOutcomeToJson(ScenarioRunOutcome instance) =>
    <String, dynamic>{
      'file': instance.file,
      'name': instance.name,
      'ok': instance.ok,
      'device': ?instance.device,
      'ms': instance.ms,
      'steps': instance.steps.map((e) => e.toJson()).toList(),
      'stepCount': instance.stepCount,
      'errors': instance.errors.map((e) => e.toJson()).toList(),
    };

ScenarioRunStep _$ScenarioRunStepFromJson(Map<String, dynamic> json) =>
    ScenarioRunStep(
      index: (json['index'] as num).toInt(),
      position: json['position'] as String,
      auto: json['auto'] as bool,
      image: json['image'] as String,
      format: json['format'] as String,
      width: (json['width'] as num).toInt(),
      height: (json['height'] as num).toInt(),
      tree: json['tree'] as String,
      texts: (json['texts'] as List<dynamic>).map((e) => e as String).toList(),
      address: json['address'] as String,
      semantics: json['semantics'] as String?,
      parent: (json['parent'] as num?)?.toInt(),
      branch: json['branch'] as String?,
      name: json['name'] as String?,
      action: json['action'] == null
          ? null
          : ScenarioStepAction.fromJson(json['action'] as Map<String, dynamic>),
      tags:
          (json['tags'] as List<dynamic>?)?.map((e) => e as String).toList() ??
          const [],
      statusBrightness: json['statusBrightness'] as String?,
      navBrightness: json['navBrightness'] as String?,
      verb: json['verb'] as String?,
      target: json['target'] as String?,
      events: json['events'] as String?,
      eventCount: (json['eventCount'] as num?)?.toInt(),
      eventChannels: (json['eventChannels'] as Map<String, dynamic>?)?.map(
        (k, e) => MapEntry(k, (e as num).toInt()),
      ),
      eventTitles: (json['eventTitles'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
      eventsDropped: (json['eventsDropped'] as num?)?.toInt(),
      frames: json['frames'] as String?,
      frameCount: (json['frameCount'] as num?)?.toInt(),
      frameWidth: (json['frameWidth'] as num?)?.toInt(),
      frameHeight: (json['frameHeight'] as num?)?.toInt(),
      frameIntervalMs: (json['frameIntervalMs'] as num?)?.toInt(),
      framesDropped: (json['framesDropped'] as num?)?.toInt(),
      settled: json['settled'] as bool? ?? true,
      strayFrames: (json['strayFrames'] as num?)?.toInt() ?? 0,
      failure: json['failure'] as String?,
    );

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

ScenarioStepAction _$ScenarioStepActionFromJson(Map<String, dynamic> json) =>
    ScenarioStepAction(
      verb: json['verb'] as String,
      target: json['target'] as String?,
      kind: json['kind'] as String?,
    );

Map<String, dynamic> _$ScenarioStepActionToJson(ScenarioStepAction instance) =>
    <String, dynamic>{
      'verb': instance.verb,
      'target': ?instance.target,
      'kind': ?instance.kind,
    };

ScenarioRunError _$ScenarioRunErrorFromJson(Map<String, dynamic> json) =>
    ScenarioRunError(
      error: json['error'] as String,
      stack: json['stack'] as String?,
    );

Map<String, dynamic> _$ScenarioRunErrorToJson(ScenarioRunError instance) =>
    <String, dynamic>{'error': instance.error, 'stack': ?instance.stack};

Map<String, dynamic> _$ScenarioWebExportResultToJson(
  ScenarioWebExportResult instance,
) => <String, dynamic>{
  'output': instance.output,
  'indexHtml': instance.indexHtml,
  'scenarios': instance.scenarios,
  'steps': instance.steps,
  'artifacts': instance.artifacts,
  'durationMs': instance.durationMs,
  'failed': instance.failed,
  'serve': instance.serve,
  'ok': instance.ok,
};

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

Map<String, dynamic> _$ScenarioReadResultToJson(ScenarioReadResult instance) =>
    <String, dynamic>{
      'step': instance.step,
      'lens': instance.lens,
      'scenario': ?instance.scenario,
      'file': ?instance.file,
      'index': ?instance.index,
      'failure': ?instance.failure,
      'image': ?instance.image,
      'screen': ?instance.screen?.toJson(),
      'texts': ?instance.texts,
      'tree': ?instance.tree,
      'nodes': ?instance.nodes,
      'find': ?instance.find,
      'at': ?instance.at,
      'styles': ?instance.styles?.map((e) => e.toJson()).toList(),
      'note': ?instance.note,
      'next': ?instance.next,
      'steps': instance.steps,
    };
