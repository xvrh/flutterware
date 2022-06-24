import 'dart:async';
import 'dart:convert';

import 'package:json_annotation/json_annotation.dart';
import 'package:logging/logging.dart';

import 'commands.dart';
import 'events.dart';

part 'protocol.g.dart';

final _logger = Logger('daemon_protocol');

@JsonSerializable(createFactory: false)
class Method {
  final String method;
  final int id;
  final Map<String, dynamic> params;

  Method(this.method, this.id, this.params);

  Map<String, dynamic> toJson() => _$MethodToJson(this);
}

class DaemonProtocol {
  final StringSink write;
  final Stream<String> read;
  final _eventController = StreamController<Event>.broadcast();
  late StreamSubscription _subscription;
  final _inFlightCommands = <int, _InFlightCommand>{};
  int _commandId = 0;

  DaemonProtocol(this.write, this.read) {
    _subscription = read.listen((event) {
      _logger.finer('Daemon: $event');
      if (event.startsWith('[{') && event.endsWith('}]')) {
        var content = jsonDecode(event) as List;
        var object = content.first as Map<String, dynamic>;
        var eventName = object['event'] as String?;
        if (eventName != null) {
          var params = object['params'] as Map<String, dynamic>;
          var decodedEvent = Event.decode(eventName, params);
          if (decodedEvent != null) {
            _eventController.add(decodedEvent);
          }
        } else {
          var id = object['id'] as int?;
          if (id != null) {
            var result = object['result'];
            var inflight = _inFlightCommands.remove(id);
            if (inflight != null) {
              inflight.complete(result);
            }
          }
        }
      }
    }, onDone: () {
      _eventController.close();
    });
  }

  Stream<Event> get onEvent => _eventController.stream;

  Future<TResult> sendCommand<TResult>(Command<TResult> command) {
    var id = _commandId++;
    var inflight = _inFlightCommands[id] = _InFlightCommand<TResult>(command);
    _write(Method(command.methodName, id, command.toJson()));
    return inflight.completer.future;
  }

  void _write(Object object) {
    write.writeln('[${jsonEncode(object)}]');
  }

  void close() {
    _subscription.cancel();
    _eventController.close();
  }
}

class _InFlightCommand<TResult> {
  final Command<TResult> command;
  final completer = Completer<TResult>();

  _InFlightCommand(this.command);

  void complete(Object? result) {
    var decoded = command.decodeResult(result);
    completer.complete(decoded);
  }
}
