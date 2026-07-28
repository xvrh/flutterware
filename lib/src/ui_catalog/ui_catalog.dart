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

  static UICatalogStateProvider? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<UICatalogStateProvider>();
  }

  @override
  bool updateShouldNotify(UICatalogStateProvider oldWidget) {
    return oldWidget.state != state;
  }
}

abstract class UICatalogState {
  static final empty = _EmptyUICatalogState();

  /// Controls belonging to one entry, read while it builds.
  ///
  /// App-wide switches — a flavour, a locale, a theme — are not declared here.
  /// They are declared in the project's `CatalogShell`, which hands them out
  /// through `TopBarState` rather than through this, and they persist across
  /// entries because they belong to the shell rather than to whatever it is
  /// wrapping. That they are *not* reachable from a context is deliberate; see
  /// `TopBarState`.
  Parameters get parameters;

  static UICatalogState of(BuildContext context) {
    final provider = UICatalogStateProvider.maybeOf(context);
    return provider?.state ?? UICatalogState.empty;
  }
}

class _EmptyUICatalogState implements UICatalogState {
  @override
  final parameters = Parameters();
}
