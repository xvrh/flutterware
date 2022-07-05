import 'dart:async';
import 'package:built_collection/built_collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart' as flutter;
import 'package:flutterware/src/test_runner/runtime/run_context.dart';
import 'package:logging/logging.dart';
import 'package:pool/pool.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../api.dart';
import '../protocol/connection.dart';
import '../protocol/domains/listing.dart';
import '../protocol/domains/project.dart';
import '../protocol/domains/run.dart';
import '../protocol/models.dart';
import 'asset_bundle.dart';
import 'binding.dart';
import 'fonts.dart';
import 'list_tests.dart';
import 'run_group.dart';
import 'package:test_api/src/backend/group.dart'; // ignore: implementation_imports

final _logger = Logger('runner');

StreamChannel<String> connectToServer(Uri serverUri) {
  return WebSocketChannel.connect(serverUri).cast<String>();
}

typedef TestCallback = Future<void> Function(WidgetTester);

/// The class responsible to hold all the tests and coordinate the communication
/// with the server.
class Runner {
  final StreamChannel<String> Function() connectionFactory;
  final Map<String, void Function()> Function() mainFunctions;
  final ProjectInfo project;
  late final ScenarioBinding _binding;
  final void Function()? onConnected;
  ProjectClient? _project;
  RunClient? _runClient;
  final Future<ScenarioBundle> Function() _bundleFactory;
  late final ScenarioBundle _bundle;

  Runner(this.connectionFactory,
      {required this.mainFunctions,
      required this.project,
      required Future<ScenarioBundle> Function() bundle,
      this.onConnected})
      : _bundleFactory = bundle {
    FlutterError.onError = (error) {
      _logger.severe('FLUTTER ERROR: $error');
    };

    _binding = ScenarioBinding(onReloaded: notifyReloaded);
  }

  ScenarioBundle get bundle => _bundle;

  ScenarioBinding get binding => _binding;

  Future<void> run() async {
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
    flutter.WidgetController.hitTestWarningShouldBeFatal = true;
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
    ListingClient(connection, list: () {
      var allMains = mainFunctions();
      return listTests(allMains);
    });
    _runClient =
        RunClient(connection, create: _createRun, execute: _executeRun);

    _logger.warning('Connected to server');
    onConnected?.call();
  }

  void notifyReloaded() {
    _project?.notifyReloaded();
  }

  @override
  Future<void> addScreen(RunArgs run, NewScreen screen) =>
      _runClient!.addScreen(run, screen);

  Group? _findTest(Map<String, void Function()> tests, BuiltList<String> name) {
    return findTest(tests, name.join(' '));
  }

  final _currentScenario = <RunArgs, Group>{};

  ScenarioRun _createRun(RunArgs args) {
    _logger.fine('RunTest ${args.scenarioName.join('/')}');
    var allMains = mainFunctions();
    var scenario = _findTest(allMains, args.scenarioName);
    if (scenario == null) {
      throw Exception('No test ${args.scenarioName.join('/')} found.');
    }

    var run = ScenarioRun(ScenarioReference(args.scenarioName), args);
    _currentScenario[args] = scenario;
    return run;
  }

  final _runPool = Pool(1);
  void _executeRun(RunArgs args) {
    var runClient = _runClient!;
    var scenario = _currentScenario[args]!;

    _runPool.withResource(() async {
      var stopwatch = Stopwatch()..start();
      Object? error;
      StackTrace? stackTrace;
      try {
        var runClient = _runClient!;
        var runContext = RunContext(args,
            addScreen: (screen) => runClient.addScreen(args, screen));
        await runZonedGuarded(
          () async {
            await runGroup(scenario).toList();
          },
          zoneValues: {#runContext: runContext},
          (e, s) {
            error = e;
            stackTrace = s;
            _logger.warning('Zone error $e $s');
          },
        );
      } catch (e, s) {
        _logger.warning('Failed to run test', e);
        error = e;
        stackTrace = s;
      } finally {
        RunResult result;
        if (error != null) {
          result = RunResult.error(error!, stackTrace);
        } else {
          result = RunResult.success();
        }

        result = result.rebuild((b) => b..duration = stopwatch.elapsed);
        await runClient.complete(args, result);
        _logger.finer('End test ${args.scenarioName} in ${stopwatch.elapsed}');
        _currentScenario.remove(args);
      }
    });
  }
}
