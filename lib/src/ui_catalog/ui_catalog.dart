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

  /// App-wide chrome shown in the top bar (e.g. theme, locale). Controls here
  /// persist across demos — declare them from the app shell (`appBuilder`).
  /// For controls specific to one demo, use [parameters] (the bottom panel).
  TopBarState get topBar;

  Parameters get parameters;

  static UICatalogState of(BuildContext context) {
    final provider = UICatalogStateProvider.maybeOf(context);
    return provider?.state ?? UICatalogState.empty;
  }
}

abstract class TopBarState {
  /// A picker over [options] (label → value). [swatch]/[icon] render a colour
  /// dot or glyph beside each option. [style] chooses how it renders — an
  /// anchored [PickerStyle.popover] menu (default), an inline
  /// [PickerStyle.segmented] control, or a modal [PickerStyle.dialog].
  T picker<T>(
    String name,
    Map<String, T> options,
    T defaultValue, {
    Color Function(T value)? swatch,
    IconData Function(T value)? icon,
    PickerStyle style,
  });
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
    core.String name,
    core.Map<core.String, T> values,
    T defaultValue, {
    Color Function(T value)? swatch,
    IconData Function(T value)? icon,
    PickerStyle style = PickerStyle.popover,
  }) {
    return defaultValue;
  }
}
