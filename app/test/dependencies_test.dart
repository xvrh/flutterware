import 'package:flutterware_app/src/dependencies/model/dependency_graph.dart';
import 'package:test/test.dart';

/// The map in each case is *dependants*: `'http': {'sample'}` reads as "sample
/// depends on http", so walking it goes up towards whatever pulled a package in.
void main() {
  test('chains run root-first and shortest-first', () {
    var packages = <String, Set<String>>{
      'analyzer': {'sample', 'http', 'path', 'build_value'},
      'http': {'sample'},
      'path': {'http', 'sample'},
      'sample': {},
      'build_value': {},
      'other': {'analyzer'},
    };

    var graphs = shortestDependencyPaths('analyzer', (e) => packages[e]!);

    // Breadth-first, so the direct explanations come out before the scenic
    // ones. The old depth-first version returned the same set in an order
    // nobody could predict.
    expect(graphs, [
      ['sample', 'analyzer'],
      ['build_value', 'analyzer'],
      ['sample', 'http', 'analyzer'],
      ['sample', 'path', 'analyzer'],
      ['sample', 'http', 'path', 'analyzer'],
    ]);
  });

  test('a cycle terminates instead of spinning', () {
    var packages = <String, Set<String>>{
      'A': {'B', 'C'},
      'C': {'D'},
      'D': {'B'},
    };

    var graphs = shortestDependencyPaths('A', (e) => packages[e] ?? {});
    expect(graphs, [
      ['B', 'A'],
      ['B', 'D', 'C', 'A'],
    ]);
  });

  test('stops at the limit rather than enumerating everything', () {
    // A fan-out wide enough that the unbounded depth-first version was
    // exponential — and it was being called from inside a Tooltip's build.
    var dependants = {
      for (var i = 0; i < 8; i++) 'p$i': {for (var j = 0; j < 8; j++) 'q$j'},
    };

    var graphs = shortestDependencyPaths(
      'p0',
      (e) => dependants[e] ?? {},
      limit: 3,
    );
    expect(graphs, hasLength(3));
    for (var path in graphs) {
      expect(path.last, 'p0');
    }
  });

  test('a package nothing depends on is its own chain', () {
    expect(shortestDependencyPaths('lonely', (_) => {}), [
      ['lonely'],
    ]);
  });
}
