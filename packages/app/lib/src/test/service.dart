import 'package:rxdart/rxdart.dart';

import 'protocol/api.dart';

class ScenarioService {
  final ValueStream<List<ScenarioApi>> clients;

  ScenarioService(this.clients);
}
