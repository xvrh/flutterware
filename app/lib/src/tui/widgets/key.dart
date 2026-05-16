part of 'widgets.dart';

/// An identifier for a [Widget], used by [Widget.canUpdate] and child
/// reconciliation to match a widget to an existing element.
abstract class Key {
  const factory Key(String value) = ValueKey<String>;
  const Key._();
}

/// A [Key] scoped to its parent. The only key family in stage 4 (no GlobalKey).
abstract class LocalKey extends Key {
  const LocalKey() : super._();
}

/// A [LocalKey] backed by a value of type [T]; equal when type and value match.
class ValueKey<T> extends LocalKey {
  const ValueKey(this.value);
  final T value;

  @override
  bool operator ==(Object other) =>
      other is ValueKey<T> && other.value == value;

  @override
  int get hashCode => Object.hash(runtimeType, value);
}

/// A [LocalKey] backed by object identity.
class ObjectKey extends LocalKey {
  const ObjectKey(this.value);
  final Object? value;

  @override
  bool operator ==(Object other) =>
      other is ObjectKey && identical(other.value, value);

  @override
  int get hashCode => Object.hash(runtimeType, identityHashCode(value));
}

/// A [LocalKey] equal only to itself.
class UniqueKey extends LocalKey {
  UniqueKey();
}
