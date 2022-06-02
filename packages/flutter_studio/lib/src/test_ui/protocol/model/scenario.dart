import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'scenario.g.dart';

abstract class ScenarioReference
    implements Built<ScenarioReference, ScenarioReferenceBuilder> {
  static Serializer<ScenarioReference> get serializer =>
      _$scenarioReferenceSerializer;

  factory ScenarioReference._builder(
      [void Function(ScenarioReferenceBuilder)? updates]) = _$ScenarioReference;
  ScenarioReference._();

  factory ScenarioReference(Iterable<String> name, {String? description}) =>
      ScenarioReference._builder((b) => b
        ..name.replace(name)
        ..description = description);

  BuiltList<String> get name;
  String? get description;
}
