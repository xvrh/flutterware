import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'test_reference.g.dart';

abstract class TestReference
    implements Built<TestReference, TestReferenceBuilder> {
  static Serializer<TestReference> get serializer =>
      _$testReferenceSerializer;

  factory TestReference._builder(
      [void Function(TestReferenceBuilder)? updates]) = _$TestReference;
  TestReference._();

  factory TestReference(Iterable<String> name, {String? description}) =>
      TestReference._builder((b) => b
        ..name.replace(name)
        ..description = description);

  BuiltList<String> get name;
  String? get description;
}
