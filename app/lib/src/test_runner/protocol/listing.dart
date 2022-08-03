import 'package:built_collection/built_collection.dart';
import '../runtime.dart';
import 'package:rxdart/rxdart.dart';

class ListingHost {
  final Channel _channel;
  final allTests =
      BehaviorSubject<BuiltMap<BuiltList<String>, TestReference>>.seeded(
          BuiltMap());

  ListingHost(Connection connection)
      : _channel = connection.createChannel('Listing');

  void list() async {
    var result =
        (await _channel.sendRequest<BuiltList>('list')).cast<TestReference>();

    var oldMap = allTests.value;
    var newTests = oldMap.rebuild((b) {
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
    allTests.add(newTests);
  }

  void dispose() {
    allTests.close();
  }
}
