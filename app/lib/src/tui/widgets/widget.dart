part of 'widgets.dart';

/// The immutable configuration node of the UI tree.
///
/// A [Widget] describes part of the UI; it holds no mutable state and is cheap
/// to rebuild. Each widget is inflated into a longer-lived [Element] (via
/// [createElement]) which is what actually persists across frames.
abstract class Widget {
  const Widget({this.key});

  /// Identifies this widget to child reconciliation; see [canUpdate].
  final Key? key;

  /// Inflates this widget into the [Element] that will hold it in the tree.
  Element createElement();

  /// Whether [newWidget] can reconfigure the element currently holding
  /// [oldWidget], rather than replacing it. True when the runtime types and
  /// keys match.
  static bool canUpdate(Widget oldWidget, Widget newWidget) =>
      oldWidget.runtimeType == newWidget.runtimeType &&
      oldWidget.key == newWidget.key;
}

/// A [Widget] that builds its subtree purely from its own configuration.
abstract class StatelessWidget extends Widget {
  const StatelessWidget({super.key});

  @override
  StatelessElement createElement() => StatelessElement(this);

  /// Describes the part of the UI this widget represents.
  Widget build(BuildContext context);
}

/// A [Widget] with mutable [State] that can change over its lifetime.
abstract class StatefulWidget extends Widget {
  const StatefulWidget({super.key});

  @override
  StatefulElement createElement() => StatefulElement(this);

  /// Creates the mutable [State] for this widget.
  State createState();
}

/// The mutable, persistent state for a [StatefulWidget].
///
/// The framework creates one [State] per [StatefulElement] in [mount] and
/// keeps it across rebuilds. Calling [setState] schedules a rebuild.
abstract class State<T extends StatefulWidget> {
  T? _widget;
  StatefulElement? _element;

  /// The current configuration. Updated by the framework when the parent
  /// rebuilds with a new widget of the same type.
  T get widget => _widget!;

  /// The [BuildContext] (the owning [StatefulElement]) for this state.
  BuildContext get context => _element!;

  /// Whether this state is currently mounted in the tree.
  ///
  /// False before [StatefulElement.mount] runs and again after the element is
  /// removed; true while the element is active.
  bool get mounted =>
      _element != null && _element!._lifecycleState == _ElementLifecycle.active;

  /// Called once when this state is inserted into the tree, before the first
  /// [build]. Subclasses that override must not return a `Future`.
  void initState() {}

  /// Called after [initState] and whenever an inherited dependency changes.
  void didChangeDependencies() {}

  /// Called when the parent rebuilds this widget with a new configuration.
  void didUpdateWidget(covariant T oldWidget) {}

  /// Notifies the framework that internal state changed, scheduling a rebuild.
  void setState(void Function() fn) {
    assert(_element != null,
        'setState() called on an unmounted State ($runtimeType).');
    fn();
    _element!.markNeedsBuild();
  }

  /// Called when this state is removed from the tree, possibly temporarily.
  void deactivate() {}

  /// Called when this state is permanently removed; release resources here.
  void dispose() {}

  /// Describes the part of the UI this state represents.
  Widget build(BuildContext context);
}

/// A [Widget] that wraps exactly one [child] without altering its layout.
abstract class ProxyWidget extends Widget {
  const ProxyWidget({super.key, required this.child});

  /// The widget below this one in the tree.
  final Widget child;
}
