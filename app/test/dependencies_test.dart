import 'package:flutterware_app/src/dependencies/model/dependency_graph.dart';
import 'package:test/test.dart';

void main() {
  test('Compute dependencies graph', () {
    var packages = <String, Set<String>>{
      'analyzer': {'sample', 'http', 'path', 'build_value'},
      'http': {'sample'},
      'path': {'http', 'sample'},
      'sample': {},
      'build_value': {},
      'other': {'analyzer'},
    };

    var graphs = dependenciesGraph('analyzer', (e) => packages[e]!);
    expect(graphs, [
      ['sample', 'analyzer'],
      ['sample', 'http', 'analyzer'],
      ['sample', 'http', 'path', 'analyzer'],
      ['sample', 'path', 'analyzer'],
      ['build_value', 'analyzer'],
    ]);
  });

  test('Handle cyclic dependencies', () {
    var packages = <String, Set<String>>{
      'A': {'B', 'C'},
      'C': {'D'},
      'D': {'B'},
    };

    var graphs = dependenciesGraph('A', (e) => packages[e] ?? {});
    expect(graphs, [
      ['B', 'A'],
      ['B', 'D', 'C', 'A']
    ]);
  });
}
