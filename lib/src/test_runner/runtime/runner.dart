import 'dart:async';
import 'package:built_collection/built_collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart' as flutter;
import 'package:logging/logging.dart';
import 'package:pool/pool.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:test_api/src/backend/group.dart'; // ignore: implementation_imports
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
import 'run_context.dart';
import 'run_group.dart';

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
  late final TestBinding _binding;
  final void Function()? onConnected;
  ProjectClient? _project;
  RunClient? _runClient;
  final Future<TestBundle> Function() _bundleFactory;
  late final TestBundle _bundle;

  Runner(this.connectionFactory,
      {required this.mainFunctions,
      required Future<TestBundle> Function() bundle,
      this.onConnected})
      : _bundleFactory = bundle {
    FlutterError.onError = (error) {
      _logger.severe('FLUTTER ERROR: $error');
    };

    _binding = TestBinding(onReloaded: notifyReloaded);
  }

  TestBundle get bundle => _bundle;

  TestBinding get binding => _binding;

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
    _project = ProjectClient(connection);
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

  Group? _findTest(Map<String, void Function()> tests, BuiltList<String> name) {
    return findTest(tests, name.join(' '));
  }

  final _currentTest = <RunArgs, Group>{};

  TestRun _createRun(RunArgs args) {
    _logger.fine('RunTest ${args.testName.join('/')}');
    var allMains = mainFunctions();
    var test = _findTest(allMains, args.testName);
    if (test == null) {
      throw Exception('No test ${args.testName.join('/')} found.');
    }

    var run = TestRun(TestReference(args.testName), args);
    _currentTest[args] = test;
    return run;
  }

  final _runPool = Pool(1);
  void _executeRun(RunArgs args) {
    var test = _currentTest[args]!;

    _runPool.withResource(() async {
      var stopwatch = Stopwatch()..start();

      FlutterErrorDetails? error;
      reportTestException = (errorDetails, testDescription) {
        error = errorDetails;
        _logger.severe('Test error $errorDetails');
      };

      var runClient = _runClient!;
      var runContext = RunContext(args,
          addScreen: (screen) => runClient.addScreen(args, screen));
      await runZonedGuarded(
        () async => await runGroup(test),
        zoneValues: {#runContext: runContext},
        (error, stack) {
          _logger.info('Zone error $error');
        },
      );

      RunResult result;
      if (error != null) {
        var errorDetails = error!;
        result = RunResult.error(errorDetails.exception, errorDetails.stack);
      } else {
        result = RunResult.success();
      }

      result = result.rebuild((b) => b..duration = stopwatch.elapsed);
      await runClient.complete(args, result);
      _logger.info('End test ${args.testName} in ${stopwatch.elapsed}');
      _currentTest.remove(args);
    });
  }
}
