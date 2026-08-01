import 'dart:core' as core;
import 'dart:core';

import 'package:flutter/material.dart';

import 'parameters.dart';

export 'app.dart' show UICatalog;

/// What a preview asks for while it builds — `context.previews.parameters.*`.
extension PreviewsExtension on BuildContext {
  PreviewState get previews => PreviewState.of(this);
}

/// The same thing, under the name the in-app catalog has always used.
///
/// Two accessors over one state, and deliberately so: knobs are written on both
/// sides of the split. A preview says `previews`, a ui_book page says
/// `uiCatalog`, and neither reads like the other tool's vocabulary.
extension UIBookExtension on BuildContext {
  PreviewState get uiCatalog => PreviewState.of(this);
}

class UICatalogStateProvider extends InheritedWidget {
  final PreviewState state;

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

abstract class PreviewState {
  static final empty = _EmptyPreviewState();

  /// Controls belonging to one entry, read while it builds.
  ///
  /// App-wide switches — a flavour, a locale, a theme — are not declared here.
  /// They are declared in the project's `PreviewShell`, which hands them out
  /// through `TopBarState` rather than through this, and they persist across
  /// entries because they belong to the shell rather than to whatever it is
  /// wrapping. That they are *not* reachable from a context is deliberate; see
  /// `TopBarState`.
  Parameters get parameters;

  static PreviewState of(BuildContext context) {
    final provider = UICatalogStateProvider.maybeOf(context);
    return provider?.state ?? PreviewState.empty;
  }
}

class _EmptyPreviewState implements PreviewState {
  @override
  final parameters = Parameters();
}
