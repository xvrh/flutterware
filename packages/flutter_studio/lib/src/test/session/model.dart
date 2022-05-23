import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'model.g.dart';

@SerializersFor([
  RunStartCommand,
  RunStopCommand,
])
final Serializers serializers = _$serializers;

abstract class RunStartCommand implements Built<RunStartCommand, RunStartCommandBuilder> {
  RunStartCommand._();
  factory RunStartCommand([void Function(RunStartCommandBuilder) updates]) = _$RunStartCommand;
}

abstract class RunStopCommand implements Built<RunStopCommand, RunStopCommandBuilder> {
  RunStopCommand._();
  factory RunStopCommand([void Function(RunStopCommandBuilder) updates]) = _$RunStopCommand;
}


