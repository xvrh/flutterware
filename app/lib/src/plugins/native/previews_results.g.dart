// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'previews_results.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Map<String, dynamic> _$CatalogEntriesResultToJson(
  CatalogEntriesResult instance,
) => <String, dynamic>{
  'packages': instance.packages.map((e) => e.toJson()).toList(),
};

Map<String, dynamic> _$CatalogPackageEntriesToJson(
  CatalogPackageEntries instance,
) => <String, dynamic>{
  'path': instance.path,
  'directory': instance.directory,
  'entries': instance.entries.map((e) => e.toJson()).toList(),
  'diagnostics': instance.diagnostics,
  'error': ?instance.error,
  'authoring': ?instance.authoring,
};

Map<String, dynamic> _$CatalogNewResultToJson(CatalogNewResult instance) =>
    <String, dynamic>{
      'package': instance.package,
      'file': instance.file,
      'name': instance.name,
      'id': instance.id,
      'next': instance.next,
    };

Map<String, dynamic> _$CatalogEntrySummaryToJson(
  CatalogEntrySummary instance,
) => <String, dynamic>{
  'id': instance.id,
  'name': instance.name,
  'address': instance.address,
  'group': ?instance.group,
};

Map<String, dynamic> _$CatalogCheckResultToJson(CatalogCheckResult instance) =>
    <String, dynamic>{
      'packages': instance.packages.map((e) => e.toJson()).toList(),
    };

Map<String, dynamic> _$CatalogPackageCheckToJson(
  CatalogPackageCheck instance,
) => <String, dynamic>{
  'path': instance.path,
  'ok': instance.ok,
  'servable': instance.servable,
  'broken': instance.broken.map((e) => e.toJson()).toList(),
  'error': ?instance.error,
};

Map<String, dynamic> _$CatalogBrokenEntryToJson(CatalogBrokenEntry instance) =>
    <String, dynamic>{'id': instance.id, 'error': instance.error};

Map<String, dynamic> _$CatalogEntryDescriptionToJson(
  CatalogEntryDescription instance,
) => <String, dynamic>{
  'id': instance.id,
  'name': instance.name,
  'package': instance.package,
  'file': instance.file,
  'symbol': instance.symbol,
  'annotation': instance.annotation,
  'address': instance.address,
  'group': ?instance.group,
  'knobs': ?instance.knobs?.map((e) => e.toJson()).toList(),
  'axes': ?instance.axes?.map((e) => e.toJson()).toList(),
  'shell': ?instance.shell,
};

Map<String, dynamic> _$CatalogKnobToJson(CatalogKnob instance) =>
    <String, dynamic>{
      'name': instance.name,
      'kind': instance.kind,
      'value': ?instance.value,
      'default': ?instance.defaultValue,
      'min': ?instance.min,
      'max': ?instance.max,
      'options': instance.options,
    };

Map<String, dynamic> _$CatalogTreeNodeToJson(CatalogTreeNode instance) =>
    <String, dynamic>{
      'id': instance.id,
      'type': instance.type,
      'depth': instance.depth,
      'description': ?instance.description,
      'source': ?instance.source,
      'local': instance.local,
      'offstage': ?instance.offstage,
      'rect': ?instance.rect,
      'constraints': ?instance.constraints,
      'flex': ?instance.flex,
      'flexChild': ?instance.flexChild,
    };

Map<String, dynamic> _$CatalogRenderErrorToJson(CatalogRenderError instance) =>
    <String, dynamic>{
      'exception': instance.exception,
      'library': ?instance.library,
      'context': ?instance.context,
      'count': instance.count,
    };

Map<String, dynamic> _$CatalogInspectResultToJson(
  CatalogInspectResult instance,
) => <String, dynamic>{
  'entry': instance.entry,
  'address': instance.address,
  'readFrom': instance.readFrom,
  'ok': instance.ok,
  'errors': instance.errors.map((e) => e.toJson()).toList(),
  'lens': instance.lens,
  'screen': ?instance.screen?.toJson(),
  'styles': ?instance.styles?.map((e) => e.toJson()).toList(),
  'nodes': ?instance.nodes,
  'tree': ?instance.tree?.map((e) => e.toJson()).toList(),
  'find': ?instance.find?.map((e) => e.toJson()).toList(),
  'at': ?instance.at?.map((e) => e.toJson()).toList(),
  'atOuterElided': ?instance.atOuterElided,
  'logs': ?instance.logs,
  'logsDropped': ?instance.logsDropped,
  'screenshot': ?instance.screenshot?.toJson(),
  'next': ?instance.next,
};

Map<String, dynamic> _$CatalogAuditResultToJson(CatalogAuditResult instance) =>
    <String, dynamic>{
      'checked': instance.checked,
      'broken': instance.broken,
      'entries': instance.entries.map((e) => e.toJson()).toList(),
      'unreachable': instance.unreachable.map((e) => e.toJson()).toList(),
    };

Map<String, dynamic> _$CatalogAuditEntryToJson(CatalogAuditEntry instance) =>
    <String, dynamic>{
      'id': instance.id,
      'address': instance.address,
      'compiles': instance.compiles,
      'compileError': ?instance.compileError,
      'errors': instance.errors.map((e) => e.toJson()).toList(),
    };

Map<String, dynamic> _$CatalogAuditFailureToJson(
  CatalogAuditFailure instance,
) => <String, dynamic>{'package': instance.package, 'error': instance.error};

Map<String, dynamic> _$CatalogWebBuildResultToJson(
  CatalogWebBuildResult instance,
) => <String, dynamic>{
  'package': instance.package,
  'output': instance.output,
  'indexHtml': instance.indexHtml,
  'entries': instance.entries,
  'durationMs': instance.durationMs,
};

Map<String, dynamic> _$ComparisonCompareResultToJson(
  ComparisonCompareResult instance,
) => <String, dynamic>{
  'against': instance.against,
  'baseSha': instance.baseSha,
  'counts': instance.counts,
  'findings': instance.findings.map((e) => e.toJson()).toList(),
  'index': instance.index,
  'export': ?instance.export,
  'report': ?instance.report,
  'scenariosNote': ?instance.scenariosNote,
};

Map<String, dynamic> _$ComparisonFindingToJson(ComparisonFinding instance) =>
    <String, dynamic>{
      'id': instance.id,
      'half': instance.half,
      'state': instance.state,
      'note': ?instance.note,
      'delta': ?instance.delta,
    };
