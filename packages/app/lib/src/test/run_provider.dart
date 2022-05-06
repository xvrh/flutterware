/*
import 'package:dev_studio/src/scenario_runner/app/toolbar.dart';
import 'package:dev_studio/src/scenario_runner/protocol/api.dart';
import 'package:dev_studio/src/scenario_runner/protocol/domains/run.dart';
import 'package:dev_studio/src/scenario_runner/protocol/model/run_args.dart';
import 'package:dev_studio/src/scenario_runner/protocol/model/scenario_run.dart';
import 'package:flutter/material.dart';

class ScenarioRunProvider extends InheritedWidget {
  final ScenarioRun run;
  
  const ScenarioRunProvider({
    Key? key,
    required Widget child,
    required this.run,
  }) : super(key: key, child: child);

  static ScenarioRunProvider of(BuildContext context) {
    final ScenarioRunProvider? result =
        context.dependOnInheritedWidgetOfExactType<ScenarioRunProvider>();
    assert(result != null, 'No ScenarioRunProvider found in context');
    return result!;
  }

  @override
  bool updateShouldNotify(ScenarioRunProvider oldWidget) {
    return run != oldWidget.run;
  }
}

class ScenarioRunScope extends StatefulWidget {
  final ScenarioApi client;
  final Widget child;
  
  const ScenarioRunScope({Key? key, required this.client, required this.child}) : super(key: key);

  @override
  ScenarioRunScopeState createState() => ScenarioRunScopeState();
}

class ScenarioRunScopeState extends State<ScenarioRunScope> {
  late RunReference _runReference;
  
  void refresh(String scenarioName) {
    _runReference.dispose();
    setState(() {
      _start();
    });
  }

  void start(String scenarioName) {
    var toolbar = ToolBarScope.of(context).parameters;
    _runReference = widget.client.run.start(
      RunArgs(
        scenarioName,
        device: toolbar.device,
        language: toolbar.language,
        imageRatio: 1.0,
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    return StreamBuilder<ScenarioRun>(
        stream: _runReference.onUpdated,
        initialData: _runReference.value,
        builder: (context, snapshot) {
          return ScenarioRunProvider(child: widget.child, run: snapshot.requireData);
    });
  }
}
*/
