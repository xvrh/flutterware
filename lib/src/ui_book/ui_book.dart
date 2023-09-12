import 'dart:core' as core;
import 'dart:core';
import 'package:flutter/material.dart';
import 'parameters.dart';

export 'app.dart' show UIBook;

extension UIBookExtension on BuildContext {
  UIBookState get book => UIBookState.of(this);
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

class UIBookStateProvider extends InheritedWidget {
  final UIBookState state;

  const UIBookStateProvider({
    super.key,
    required super.child,
    required this.state,
  });

  static UIBookStateProvider of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<UIBookStateProvider>()!;
  }

  @override
  bool updateShouldNotify(UIBookStateProvider oldWidget) {
    return oldWidget.state != state;
  }
}

abstract class UIBookState {
  static final empty = _EmptyUIBookState();

  TopBarState get topBar;

  Parameters get knobs;

  static UIBookState of(BuildContext context) {
    return UIBookStateProvider.of(context).state;
  }
}

abstract class TopBarState {
  T picker<T>(String name, Map<String, T> options, T defaultValue);
}

class _EmptyUIBookState implements UIBookState {
  @override
  final topBar = _EmptyTopBarState();

  @override
  final knobs = Parameters();
}

class _EmptyTopBarState implements TopBarState {
  @override
  T picker<T>(
      core.String name, core.Map<core.String, T> values, T defaultValue) {
    return defaultValue;
  }
}
