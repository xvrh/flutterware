import 'package:built_collection/built_collection.dart';
import '../connection.dart';
import '../models.dart' show TestReference;

class ListingClient {
  final Channel channel;
  final Iterable<TestReference> Function() list;

  ListingClient(Connection connection, {required this.list})
      : channel = connection.createChannel('Listing') {
    channel.registerMethod('list', _list);
  }

  BuiltList<TestReference> _list() {
    var result = BuiltList<TestReference>(list());
    return result;
  }
}
