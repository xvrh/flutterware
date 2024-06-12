import 'dart:core' as core;
import 'dart:core';
import 'package:flutter/material.dart';
import 'parameters.dart';

export 'app.dart' show UICatalog;

extension UIBookExtension on BuildContext {
  UICatalogState get uiCatalog => UICatalogState.of(this);
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

class UICatalogStateProvider extends InheritedWidget {
  final UICatalogState state;

  const UICatalogStateProvider({
    super.key,
    required super.child,
    required this.state,
  });

  static UICatalogStateProvider of(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<UICatalogStateProvider>()!;
  }

  @override
  bool updateShouldNotify(UICatalogStateProvider oldWidget) {
    return oldWidget.state != state;
  }
}

abstract class UICatalogState {
  static final empty = _EmptyUICatalogState();

  TopBarState get topBar;

  Parameters get parameters;

  static UICatalogState of(BuildContext context) {
    return UICatalogStateProvider.of(context).state;
  }
}

abstract class TopBarState {
  T picker<T>(String name, Map<String, T> options, T defaultValue);
}

class _EmptyUICatalogState implements UICatalogState {
  @override
  final topBar = _EmptyTopBarState();

  @override
  final parameters = Parameters();
}

class _EmptyTopBarState implements TopBarState {
  @override
  T picker<T>(
      core.String name, core.Map<core.String, T> values, T defaultValue) {
    return defaultValue;
  }
}
