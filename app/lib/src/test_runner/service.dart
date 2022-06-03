import 'package:flutter/foundation.dart';
import 'package:rxdart/rxdart.dart';

import 'protocol/api.dart';

class TestService {
  final _state = ValueNotifier<DaemonState>(DaemonState$Initial());

  ValueListenable<DaemonState> get state => _state;

  void ensureStarted() {
    if (_state.value is DaemonState$Initial) {
      start();
    }
  }

  void start() async {
    assert(_state.value is DaemonState$Initial || _state.value is DaemonState$Stopped);
    _state.value = DaemonState$Starting('');

    try {

    } catch (e) {

    }
  }

  void stop() {}
}

class DaemonState {

}

class DaemonState$Initial implements DaemonState {
}

class DaemonState$Starting implements DaemonState {
  final String logs;

  DaemonState$Starting(this.logs);
}
class DaemonState$Stopped implements DaemonState {
  final Object? error;

  DaemonState$Stopped({this.error});

}
class DaemonState$Connected implements DaemonState {
  final TestDaemon daemon;

  DaemonState$Connected(this.daemon);
}

class TestDaemon {

}
