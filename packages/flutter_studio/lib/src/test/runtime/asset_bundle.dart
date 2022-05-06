import 'dart:async';
import 'package:flutter/services.dart';

abstract class ScenarioBundle implements AssetBundle {
  Future<void> waitFinishLoading();
  Future<void> runWithNetworkOverride(Future<void> Function() callback);
}
