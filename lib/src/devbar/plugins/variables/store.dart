abstract class VariablesStore {
  Object? operator [](String key);
  void save(Map<String, Object> data);
}

class InMemoryVariablesStore implements VariablesStore {
  final data = <String, Object>{};

  @override
  Object? operator [](String key) => data[key];

  @override
  void save(Map<String, Object> data) {
    this.data
      ..clear()
      ..addAll(data);
  }
}
