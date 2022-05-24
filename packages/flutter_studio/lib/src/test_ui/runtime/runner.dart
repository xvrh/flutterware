import 'dart:async';
import 'package:built_collection/built_collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:pool/pool.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../protocol/connection.dart';
import '../protocol/domains/listing.dart';
import '../protocol/domains/project.dart';
import '../protocol/domains/run.dart';
import '../protocol/models.dart';
import 'asset_bundle.dart';
import 'binding.dart';
import 'fonts.dart';
import 'scenario.dart';

final _logger = Logger('runner');

//TODO(xha): This should try to connect permanently to the server when connection
// is lost (ie due to hot-restart of app). => rearchitecture
StreamChannel<String> connectToServer(Uri serverUri) {
  return WebSocketChannel.connect(serverUri).cast<String>();
}

/// The class responsible to hold all the tests and coordinate the communication
/// with the server.
class Runner implements RunContext {
  final StreamChannel<String> Function() connectionFactory;
  final Map<String, dynamic> Function() scenarios;
  final ProjectInfo project;
  late final ScenarioBinding _binding;
  final void Function()? onConnected;
  final _runPool = Pool(1);
  ProjectClient? _project;
  RunClient? _runClient;
  final Future<ScenarioBundle> Function() _bundleFactory;
  late final ScenarioBundle _bundle;

  Runner(this.connectionFactory,
      {required this.scenarios,
      required this.project,
      required Future<ScenarioBundle> Function() bundle,
      this.onConnected})
      : _bundleFactory = bundle {
    FlutterError.onError = (error) {
      _logger.severe('FLUTTER ERROR: $error');
    };

    _binding = ScenarioBinding(onReloaded: notifyReloaded);
    _setup();
  }

  ScenarioBundle get bundle => _bundle;

  ScenarioBinding get binding => _binding;

  Future<void> _setup() async {
    _bundle = await _bundleFactory();

    if (!kIsWeb) {
      await loadFonts({
        // TODO(xha): allow to toggle this from the UI. We want to see if all
        // the texts in the app correctly use the overriden font. Instead of loading
        // the correct font, we load the Ahem Font.
        // Be aware: it requires a full restart on the client side (ctrl+c | stop + restart)
        // to have the previous fonts unloaded.
        //'Work Sans': await ahemFont,
      });
    }
    await loadAppFonts(bundle);
    WidgetController.hitTestWarningShouldBeFatal = true;
    WidgetsApp.debugAllowBannerOverride = false;
    _startConnection();
  }

  void _startConnection() {
    _logger.info('Start connecting to server');
    var channel = connectionFactory();
    var connection = Connection(channel, modelSerializers);
    connection.listen(onClose: () {
      _project = null;
      _runClient = null;
      _logger.warning('Connection to server closed');
      Timer(const Duration(milliseconds: 1000), _startConnection);
    });
    _onConnected(connection);
  }

  void _onConnected(Connection connection) {
    _project = ProjectClient(connection, load: () => project);
    ListingClient(connection, list: _list);
    _runClient =
        RunClient(connection, create: _createRun, execute: _executeRun);

    onConnected?.call();
  }

  void notifyReloaded() {
    _project?.notifyReloaded();
  }

  Iterable<ScenarioReference> _list() {
    var allScenario = scenarios();
    return _listScenarios([], allScenario);
  }

  Iterable<ScenarioReference> _listScenarios(
      List<String> parents, Map<String, dynamic> scenarios) sync* {
    for (var entry in scenarios.entries) {
      var value = entry.value;
      var name = [...parents, entry.key];
      if (value is Scenario) {
        yield ScenarioReference(name, description: value.description);
      } else if (value is Map<String, dynamic>) {
        yield* _listScenarios(name, value);
      } else {
        throw StateError(
            'Scenarios map should only contains Scenario or Map<String, dynamic>');
      }
    }
  }

  @override
  Future<void> addScreen(RunArgs run, NewScreen screen) =>
      _runClient!.addScreen(run, screen);

  Scenario? _findScenario(
      Map<String, dynamic> scenarios, BuiltList<String> name) {
    for (var namePart in name) {
      var value = scenarios[namePart];
      if (value is Scenario) {
        return value;
      } else if (value is Map<String, dynamic>) {
        scenarios = value;
      }
    }
    return null;
  }

  final _currentScenario = <RunArgs, Scenario>{};
  ScenarioRun _createRun(RunArgs args) {
    _logger.fine('RunScenario ${args.scenarioName.join('/')}');
    var allScenario = scenarios();
    var scenario = _findScenario(allScenario, args.scenarioName);
    if (scenario == null) {
      throw Exception('No scenario ${args.scenarioName.join('/')} found.');
    }

    var run = ScenarioRun(
        ScenarioReference(args.scenarioName, description: scenario.description),
        args);
    _currentScenario[args] = scenario;
    return run;
  }

  void _executeRun(RunArgs args) {
    var runClient = _runClient!;
    var scenario = _currentScenario[args]!;

    _runPool.withResource(() async {
      var stopwatch = Stopwatch()..start();
      late RunResult result;
      try {
        var zoneError =
            await scenario.execute(this, binding, bundle, project, args);
        if (zoneError == null) {
          result = RunResult.success();
        } else {
          result = RunResult.error(zoneError, null);
        }
      } catch (e, stackTrace) {
        _logger.warning('Failed to run scenario', e);
        result = RunResult.error(e, stackTrace);
      } finally {
        result = result.rebuild((b) => b..duration = stopwatch.elapsed);
        await runClient.complete(args, result);
        _logger
            .finer('End scenario ${args.scenarioName} in ${stopwatch.elapsed}');
        _currentScenario.remove(args);
      }
    });
  }
}
