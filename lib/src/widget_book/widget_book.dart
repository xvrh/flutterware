import 'dart:core' as core;
import 'dart:core';
import 'package:flutter/material.dart';

export 'app.dart' show WidgetBook;

var _v = '''Widget book
- Create the treeview
- Visualizer has option to select the size of the viewport + custom
- Each widget can easily add an option bar (language, preferences etc...)
- Parameters allow to add even more options                
- Copy everything from Storybook

- Allow to compile to web
- Remember last selected widget
''';

mixin _Parameters {
  DateTime dateTime(String name) {
    return DateTime.now();
  }

  String string(String name, String defaultValue) {
    return '';
  }

  core.num num(String name, core.num defaultValue,
      {core.num? min, core.num? max}) {
    return 0;
  }

  core.int int(String name, core.int defaultValue,
      {core.int? min, core.int? max}) {
    return 0;
  }

  core.double double(String name, core.double defaultValue,
      {core.double? min, core.double? max}) {
    return 0;
  }
}

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

abstract class WidgetBookState {
  static final empty = _EmptyWidgetBookState();

  TopBarState get topBar;

  static WidgetBookState of(BuildContext context) {
    return WidgetBookStateProvider.of(context).state;
  }
}

abstract class TopBarState {
  T picker<T>(String name, Map<String, T> values, T defaultValue);
}

class _EmptyWidgetBookState implements WidgetBookState {
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
