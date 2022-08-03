import 'dart:convert';
import 'package:rxdart/rxdart.dart';
import '../runtime.dart';

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
    _channel.sendRequest<TestRun>('create', args).then((r) {
      run._test.add(r);
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
        var file = newScreen.imageFile;
        if (file != null) {
          s.imageFile.replace(file);
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
  final _test = BehaviorSubject<TestRun>();

  RunReference(this.args, this._host);

  TestRun? get value => _test.valueOrNull;
  Stream<TestRun> get onUpdated => _test.stream;

  void _rebuild(void Function(TestRunBuilder) updates) {
    var test = _test.value;
    test = test.rebuild(updates);
    _test.add(test);
  }

  void _completeWithError(Object error) {
    _test.addError(error);
  }

  void dispose() {
    _test.close();
    _host._currentRuns.remove(args.id);
  }
}
