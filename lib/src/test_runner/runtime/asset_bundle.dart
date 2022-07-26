import 'dart:async';
import 'package:flutter/services.dart';

abstract class TestBundle implements AssetBundle {
  Future<void> waitFinishLoading();
  Future<void> runWithNetworkOverride(Future<void> Function() callback);
}
