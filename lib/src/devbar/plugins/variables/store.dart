abstract class VariablesStore {
  Object? operator [](String key);
  void operator []=(String key, Object? value);
  List<String> get keys;
}

class InMemoryVariablesStore implements VariablesStore {
  final data = <String, Object?>{};

  @override
  Object? operator [](String key) => data[key];

  @override
  void operator []=(String key, Object? value) {
    data[key] = value;
  }

  @override
  List<String> get keys => data.keys.toList();
}
