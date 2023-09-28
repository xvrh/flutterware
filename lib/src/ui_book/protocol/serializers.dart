import 'package:built_value/serializer.dart';
import 'models.dart';

part 'serializers.g.dart';

@SerializersFor([
  ScreenConfiguration,
])
final Serializers modelSerializers = _$modelSerializers;
