part of 'widgets.dart';

/// An [Element] for a [ProxyWidget].
///
/// A proxy element builds exactly its widget's [ProxyWidget.child]; it adds no
/// configuration of its own to the rendered output. Subclasses ([InheritedElement],
/// [ParentDataElement]) use the position in the tree for side effects —
/// inherited-widget lookup, or writing parent data — rather than for layout.
abstract class ProxyElement extends ComponentElement {
  ProxyElement(ProxyWidget super.widget);

  @override
  Widget build() => (widget as ProxyWidget).child;

  @override
  void update(ProxyWidget newWidget) {
    var oldWidget = widget as ProxyWidget;
    assert(widget != newWidget);
    super.update(newWidget);
    assert(widget == newWidget);
    updated(oldWidget);
    rebuild(force: true);
  }

  /// Called during [update], after the new widget is in place, with the
  /// [oldWidget] it replaced. Subclasses react to the configuration change
  /// here — [InheritedElement] notifies its dependents.
  void updated(covariant ProxyWidget oldWidget) {
    notifyClients(oldWidget);
  }

  /// Notifies whatever depends on this element that its widget changed.
  ///
  /// The base does nothing; [InheritedElement] overrides it to rebuild its
  /// registered dependents.
  void notifyClients(covariant ProxyWidget oldWidget) {}
}

/// A [Widget] that propagates information down the tree, looked up in `O(1)`
/// by descendants via [BuildContext.dependOnInheritedWidgetOfExactType].
///
/// When an inherited widget is rebuilt and [updateShouldNotify] returns true,
/// every descendant that depends on it is rebuilt.
abstract class InheritedWidget extends ProxyWidget {
  const InheritedWidget({super.key, required super.child});

  @override
  InheritedElement createElement() => InheritedElement(this);

  /// Whether descendants that depend on this widget should rebuild, given the
  /// [oldWidget] this one replaced.
  bool updateShouldNotify(covariant InheritedWidget oldWidget);
}

/// The [Element] for an [InheritedWidget].
///
/// On [mount] it installs itself into [_inheritedElements] so every descendant
/// inherits a map entry keyed by the widget's runtime type. Descendants that
/// look it up register as dependents; when the widget changes and
/// [InheritedWidget.updateShouldNotify] is true, those dependents are rebuilt.
class InheritedElement extends ProxyElement {
  InheritedElement(InheritedWidget super.widget);

  final Map<Element, Object?> _dependents = {};

  @override
  void _updateInheritance() {
    var incoming = _parent?._inheritedElements;
    if (incoming != null) {
      _inheritedElements = Map<Type, InheritedElement>.of(incoming);
    } else {
      _inheritedElements = <Type, InheritedElement>{};
    }
    _inheritedElements![widget.runtimeType] = this;
  }

  /// Records [dependent] as depending on this inherited element, tagged with
  /// [aspect]. The dependent also remembers this element so it can unregister
  /// itself when it is rebuilt, deactivated, or unmounted.
  void updateDependencies(Element dependent, Object? aspect) {
    setDependencies(dependent, aspect);
    (dependent._dependencies ??= <InheritedElement>{}).add(this);
  }

  /// The aspect [dependent] depends on, or null. Subclasses may override the
  /// dependency representation; the default stores the raw aspect.
  Object? getDependencies(Element dependent) => _dependents[dependent];

  /// Sets the dependency [value] for [dependent].
  void setDependencies(Element dependent, Object? value) {
    _dependents[dependent] = value;
  }

  /// Drops [dependent] from this element's dependent set. Called when the
  /// dependent leaves the tree.
  void removeDependent(Element dependent) {
    _dependents.remove(dependent);
  }

  @override
  void notifyClients(InheritedWidget oldWidget) {
    if (!(widget as InheritedWidget).updateShouldNotify(oldWidget)) {
      return;
    }
    for (var dependent in _dependents.keys) {
      notifyDependent(oldWidget, dependent);
    }
  }

  /// Rebuilds a single [dependent] in response to this widget changing.
  void notifyDependent(InheritedWidget oldWidget, Element dependent) {
    dependent.didChangeDependencies();
    dependent.markNeedsBuild();
  }
}

/// A [Widget] that, rather than rendering anything itself, writes layout
/// configuration ([ParentData]) onto a descendant render object.
///
/// `Expanded`/`Flexible` are [ParentDataWidget]s: they write a `flex` factor
/// into a child's `FlexParentData`.
abstract class ParentDataWidget<T extends ParentData> extends ProxyWidget {
  const ParentDataWidget({super.key, required super.child});

  @override
  ParentDataElement<T> createElement() => ParentDataElement<T>(this);

  /// Mutates the [ParentData] of [renderObject] from this widget's fields.
  void applyParentData(RenderObject renderObject);
}

/// The [Element] for a [ParentDataWidget].
///
/// After every mount and update it walks down to the descendant render
/// objects and applies the widget's parent data to each.
class ParentDataElement<T extends ParentData> extends ProxyElement {
  ParentDataElement(ParentDataWidget<T> super.widget);

  @override
  void mount(Element? parent, Object? newSlot) {
    super.mount(parent, newSlot);
    _applyParentData(widget as ParentDataWidget<T>);
  }

  @override
  void notifyClients(ParentDataWidget<T> oldWidget) {
    _applyParentData(widget as ParentDataWidget<T>);
  }

  /// Walks down to the descendant render-object elements and applies [w]'s
  /// parent data to each.
  ///
  /// The actual apply is delegated to [Element._applyParentDataTo], a no-op on
  /// the base [Element] that `RenderObjectElement` overrides (a later task) to
  /// call [ParentDataWidget.applyParentData] on its render object. Until that
  /// override lands the walk is a harmless no-op; this keeps the parent-data
  /// element self-contained without a forward reference to `RenderObjectElement`.
  void _applyParentData(ParentDataWidget<T> w) {
    if (_child != null) {
      _child!._applyParentDataTo(w);
    }
  }
}
