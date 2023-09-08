import 'dart:core' as core;
import 'dart:core';
import 'package:flutter/material.dart';
import 'parameters.dart';

export 'app.dart' show WidgetBook;

extension WidgetBookExtension on BuildContext {
  WidgetBookState get book => WidgetBookState.of(this);
}

class WidgetContainer extends StatelessWidget {
  final BoxDecoration? background;
  final bool? intrinsicWidth;
  final bool? intrinsicHeight;
  final bool? deviceFrame;

  const WidgetContainer({
    super.key,
    this.background,
    this.intrinsicWidth,
    this.intrinsicHeight,
    this.deviceFrame,
  });

  @override
  Widget build(BuildContext context) {
    return Container();
  }
}

class WidgetBookStateProvider extends InheritedWidget {
  final WidgetBookState state;

  const WidgetBookStateProvider({
    super.key,
    required super.child,
    required this.state,
  });

  static WidgetBookStateProvider of(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<WidgetBookStateProvider>()!;
  }

  @override
  bool updateShouldNotify(WidgetBookStateProvider oldWidget) {
    return oldWidget.state != state;
  }
}

abstract class WidgetBookState with ParametersMixin {
  static final empty = _EmptyWidgetBookState();

  TopBarState get topBar;

  static WidgetBookState of(BuildContext context) {
    return WidgetBookStateProvider.of(context).state;
  }
}

abstract class TopBarState {
  T picker<T>(String name, Map<String, T> values, T defaultValue);
}

class _EmptyWidgetBookState with ParametersMixin implements WidgetBookState {
  @override
  final topBar = _EmptyTopBarState();
}

class _EmptyTopBarState implements TopBarState {
  @override
  T picker<T>(
      core.String name, core.Map<core.String, T> values, T defaultValue) {
    return defaultValue;
  }
}
