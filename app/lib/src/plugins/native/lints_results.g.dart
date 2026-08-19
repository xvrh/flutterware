// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'lints_results.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Map<String, dynamic> _$LintsStatusResultToJson(LintsStatusResult instance) =>
    <String, dynamic>{
      'dartVersion': ?instance.dartVersion,
      'catalogAvailable': instance.catalogAvailable,
      'universe': instance.universe,
      'files': instance.files.map((e) => e.toJson()).toList(),
      'rules': instance.rules.map((e) => e.toJson()).toList(),
      'unknownNames': instance.unknownNames,
      'pricing': ?instance.pricing?.toJson(),
    };

Map<String, dynamic> _$LintsFileSummaryToJson(LintsFileSummary instance) =>
    <String, dynamic>{
      'path': instance.path,
      'includeChain': instance.includeChain,
      'inheritsNothing': instance.inheritsNothing,
      'includeErrors': instance.includeErrors,
      'configured': instance.configured,
      'enabled': instance.enabled,
    };

Map<String, dynamic> _$LintsRuleEntryToJson(LintsRuleEntry instance) =>
    <String, dynamic>{
      'name': instance.name,
      'bucket': instance.bucket,
      'since': ?instance.since,
      'state': ?instance.state,
      'fix': ?instance.fix,
      'description': ?instance.description,
      'enabledVia': ?instance.enabledVia,
      'comment': ?instance.comment,
      'files': instance.files,
      'incompatible': instance.incompatible,
      'price': ?instance.price,
    };

Map<String, dynamic> _$LintsPricingSummaryToJson(
  LintsPricingSummary instance,
) => <String, dynamic>{
  'at': instance.at,
  'elapsedMs': instance.elapsedMs,
  'freeWins': instance.freeWins,
  'stale': instance.stale,
};

Map<String, dynamic> _$LintsPriceResultToJson(LintsPriceResult instance) =>
    <String, dynamic>{
      'candidates': instance.candidates,
      'freeWins': instance.freeWins,
      'elapsedMs': instance.elapsedMs,
      'counts': instance.counts,
    };
