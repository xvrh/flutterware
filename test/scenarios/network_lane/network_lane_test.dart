import 'package:flutter/material.dart';
import 'package:flutterware/flutter_test.dart';
import 'package:flutterware/src/scenarios/run_args.dart';

/// The folder's network policy, end to end: nothing here says `network:`
/// except the one scenario that disagrees with its folder.
void main() {
  scenario('takes the folder policy', (s) async {
    expect(s.network.mode, ScenarioNetwork.live);
    await s.pumpWidget(const MaterialApp(home: Text('hello')));
  });

  scenario('says its own and wins', network: ScenarioNetwork.off, (s) async {
    expect(s.network.mode, ScenarioNetwork.off);
    await s.pumpWidget(const MaterialApp(home: Text('hello')));
  });

  // What `--network=` on one run and `FW_NETWORK=` in this lane both resolve
  // to. Read as the scenario *declares*, like every other axis, so it is set
  // around the declarations it is meant to reach.
  scenarioRunArgs = const ScenarioRunArgs(network: ScenarioNetwork.off);

  scenario('a run beats the folder', (s) async {
    expect(s.network.mode, ScenarioNetwork.off);
    await s.pumpWidget(const MaterialApp(home: Text('hello')));
  });

  scenario('and the scenario beats the run', network: ScenarioNetwork.live, (
    s,
  ) async {
    expect(s.network.mode, ScenarioNetwork.live);
    await s.pumpWidget(const MaterialApp(home: Text('hello')));
  });

  scenarioRunArgs = null;
}
