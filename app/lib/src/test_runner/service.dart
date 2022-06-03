import 'package:rxdart/rxdart.dart';

import 'protocol/api.dart';

class TestService {
  final ValueStream<List<TestRunnerApi>> clients;

  TestService(this.clients);
}
