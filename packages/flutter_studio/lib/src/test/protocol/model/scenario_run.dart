import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';
import 'run_args.dart';
import 'run_result.dart';
import 'scenario.dart';
import 'screen.dart';

part 'scenario_run.g.dart';

abstract class ScenarioRun implements Built<ScenarioRun, ScenarioRunBuilder> {
  static Serializer<ScenarioRun> get serializer => _$scenarioRunSerializer;

  ScenarioRun._();
  factory ScenarioRun._builder([void Function(ScenarioRunBuilder) updates]) =
      _$ScenarioRun;

  factory ScenarioRun(ScenarioReference scenario, RunArgs args) =>
      ScenarioRun._builder((b) => b
        ..scenario.replace(scenario)
        ..args.replace(args));

  ScenarioReference get scenario;
  RunArgs get args;
  BuiltMap<String, Screen> get screens;
  RunResult? get result;
  bool get isCompleted => result != null;

  ScenarioRun collapse() {
    return rebuild((b) {
      Screen? lastScreen;
      for (var screenEntry in screens.entries) {
        var screen = screenEntry.value;
        if (screen.isCollapsable && lastScreen != null) {
          screen = screen.rebuild((r) => r.isCollapsed = true);
          lastScreen = lastScreen.rebuild((s) {
            var index = s.next.build().indexWhere((e) => e.to == screen.id);
            s.next.removeAt(index);
            s.next.insertAll(index, screen.next);
            s.collapsedScreens.add(screen);
          });
          b.screens[lastScreen.id] = lastScreen;
          b.screens[screen.id] = screen;
        } else {
          b.screens[screen.id] = screen;
          lastScreen = screen;
        }
      }
    });
  }
}
