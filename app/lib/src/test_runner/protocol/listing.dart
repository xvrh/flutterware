import 'package:built_collection/built_collection.dart';
import 'package:rxdart/rxdart.dart';
import 'package:flutterware/internals/test_runner.dart';

class ListingHost {
  final Channel _channel;
  final allScenarios =
      BehaviorSubject<BuiltMap<BuiltList<String>, ScenarioReference>>.seeded(
          BuiltMap());

  ListingHost(Connection connection)
      : _channel = connection.createChannel('Listing');

  void list() async {
    var result = (await _channel.sendRequest<BuiltList>('list'))
        .cast<ScenarioReference>();

    var oldMap = allScenarios.value;
    var newScenarios = oldMap.rebuild((b) {
      b.clear();
      for (var newEntry in result) {
        var oldEntry = oldMap[newEntry.name];
        if (oldEntry != null) {
          b[newEntry.name] =
              oldEntry.rebuild((b) => b..description = newEntry.description);
        } else {
          b[newEntry.name] = newEntry;
        }
      }
    });
    allScenarios.add(newScenarios);
  }

  void dispose() {
    allScenarios.close();
  }
}
