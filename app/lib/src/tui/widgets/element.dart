part of 'widgets.dart';

/// A handle to the location of a widget in the tree.
///
/// Every [Element] implements [BuildContext], so a widget's `build` method
/// receives its own element as its context.
abstract class BuildContext {
  /// The widget currently configuring this context's element.
  Widget get widget;

  /// The [BuildOwner] scheduling rebuilds for this context.
  BuildOwner? get owner;

  /// The nearest descendant render object, or null if there is none yet.
  RenderObject? findRenderObject();

  /// Returns the nearest ancestor [InheritedWidget] of type [T], registering
  /// this context as a dependent so it rebuilds when that widget changes.
  ///
  /// The optional [aspect] tags the dependency; [InheritedElement] subclasses
  /// may use it to rebuild only dependents whose aspect changed. Returns null
  /// when there is no such ancestor.
  T? dependOnInheritedWidgetOfExactType<T extends InheritedWidget>(
      {Object? aspect});

  /// Returns the nearest ancestor [InheritedWidget] of type [T] without
  /// registering a dependency.
  T? getInheritedWidgetOfExactType<T extends InheritedWidget>();
}

/// The stages of an [Element]'s life: created but unmounted ([initial]), in
/// the tree ([active]), removed but possibly reclaimable ([inactive]), or
/// permanently gone ([defunct]).
enum _ElementLifecycle { initial, active, inactive, defunct }

/// The mounted instance of a [Widget].
///
/// Elements form the long-lived spine of the UI tree: they hold parentage,
/// the [BuildOwner], dirty flags, and (for [StatefulElement]) the [State].
/// Each frame, new widgets are reconciled against the existing elements via
/// [updateChild].
abstract class Element implements BuildContext {
  Element(this._widget);

  Widget? _widget;
  Element? _parent;
  Object? _slot;
  int _depth = 0;
  BuildOwner? _owner;
  _ElementLifecycle _lifecycleState = _ElementLifecycle.initial;
  bool _dirty = true;
  bool _inDirtyList = false;

  /// The inherited-widget lookup map, inherited from the parent: a widget
  /// runtime type to the nearest ancestor [InheritedElement] of that type.
  /// Enables `O(1)` ancestor lookup from any element.
  Map<Type, InheritedElement>? _inheritedElements;

  /// The [InheritedElement]s this element currently depends on. Used to
  /// unregister this element from each when it is rebuilt or leaves the tree.
  Set<InheritedElement>? _dependencies;

  @override
  Widget get widget => _widget!;

  @override
  BuildOwner? get owner => _owner;

  /// This element's position within its parent, as assigned by the parent.
  Object? get slot => _slot;

  /// Whether this element is still configured by a widget.
  bool get mounted => _widget != null;

  /// Whether this element needs rebuilding.
  bool get dirty => _dirty;

  /// Orders inactive elements deepest-first for unmounting.
  static int _sort(Element a, Element b) => a._depth - b._depth;

  // --- The render object this element (or its descendants) contributes. ---

  /// The nearest render object at or below this element, or null if there is
  /// none. The base walks down to the first descendant that owns one;
  /// `RenderObjectElement` (a later task) overrides this to return its own.
  RenderObject? get renderObject {
    if (_lifecycleState == _ElementLifecycle.defunct) {
      return null;
    }
    return _renderObjectAttachingChild?.renderObject;
  }

  /// The single child that attaches a render object into this element's
  /// ancestor, or null. Overridden by [ComponentElement].
  Element? get _renderObjectAttachingChild {
    Element? next;
    visitChildren((child) => next = child);
    return next;
  }

  @override
  RenderObject? findRenderObject() => renderObject;

  // --- Lifecycle ---

  /// Adds this element to the tree under [parent] at [newSlot].
  void mount(Element? parent, Object? newSlot) {
    assert(_lifecycleState == _ElementLifecycle.initial);
    assert(_parent == null);
    _parent = parent;
    _slot = newSlot;
    _lifecycleState = _ElementLifecycle.active;
    _depth = parent == null ? 1 : parent._depth + 1;
    if (parent != null) {
      _owner = parent._owner;
    }
    _updateInheritance();
  }

  /// Reconfigures this element with [newWidget], which has the same runtime
  /// type and key as the current widget. Subclasses extend this.
  void update(covariant Widget newWidget) {
    assert(_lifecycleState == _ElementLifecycle.active);
    assert(newWidget != widget);
    assert(Widget.canUpdate(widget, newWidget));
    _widget = newWidget;
  }

  /// Copies the inherited-widget map from the parent. Overridden by
  /// `InheritedElement` to also register itself.
  void _updateInheritance() {
    _inheritedElements = _parent?._inheritedElements;
  }

  /// Rebuilds this element if it is active and dirty.
  void rebuild({bool force = false}) {
    assert(_lifecycleState != _ElementLifecycle.initial);
    if (_lifecycleState != _ElementLifecycle.active || (!_dirty && !force)) {
      return;
    }
    performRebuild();
    assert(!_dirty);
  }

  /// Performs the subclass-specific rebuild. The base clears the dirty flag.
  void performRebuild() {
    _dirty = false;
  }

  /// Marks this element as needing a rebuild and enqueues it with the owner.
  void markNeedsBuild() {
    assert(_lifecycleState != _ElementLifecycle.defunct);
    if (_lifecycleState != _ElementLifecycle.active) {
      return;
    }
    if (_dirty) {
      return;
    }
    _dirty = true;
    _owner!.scheduleBuildFor(this);
  }

  // --- Child reconciliation ---

  /// Reconciles a single child element against a new widget.
  ///
  /// The four cases: nothing-to-nothing returns null; nothing-to-widget
  /// inflates; element-to-nothing deactivates; element-to-widget updates in
  /// place when [Widget.canUpdate], else replaces.
  Element? updateChild(Element? child, Widget? newWidget, Object? newSlot) {
    if (newWidget == null) {
      if (child != null) {
        deactivateChild(child);
      }
      return null;
    }

    final Element newChild;
    if (child != null) {
      if (child.widget == newWidget) {
        if (child._slot != newSlot) {
          updateSlotForChild(child, newSlot);
        }
        newChild = child;
      } else if (Widget.canUpdate(child.widget, newWidget)) {
        if (child._slot != newSlot) {
          updateSlotForChild(child, newSlot);
        }
        child.update(newWidget);
        assert(child.widget == newWidget);
        newChild = child;
      } else {
        deactivateChild(child);
        assert(child._parent == null);
        newChild = inflateWidget(newWidget, newSlot);
      }
    } else {
      newChild = inflateWidget(newWidget, newSlot);
    }

    return newChild;
  }

  /// Creates an element for [newWidget] and mounts it as a child of this one.
  ///
  /// There is no `GlobalKey` registry in stage 4, so this always inflates a
  /// fresh element.
  Element inflateWidget(Widget newWidget, Object? newSlot) {
    var newChild = newWidget.createElement();
    newChild.mount(this, newSlot);
    assert(newChild._lifecycleState == _ElementLifecycle.active);
    return newChild;
  }

  /// Removes [child] from this element's render tree and parks it on the
  /// owner's inactive list (which deactivates its subtree).
  void deactivateChild(Element child) {
    assert(child._parent == this);
    child._parent = null;
    child.detachRenderObject();
    _owner!._inactiveElements.add(child);
  }

  /// Drops [child] from this element's bookkeeping; the child is about to be
  /// reused or removed. Subclasses with children override this.
  void forgetChild(Element child) {}

  /// Changes the slot [child] occupies, propagating to descendant render
  /// objects so they re-splice into their parent.
  void updateSlotForChild(Element child, Object? newSlot) {
    assert(_lifecycleState == _ElementLifecycle.active);
    assert(child._parent == this);
    void visit(Element element) {
      element._updateSlot(newSlot);
      var descendant = element._renderObjectAttachingChild;
      if (descendant != null) {
        visit(descendant);
      }
    }

    visit(child);
  }

  /// Records a new slot on this element. [RenderObjectElement] also re-splices
  /// its render object.
  void _updateSlot(Object? newSlot) {
    assert(_lifecycleState == _ElementLifecycle.active);
    _slot = newSlot;
  }

  // --- activate / deactivate / unmount ---

  /// Transitions this element from inactive back to active.
  void activate() {
    assert(_lifecycleState == _ElementLifecycle.inactive);
    var hadDependencies = _dependencies?.isNotEmpty ?? false;
    _lifecycleState = _ElementLifecycle.active;
    _dependencies?.clear();
    _updateInheritance();
    if (_dirty) {
      _owner!.scheduleBuildFor(this);
    }
    if (hadDependencies) {
      didChangeDependencies();
    }
  }

  /// Transitions this element from active to inactive.
  void deactivate() {
    assert(_lifecycleState == _ElementLifecycle.active);
    assert(_widget != null);
    _unregisterDependencies();
    _inheritedElements = null;
    _lifecycleState = _ElementLifecycle.inactive;
  }

  /// Permanently removes this element from the tree.
  void unmount() {
    assert(_lifecycleState == _ElementLifecycle.inactive);
    assert(_widget != null);
    assert(_owner != null);
    _unregisterDependencies();
    _widget = null;
    _dependencies = null;
    _lifecycleState = _ElementLifecycle.defunct;
  }

  /// Drops this element from every [InheritedElement] it depends on, then
  /// clears its own dependency set. Called whenever the element leaves the
  /// active tree so stale dependents are not rebuilt.
  void _unregisterDependencies() {
    var dependencies = _dependencies;
    if (dependencies != null && dependencies.isNotEmpty) {
      for (var ancestor in dependencies) {
        ancestor.removeDependent(this);
      }
      dependencies.clear();
    }
  }

  /// Notifies this element that an inherited widget it depends on changed.
  ///
  /// Called by [InheritedElement] when an ancestor inherited widget updates.
  /// The base records the change so the next rebuild runs; [StatefulElement]
  /// forwards it to the [State]'s `didChangeDependencies`.
  void didChangeDependencies() {
    _didChangeDependencies();
  }

  /// Hook invoked when an inherited dependency changes. Overridden by
  /// [StatefulElement] to forward to the [State].
  void _didChangeDependencies() {}

  // --- Render tree attach / detach ---

  /// Adds this element's render objects into the render tree. The base
  /// forwards to children; [RenderObjectElement] does the real work.
  void attachRenderObject(Object? newSlot) {
    visitChildren((child) => child.attachRenderObject(newSlot));
    _slot = newSlot;
  }

  /// Removes this element's render objects from the render tree.
  void detachRenderObject() {
    visitChildren((child) => child.detachRenderObject());
    _slot = null;
  }

  /// Visits each child element. Elements with children override this.
  void visitChildren(void Function(Element child) visitor) {}

  // --- BuildContext / InheritedWidget ---

  @override
  T? dependOnInheritedWidgetOfExactType<T extends InheritedWidget>(
      {Object? aspect}) {
    var ancestor = _inheritedElements?[T];
    if (ancestor == null) {
      return null;
    }
    ancestor.updateDependencies(this, aspect);
    return ancestor.widget as T;
  }

  @override
  T? getInheritedWidgetOfExactType<T extends InheritedWidget>() {
    var ancestor = _inheritedElements?[T];
    return ancestor?.widget as T?;
  }

  /// Applies [widget]'s parent data to descendant render objects.
  ///
  /// The base recurses into children; `RenderObjectElement` (a later task)
  /// overrides this to call [ParentDataWidget.applyParentData] on its render
  /// object. [ParentDataElement] drives this walk after mount and update.
  void _applyParentDataTo(ParentDataWidget widget) {
    visitChildren((child) => child._applyParentDataTo(widget));
  }
}

/// An [Element] backed by a widget whose `build` produces a single child
/// widget (a [StatelessWidget] or [StatefulWidget]).
abstract class ComponentElement extends Element {
  ComponentElement(super.widget);

  Element? _child;

  @override
  Element? get _renderObjectAttachingChild => _child;

  @override
  void mount(Element? parent, Object? newSlot) {
    super.mount(parent, newSlot);
    assert(_child == null);
    _firstBuild();
    assert(_child != null);
  }

  /// Performs the initial build. [StatefulElement] extends this to run
  /// `initState`/`didChangeDependencies` first.
  void _firstBuild() {
    rebuild();
  }

  @override
  void performRebuild() {
    super
        .performRebuild(); // clears _dirty before build() so re-entrant markNeedsBuild() is not swallowed
    var built = build();
    _child = updateChild(_child, built, _slot);
    assert(_child != null);
  }

  /// Produces this element's child widget. Subclasses delegate to the widget's
  /// or state's `build`.
  Widget build();

  @override
  void visitChildren(void Function(Element child) visitor) {
    if (_child != null) {
      visitor(_child!);
    }
  }

  @override
  void forgetChild(Element child) {
    assert(child == _child);
    _child = null;
    super.forgetChild(child);
  }
}

/// An [Element] for a [StatelessWidget].
class StatelessElement extends ComponentElement {
  StatelessElement(StatelessWidget super.widget);

  @override
  Widget build() => (widget as StatelessWidget).build(this);

  @override
  void update(StatelessWidget newWidget) {
    super.update(newWidget);
    rebuild(force: true);
  }
}

/// An [Element] for a [StatefulWidget]; owns the widget's [State].
class StatefulElement extends ComponentElement {
  StatefulElement(StatefulWidget widget)
      : _state = widget.createState(),
        super(widget) {
    assert(_state._element == null);
    _state._element = this;
    assert(_state._widget == null);
    _state._widget = widget;
  }

  final State<StatefulWidget> _state;
  bool _didChangeDependenciesFlag = false;

  /// The [State] instance for this location in the tree.
  State<StatefulWidget> get state => _state;

  @override
  Widget build() => state.build(this);

  @override
  void _firstBuild() {
    state.initState();
    state.didChangeDependencies();
    super._firstBuild();
  }

  @override
  void performRebuild() {
    if (_didChangeDependenciesFlag) {
      state.didChangeDependencies();
      _didChangeDependenciesFlag = false;
    }
    super.performRebuild();
  }

  @override
  void update(StatefulWidget newWidget) {
    super.update(newWidget);
    var oldWidget = state._widget!;
    state._widget = newWidget;
    state.didUpdateWidget(oldWidget);
    rebuild(force: true);
  }

  @override
  void _didChangeDependencies() {
    _didChangeDependenciesFlag = true;
  }

  @override
  void activate() {
    super.activate();
    // The State may have released build-time resources in deactivate(); a
    // rebuild lets it reallocate them.
    assert(_lifecycleState == _ElementLifecycle.active);
    markNeedsBuild();
  }

  @override
  void deactivate() {
    state.deactivate();
    super.deactivate();
  }

  @override
  void unmount() {
    super.unmount();
    state.dispose();
    _state._element = null;
  }
}

/// The owner's collection of elements deactivated this frame.
///
/// An element is added here when removed from the tree; if not reclaimed
/// before [_unmountAll] runs, its whole subtree is unmounted.
class _InactiveElements {
  final Set<Element> _elements = {};

  void add(Element element) {
    assert(element._parent == null);
    if (element._lifecycleState == _ElementLifecycle.active) {
      _deactivateRecursively(element);
    }
    _elements.add(element);
  }

  void remove(Element element) {
    assert(element._parent == null);
    _elements.remove(element);
  }

  static void _deactivateRecursively(Element element) {
    assert(element._lifecycleState == _ElementLifecycle.active);
    element.deactivate();
    element.visitChildren(_deactivateRecursively);
  }

  static void _unmount(Element element) {
    assert(element._lifecycleState == _ElementLifecycle.inactive);
    element.visitChildren((child) {
      assert(child._parent == element);
      _unmount(child);
    });
    element.unmount();
    assert(element._lifecycleState == _ElementLifecycle.defunct);
  }

  void _unmountAll() {
    var elements = _elements.toList()..sort(Element._sort);
    _elements.clear();
    elements.reversed.forEach(_unmount);
    assert(_elements.isEmpty);
  }
}
