part of 'widgets.dart';

/// A [Widget] that configures a stage 3 [RenderObject].
///
/// This is the bridge between the reactive widget layer and the imperative
/// render tree: [createRenderObject] builds the render object the first time
/// the widget is mounted, and [updateRenderObject] pushes changed fields onto
/// it on every rebuild. The [Leaf]/[SingleChild]/[MultiChild] variants differ
/// only in how many children they manage.
abstract class RenderObjectWidget extends Widget {
  const RenderObjectWidget({super.key});

  @override
  RenderObjectElement createElement();

  /// Creates the [RenderObject] this widget configures.
  RenderObject createRenderObject(BuildContext context);

  /// Copies this widget's configuration onto an existing [renderObject].
  void updateRenderObject(
      BuildContext context, covariant RenderObject renderObject) {}

  /// Called when the element holding [renderObject] is unmounted, so the
  /// widget can release anything tied to it. The base does nothing.
  void didUnmountRenderObject(covariant RenderObject renderObject) {}
}

/// The [Element] for a [RenderObjectWidget].
///
/// It owns one [RenderObject], creates it on [mount], updates it on every
/// rebuild, and splices it into the render tree by walking to the nearest
/// ancestor [RenderObjectElement] and calling its
/// [insertRenderObjectChild]/[moveRenderObjectChild]/[removeRenderObjectChild].
abstract class RenderObjectElement extends Element {
  RenderObjectElement(RenderObjectWidget super.widget);

  RenderObject? _renderObject;

  @override
  RenderObject? get renderObject => _renderObject;

  /// A [RenderObjectElement] contributes its own render object, so the
  /// slot-propagation walk stops here rather than descending into children.
  @override
  Element? get _renderObjectAttachingChild => null;

  /// The nearest ancestor [RenderObjectElement] this element's render object
  /// is spliced into, or null when detached.
  RenderObjectElement? _ancestorRenderObjectElement;

  RenderObjectElement? _findAncestorRenderObjectElement() {
    var ancestor = _parent;
    while (ancestor != null && ancestor is! RenderObjectElement) {
      ancestor = ancestor._parent;
    }
    return ancestor as RenderObjectElement?;
  }

  @override
  void mount(Element? parent, Object? newSlot) {
    super.mount(parent, newSlot);
    _renderObject = (widget as RenderObjectWidget).createRenderObject(this);
    attachRenderObject(newSlot);
    super.performRebuild(); // clears the dirty flag
  }

  @override
  void update(covariant RenderObjectWidget newWidget) {
    super.update(newWidget);
    _performRebuild(); // calls widget.updateRenderObject()
  }

  @override
  void performRebuild() {
    _performRebuild(); // calls widget.updateRenderObject()
  }

  void _performRebuild() {
    (widget as RenderObjectWidget).updateRenderObject(this, _renderObject!);
    super.performRebuild(); // clears the dirty flag
  }

  @override
  void unmount() {
    var oldWidget = widget as RenderObjectWidget;
    super.unmount();
    oldWidget.didUnmountRenderObject(_renderObject!);
  }

  @override
  void _updateSlot(Object? newSlot) {
    var oldSlot = _slot;
    super._updateSlot(newSlot);
    _ancestorRenderObjectElement?.moveRenderObjectChild(
        _renderObject!, oldSlot, newSlot);
  }

  @override
  void attachRenderObject(Object? newSlot) {
    assert(_ancestorRenderObjectElement == null);
    _slot = newSlot;
    _ancestorRenderObjectElement = _findAncestorRenderObjectElement();
    _ancestorRenderObjectElement?.insertRenderObjectChild(
        _renderObject!, newSlot);
  }

  @override
  void detachRenderObject() {
    if (_ancestorRenderObjectElement != null) {
      _ancestorRenderObjectElement!
          .removeRenderObjectChild(_renderObject!, _slot);
      _ancestorRenderObjectElement = null;
    }
    _slot = null;
  }

  /// Applies a [ParentDataWidget]'s parent data to this element's render
  /// object — the seam [ParentDataElement] drives. The base [Element]
  /// implementation recurses into children; this is the leaf that does the
  /// real write.
  @override
  void _applyParentDataTo(ParentDataWidget widget) {
    widget.applyParentData(_renderObject!);
  }

  /// Inserts [child] into this element's render object at the given [slot].
  void insertRenderObjectChild(
      covariant RenderObject child, covariant Object? slot);

  /// Moves [child] within this element's render object from [oldSlot] to
  /// [newSlot]. [child] is guaranteed to already be a child of the render
  /// object.
  void moveRenderObjectChild(covariant RenderObject child,
      covariant Object? oldSlot, covariant Object? newSlot);

  /// Removes [child] from this element's render object.
  void removeRenderObjectChild(
      covariant RenderObject child, covariant Object? slot);

  /// Reconciles an ordered list of child elements against a new list of
  /// widgets, returning the new child-element list.
  ///
  /// A faithful transcription of Flutter's `RenderObjectElement.updateChildren`:
  /// a forward scan over the matching prefix, a backward scan over the matching
  /// suffix, a key-map of the old middle so moved/keyed children are matched
  /// rather than torn down, then inflate/update/deactivate of the middle, and a
  /// final forward scan over the suffix. The only adaptation: the slot of each
  /// child is its previous-sibling [Element] (null for the first), so a child
  /// whose index shifts gets a new slot and its render object is re-spliced.
  ///
  /// [oldChildren] must not be mutated while this runs; a caller removing
  /// children reentrantly supplies [forgottenChildren], which is consulted
  /// whenever [oldChildren] is read.
  List<Element> updateChildren(
    List<Element> oldChildren,
    List<Widget> newWidgets, {
    Set<Element>? forgottenChildren,
  }) {
    Element? replaceWithNullIfForgotten(Element child) {
      return (forgottenChildren?.contains(child) ?? false) ? null : child;
    }

    // This attempts to diff the new child list (newWidgets) against the old
    // child list (oldChildren) and produce the new list of child elements.
    //
    // The general approach, syncing the new list backwards:
    // 1. Walk the lists from the top, syncing nodes, until they no longer
    //    match.
    // 2. Walk the lists from the bottom, WITHOUT syncing, until they no longer
    //    match — these are synced last so all nodes sync in order.
    // 3. Walk the narrowed old middle, building a key map and deactivating
    //    keyless leftovers.
    // 4. Walk the narrowed new middle: keyed items sync with their old element
    //    if present, everything else syncs with null (inflates).
    // 5. Walk the suffix again, syncing the nodes.
    // 6. Deactivate any keyed old children still unclaimed.

    var newChildrenTop = 0;
    var oldChildrenTop = 0;
    var newChildrenBottom = newWidgets.length - 1;
    var oldChildrenBottom = oldChildren.length - 1;

    var newChildren = List<Element?>.filled(newWidgets.length, null);

    Element? previousChild;

    // Update the top of the list.
    while ((oldChildrenTop <= oldChildrenBottom) &&
        (newChildrenTop <= newChildrenBottom)) {
      var oldChild = replaceWithNullIfForgotten(oldChildren[oldChildrenTop]);
      var newWidget = newWidgets[newChildrenTop];
      if (oldChild == null || !Widget.canUpdate(oldChild.widget, newWidget)) {
        break;
      }
      var newChild = updateChild(oldChild, newWidget, previousChild)!;
      newChildren[newChildrenTop] = newChild;
      previousChild = newChild;
      newChildrenTop += 1;
      oldChildrenTop += 1;
    }

    // Scan the bottom of the list.
    while ((oldChildrenTop <= oldChildrenBottom) &&
        (newChildrenTop <= newChildrenBottom)) {
      var oldChild = replaceWithNullIfForgotten(oldChildren[oldChildrenBottom]);
      var newWidget = newWidgets[newChildrenBottom];
      if (oldChild == null || !Widget.canUpdate(oldChild.widget, newWidget)) {
        break;
      }
      oldChildrenBottom -= 1;
      newChildrenBottom -= 1;
    }

    // Scan the old children in the middle of the list.
    var haveOldChildren = oldChildrenTop <= oldChildrenBottom;
    Map<Key, Element>? oldKeyedChildren;
    if (haveOldChildren) {
      oldKeyedChildren = {};
      while (oldChildrenTop <= oldChildrenBottom) {
        var oldChild = replaceWithNullIfForgotten(oldChildren[oldChildrenTop]);
        if (oldChild != null) {
          if (oldChild.widget.key != null) {
            oldKeyedChildren[oldChild.widget.key!] = oldChild;
          } else {
            deactivateChild(oldChild);
          }
        }
        oldChildrenTop += 1;
      }
    }

    // Update the middle of the list.
    while (newChildrenTop <= newChildrenBottom) {
      Element? oldChild;
      var newWidget = newWidgets[newChildrenTop];
      if (haveOldChildren) {
        var key = newWidget.key;
        if (key != null) {
          oldChild = oldKeyedChildren![key];
          if (oldChild != null) {
            if (Widget.canUpdate(oldChild.widget, newWidget)) {
              // We found a match; remove it so it is not unsynced later.
              oldKeyedChildren.remove(key);
            } else {
              // Not a match; pretend we did not see it.
              oldChild = null;
            }
          }
        }
      }
      assert(oldChild == null || Widget.canUpdate(oldChild.widget, newWidget));
      var newChild = updateChild(oldChild, newWidget, previousChild)!;
      newChildren[newChildrenTop] = newChild;
      previousChild = newChild;
      newChildrenTop += 1;
    }

    // We've scanned the whole list.
    assert(oldChildrenTop == oldChildrenBottom + 1);
    assert(newChildrenTop == newChildrenBottom + 1);
    assert(newWidgets.length - newChildrenTop ==
        oldChildren.length - oldChildrenTop);
    newChildrenBottom = newWidgets.length - 1;
    oldChildrenBottom = oldChildren.length - 1;

    // Update the bottom of the list.
    while ((oldChildrenTop <= oldChildrenBottom) &&
        (newChildrenTop <= newChildrenBottom)) {
      var oldChild = oldChildren[oldChildrenTop];
      var newWidget = newWidgets[newChildrenTop];
      assert(Widget.canUpdate(oldChild.widget, newWidget));
      var newChild = updateChild(oldChild, newWidget, previousChild)!;
      newChildren[newChildrenTop] = newChild;
      previousChild = newChild;
      newChildrenTop += 1;
      oldChildrenTop += 1;
    }

    // Clean up any of the remaining middle nodes from the old list.
    if (haveOldChildren && oldKeyedChildren!.isNotEmpty) {
      for (var oldChild in oldKeyedChildren.values) {
        if (forgottenChildren == null ||
            !forgottenChildren.contains(oldChild)) {
          deactivateChild(oldChild);
        }
      }
    }

    return newChildren.cast<Element>();
  }
}

/// A [RenderObjectWidget] with no children.
abstract class LeafRenderObjectWidget extends RenderObjectWidget {
  const LeafRenderObjectWidget({super.key});

  @override
  LeafRenderObjectElement createElement() => LeafRenderObjectElement(this);
}

/// The [Element] for a [LeafRenderObjectWidget].
class LeafRenderObjectElement extends RenderObjectElement {
  LeafRenderObjectElement(LeafRenderObjectWidget super.widget);

  @override
  void forgetChild(Element child) {
    assert(false, 'A LeafRenderObjectElement has no children.');
    super.forgetChild(child);
  }

  @override
  void insertRenderObjectChild(RenderObject child, Object? slot) {
    assert(false, 'A LeafRenderObjectElement has no children.');
  }

  @override
  void moveRenderObjectChild(
      RenderObject child, Object? oldSlot, Object? newSlot) {
    assert(false, 'A LeafRenderObjectElement has no children.');
  }

  @override
  void removeRenderObjectChild(RenderObject child, Object? slot) {
    assert(false, 'A LeafRenderObjectElement has no children.');
  }
}

/// A [RenderObjectWidget] that configures a render object with one optional
/// [child], whose render object uses the [RenderBoxWithChild] mixin.
abstract class SingleChildRenderObjectWidget extends RenderObjectWidget {
  const SingleChildRenderObjectWidget({super.key, this.child});

  /// The widget below this one in the tree, or null.
  final Widget? child;

  @override
  SingleChildRenderObjectElement createElement() =>
      SingleChildRenderObjectElement(this);
}

/// The [Element] for a [SingleChildRenderObjectWidget].
class SingleChildRenderObjectElement extends RenderObjectElement {
  SingleChildRenderObjectElement(SingleChildRenderObjectWidget super.widget);

  Element? _child;

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

  @override
  void mount(Element? parent, Object? newSlot) {
    super.mount(parent, newSlot);
    _child = updateChild(
        _child, (widget as SingleChildRenderObjectWidget).child, null);
  }

  @override
  void update(SingleChildRenderObjectWidget newWidget) {
    super.update(newWidget);
    _child = updateChild(
        _child, (widget as SingleChildRenderObjectWidget).child, null);
  }

  @override
  void insertRenderObjectChild(RenderObject child, Object? slot) {
    assert(slot == null);
    (_renderObject! as RenderBoxWithChild).child = child as RenderBox;
  }

  @override
  void moveRenderObjectChild(
      RenderObject child, Object? oldSlot, Object? newSlot) {
    assert(false, 'A SingleChildRenderObjectElement never moves its child.');
  }

  @override
  void removeRenderObjectChild(RenderObject child, Object? slot) {
    assert(slot == null);
    (_renderObject! as RenderBoxWithChild).child = null;
  }
}

/// A [RenderObjectWidget] that configures a render object with a list of
/// [children], whose render object is a [RenderFlex].
abstract class MultiChildRenderObjectWidget extends RenderObjectWidget {
  const MultiChildRenderObjectWidget({super.key, this.children = const []});

  /// The widgets below this one in the tree, in order.
  final List<Widget> children;

  @override
  MultiChildRenderObjectElement createElement() =>
      MultiChildRenderObjectElement(this);
}

/// The [Element] for a [MultiChildRenderObjectWidget].
///
/// Each child's slot is its **previous-sibling [Element]** (null for the
/// first child); that previous sibling's render object is the `after:`
/// anchor passed to [RenderFlex.insert]/[RenderFlex.move].
class MultiChildRenderObjectElement extends RenderObjectElement {
  MultiChildRenderObjectElement(MultiChildRenderObjectWidget super.widget);

  /// The current children, excluding any that have been forgotten.
  Iterable<Element> get children =>
      _children.where((child) => !_forgottenChildren.contains(child));

  late List<Element> _children;

  // Children removed reentrantly during updateChildren are parked here so the
  // diff treats them as absent without an O(n^2) list rewrite.
  final Set<Element> _forgottenChildren = {};

  @override
  void insertRenderObjectChild(RenderObject child, Element? slot) {
    (_renderObject! as RenderFlex)
        .insert(child as RenderBox, after: slot?.renderObject as RenderBox?);
  }

  @override
  void moveRenderObjectChild(
      RenderObject child, Element? oldSlot, Element? newSlot) {
    (_renderObject! as RenderFlex)
        .move(child as RenderBox, after: newSlot?.renderObject as RenderBox?);
  }

  @override
  void removeRenderObjectChild(RenderObject child, Element? slot) {
    (_renderObject! as RenderFlex).remove(child as RenderBox);
  }

  @override
  void visitChildren(void Function(Element child) visitor) {
    for (var child in _children) {
      if (!_forgottenChildren.contains(child)) {
        visitor(child);
      }
    }
  }

  @override
  void forgetChild(Element child) {
    assert(_children.contains(child));
    assert(!_forgottenChildren.contains(child));
    _forgottenChildren.add(child);
    super.forgetChild(child);
  }

  @override
  void mount(Element? parent, Object? newSlot) {
    super.mount(parent, newSlot);
    var widgetChildren = (widget as MultiChildRenderObjectWidget).children;
    var children = List<Element?>.filled(widgetChildren.length, null);
    Element? previousChild;
    for (var i = 0; i < children.length; i += 1) {
      var newChild = inflateWidget(widgetChildren[i], previousChild);
      children[i] = newChild;
      previousChild = newChild;
    }
    _children = children.cast<Element>();
  }

  @override
  void update(MultiChildRenderObjectWidget newWidget) {
    super.update(newWidget);
    _children = updateChildren(
      _children,
      (widget as MultiChildRenderObjectWidget).children,
      forgottenChildren: _forgottenChildren,
    );
    _forgottenChildren.clear();
  }
}
