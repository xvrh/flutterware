import 'dart:async';
import 'package:built_collection/built_collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart' as flutter;
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
import 'scenario.dart';
import 'package:test_api/src/backend/group.dart';

import 'widget_tester.dart'; // ignore: implementation_imports

final _logger = Logger('runner');

StreamChannel<String> connectToServer(Uri serverUri) {
  return WebSocketChannel.connect(serverUri).cast<String>();
}

typedef TestCallback = Future<void> Function(WidgetTester);

/// The class responsible to hold all the tests and coordinate the communication
/// with the server.
class Runner implements RunContext {
  final StreamChannel<String> Function() connectionFactory;
  final Map<String, void Function()> Function() tests;
  final ProjectInfo project;
  late final ScenarioBinding _binding;
  final void Function()? onConnected;
  final _runPool = Pool(1);
  ProjectClient? _project;
  RunClient? _runClient;
  final Future<ScenarioBundle> Function() _bundleFactory;
  late final ScenarioBundle _bundle;

  Runner(this.connectionFactory,
      {required this.tests,
      required this.project,
      required Future<ScenarioBundle> Function() bundle,
      this.onConnected})
      : _bundleFactory = bundle {
    //FlutterError.onError = (error) {
    //  _logger.severe('FLUTTER ERROR: $error');
    //};

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
    ListingClient(connection, list: _list);
    _runClient =
        RunClient(connection, create: _createRun, execute: _executeRun);

    _logger.warning('Connected to server');
    onConnected?.call();
  }

  void notifyReloaded() {
    _project?.notifyReloaded();
  }

  Iterable<ScenarioReference> _list() {
    var allTests = tests();
    return listTests(allTests);
  }

  late RunArgs _currentRun;

  AssetBundle get assetBundle => _bundle;

  RunArgs get args => _currentRun;

  @override
  Future<void> addScreen(/*RunArgs run,*/ NewScreen screen) =>
      _runClient!.addScreen(_currentRun, screen);

  Group? _findTest(Map<String, void Function()> tests, BuiltList<String> name) {
    return findTest(tests, name.join(' '));
    /*for (var namePart in name) {
      var value = tests[namePart];
      if (value is TestCallback) {
        return value;
      } else if (value is Map<String, dynamic>) {
        tests = value;
      } else {
        _logger.severe('Unsupported test type $value');
      }
    }
    return null;*/
  }

  final _currentScenario = <RunArgs, Group>{};

  ScenarioRun _createRun(RunArgs args) {
    _logger.fine('RunTest ${args.scenarioName.join('/')}');
    var allScenario = tests();
    var scenario = _findTest(allScenario, args.scenarioName);
    if (scenario == null) {
      throw Exception('No test ${args.scenarioName.join('/')} found.');
    }

    var run = ScenarioRun(ScenarioReference(args.scenarioName), args);
    _currentScenario[args] = scenario;
    return run;
  }

  void _executeRun(RunArgs args) {
    var runClient = _runClient!;
    var scenario = _currentScenario[args]!;
    _currentRun = args;
    runContext = this;

    _runPool.withResource(() async {
      var stopwatch = Stopwatch()..start();
      Object? error;
      StackTrace? stackTrace;
      try {
        await runZonedGuarded(() async {
          await runGroup(scenario).toList();
        }, (e, s) {
          error = e;
          stackTrace = s;
          _logger.warning('Zone error $e $s');
        });
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
