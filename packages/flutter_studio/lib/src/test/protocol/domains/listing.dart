import 'package:built_collection/built_collection.dart';
import '../connection.dart';
import '../models.dart' show ScenarioReference;

class ListingClient {
  final Channel channel;
  final Iterable<ScenarioReference> Function() list;

  ListingClient(Connection connection, {required this.list})
      : channel = connection.createChannel('Listing') {
    channel.registerMethod('list', _list);
  }

  BuiltList<ScenarioReference> _list() {
    var result = BuiltList<ScenarioReference>(list());
    return result;
  }
}
