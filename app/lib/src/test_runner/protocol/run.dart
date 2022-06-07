import 'dart:convert';
import 'package:rxdart/rxdart.dart';
import 'package:flutter_studio/internals/test_runner.dart';

class RunHost {
  final Channel _channel;
  final _currentRuns = <int, RunReference>{};

  RunHost(Connection connection)
      : _channel = connection.createChannel('TestRun') {
    _channel.registerMethod('addScreen', _addScreen);
    _channel.registerMethod('complete', _onCompleted);
  }

  RunReference start(RunArgs args) {
    var run = RunReference(args, this);
    _currentRuns[args.id] = run;
    _channel.sendRequest<ScenarioRun>('create', args).then((r) {
      run._scenario.add(r);
      _channel.sendRequest('execute', args);
    }).onError((e, stackTrace) {
      // Finish the run early
      run._completeWithError(e!);
    });

    return run;
  }

  void _addScreen(RunArgs args, NewScreen newScreen) {
    var run = _currentRuns[args.id];
    if (run == null) {
      // The UI has changed page
      return;
    }

    run._rebuild((run) {
      var screen = newScreen.screen.rebuild((s) {
        var image = newScreen.imageBase64;
        if (image != null) {
          s.imageBytes = base64Decode(image);
        }
      });
      run.screens[screen.id] = screen;
      var parentId = newScreen.parent;
      if (parentId != null) {
        var parent = run.screens[parentId]!;
        run.screens[parentId] = parent.rebuild((parentBuilder) {
          parentBuilder.next.add(
            ScreenLink(screen.id).rebuild((r) {
              var parentRectangle = newScreen.parentRectangle;
              if (parentRectangle != null) {
                r.tapRect.replace(parentRectangle);
              }
              var analyticEvent = newScreen.analyticEvent;
              if (analyticEvent != null) {
                r.analytic.replace(analyticEvent);
              }
            }),
          );
        });
      }
    });
  }

  void _onCompleted(RunArgs args, RunResult result) {
    var run = _currentRuns[args.id];
    if (run == null) return;

    run._rebuild((run) {
      run.result.replace(result);
    });
  }

  void dispose() {}
}

class RunReference {
  final RunArgs args;
  final RunHost _host;
  final _scenario = BehaviorSubject<ScenarioRun>();

  RunReference(this.args, this._host);

  ScenarioRun? get value => _scenario.valueOrNull;
  Stream<ScenarioRun> get onUpdated => _scenario.stream;

  void _rebuild(void Function(ScenarioRunBuilder) updates) {
    var scenario = _scenario.value;
    scenario = scenario.rebuild(updates);
    _scenario.add(scenario);
  }

  void _completeWithError(Object error) {
    _scenario.addError(error);
  }

  void dispose() {
    _scenario.close();
    _host._currentRuns.remove(args.id);
  }
}
