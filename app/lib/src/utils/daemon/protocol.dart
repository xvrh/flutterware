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
    _subscription = read.listen(
      (event) {
        _logger.finer('Daemon: $event');
        var object = tryReadLine(event);
        if (object != null) {
          var decodedEvent = tryReadEvent(object);
          if (decodedEvent != null) {
            _eventController.add(decodedEvent);
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
      },
      onDone: () {
        _eventController.close();
      },
    );
  }

  static Map<String, dynamic>? tryReadLine(String line) {
    if (line.startsWith('[{') && line.endsWith('}]')) {
      var content = jsonDecode(line) as List;
      return content.first as Map<String, dynamic>;
    }
    return null;
  }

  /// The event [object] carries, or null when there is none to read.
  ///
  /// Decoding failures are swallowed, deliberately. This runs inside the
  /// stdout subscription, so a throw here does not fail one event — it takes
  /// the whole subscription down and the daemon goes silent for the rest of
  /// its life. The flutter tool is not a protocol we version, and it has
  /// already added a log level we did not know about; the next addition must
  /// cost one dropped event, not the connection.
  static Event? tryReadEvent(Map<String, dynamic> object) {
    var eventName = object['event'] as String?;
    if (eventName == null) return null;
    try {
      var params = object['params'] as Map<String, dynamic>;
      return Event.decode(eventName, params);
    } on Object catch (e) {
      _logger.warning('Could not decode a "$eventName" daemon event: $e');
      return null;
    }
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
