import 'dart:convert';
import '../connection.dart';
import '../models.dart';

class RunClient {
  final Channel _channel;

  RunClient(
    Connection connection, {
    required ScenarioRun Function(RunArgs) create,
    required void Function(RunArgs) execute,
  }) : _channel = connection.createChannel('ScenarioRun') {
    _channel.registerMethod('create', create);
    _channel.registerMethod('execute', execute);
  }

  Future<void> addScreen(RunArgs args, NewScreen screen) async {
    await _channel.sendRequest('addScreen', args, screen);
  }

  Future<void> complete(RunArgs args, RunResult result) async {
    await _channel.sendRequest('complete', args, result);
  }
}
