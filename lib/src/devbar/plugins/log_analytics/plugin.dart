import 'package:flutter/material.dart';
import 'package:flutterware/src/devbar/devbar.dart';
import '../../../utils/value_stream.dart';
import '../../devbar.dart';
import 'ui.dart';

class LogAnalyticsPlugin implements DevbarPlugin {
  static const _maxEvents = 200;
  final DevbarState devbar;
  final events = ValueStream<List<AnalyticEvent>>([]);

  LogAnalyticsPlugin(this.devbar) {
    devbar.ui.addTab(Tab(text: 'Analytics'), AnalyticsList(this),
        hierarchy: ['Logs']);
  }

  void log(String eventName, [Map<String, dynamic>? parameter]) {
    var eventList = events.value..add(AnalyticEvent(eventName, parameter));

    if (eventList.length > _maxEvents) {
      eventList.removeAt(0);
    }
    events.add(eventList);
  }

  void clear() {
    events.add([]);
  }

  @override
  void dispose() {
    events.dispose();
  }
}

class AnalyticEvent {
  final String name;
  final Map<String, dynamic>? parameters;
  final time = DateTime.now();

  AnalyticEvent(this.name, this.parameters);
}

extension AnalyticsPluginDevbarExtension on DevbarState {
  LogAnalyticsPlugin get analytics => plugin<LogAnalyticsPlugin>();
}
