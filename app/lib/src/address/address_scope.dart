import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutterware/plugins.dart';

/// What a widget subscribed to.
///
/// The reason this exists rather than a `ValueListenable` per thing: a widget
/// that reads one parameter should rebuild when *that* parameter changes and
/// never otherwise. Buckets maintained by hand — "identity" versus "axes" —
/// drift the moment someone adds a third kind of state. An aspect is whatever
/// the widget actually read, so the granularity is a consequence of the code
/// rather than a rule to remember.
///
/// String-keyed inside so the set arithmetic is cheap; typed outside so a
/// misspelled aspect is a compile error rather than a widget that never
/// rebuilds.
class AddressAspect {
  const AddressAspect._(this._key);

  final String _key;

  /// One segment of this level, by index into what this level can see.
  static AddressAspect segment(int index) => AddressAspect._('seg:$index');

  /// Every segment of this level and below.
  static const segments = AddressAspect._('segs');

  /// One parameter in this level's namespace.
  static AddressAspect param(String name) => AddressAspect._('param:$name');

  /// Every parameter in this level's namespace.
  static const params = AddressAspect._('params');

  /// Every parameter in a *named* namespace, whichever level owns it.
  ///
  /// For state logic that sits above the controls it belongs to: the catalog
  /// panel drives the session, but the axis controls that write `axis.*` are
  /// further down. Reading them from here keeps the granularity — it still
  /// rebuilds only when something under that prefix moves — without inventing a
  /// widget whose only job is to be at the right depth.
  static AddressAspect paramsIn(String namespace) =>
      AddressAspect._('params:$namespace');

  /// Anything at all.
  ///
  /// What a nested [AddressScope] subscribes to, because it re-derives its own
  /// view from the whole thing. Rebuilding a scope is cheap — it rewraps a
  /// child it already has — so this is the right answer *there* and the wrong
  /// one nearly everywhere else.
  static const whole = AddressAspect._('whole');

  @override
  bool operator ==(Object other) =>
      other is AddressAspect && other._key == _key;

  @override
  int get hashCode => _key.hashCode;

  @override
  String toString() => 'AddressAspect($_key)';
}

/// A window onto the address: the part one level of the tree can see.
///
/// Two kinds of eating, because the address has two kinds of state.
/// **Segments are eaten positionally** — a level consumes a prefix and hands
/// the rest down, so nothing below it needs to know how deep it sits.
/// **Parameters are eaten by namespace** — `knob.count` belongs to whichever
/// level declared `knob`, wherever that level happens to be.
///
/// Where a namespace sits in the tree is what decides how long its values live.
/// A namespace declared *below* a segment cannot survive that segment changing;
/// one declared above it is untouched. That is the whole lifetime rule, and it
/// is nesting order rather than anything anyone has to enforce.
@immutable
class AddressView {
  const AddressView(this.full, {this.segmentOffset = 0, this.namespace});

  /// The address in its entirety. Present at every level because a write has
  /// to produce a whole address, and because the bar wants to show one.
  final Address full;

  /// How many segments the levels above consumed.
  final int segmentOffset;

  /// The parameter namespace this level owns, or null for the un-namespaced
  /// ones.
  final String? namespace;

  /// What is left for this level and everything below it.
  List<String> get segments => segmentOffset >= full.segments.length
      ? const []
      : full.segments.sublist(segmentOffset);

  /// The segment at [index] *of this level*, or null past the end.
  String? segment(int index) {
    var at = segmentOffset + index;
    return index < 0 || at >= full.segments.length ? null : full.segments[at];
  }

  String? param(String name) => full.axes[keyFor(name)];

  /// Everything in this level's namespace, with the prefix taken off.
  Map<String, String> get params {
    var prefix = namespace == null ? null : '$namespace.';
    return {
      for (var entry in full.axes.entries)
        if (prefix == null
            ? !entry.key.contains('.')
            : entry.key.startsWith(prefix))
          (prefix == null ? entry.key : entry.key.substring(prefix.length)):
              entry.value,
    };
  }

  /// A local name as it is written in the address.
  String keyFor(String name) => namespace == null ? name : '$namespace.$name';

  /// The view one level down.
  ///
  /// A namespace *replaces* rather than compounds: `?knob.count` stays two
  /// words deep however many scopes are between it and the root, because the
  /// address is read by people and written into filenames. Passing null keeps
  /// whatever the parent owned.
  AddressView nest({int eat = 0, String? namespace}) => AddressView(
    full,
    segmentOffset: segmentOffset + eat,
    namespace: namespace ?? this.namespace,
  );

  @override
  bool operator ==(Object other) =>
      other is AddressView &&
      other.full == full &&
      other.segmentOffset == segmentOffset &&
      other.namespace == namespace;

  @override
  int get hashCode => Object.hash(full, segmentOffset, namespace);

  @override
  String toString() =>
      'AddressView($full, +$segmentOffset${namespace == null ? '' : ', $namespace.*'})';
}

/// Reading and writing one level's part of the address.
///
/// Writes are relative and always produce a whole address, which is what keeps
/// the shell the only owner: a level says what changed about *its* part, and
/// the address that comes back down is the single source everything re-derives
/// from. Nobody holds a copy.
@immutable
class AddressHandle {
  const AddressHandle(this.view, this._write);

  final AddressView view;
  final void Function(Address) _write;

  Address get full => view.full;
  List<String> get segments => view.segments;
  String? segment(int index) => view.segment(index);
  String? param(String name) => view.param(name);
  Map<String, String> get params => view.params;

  /// Goes somewhere else entirely. The escape hatch a search hit and a pasted
  /// address use; a level moving within itself wants [setSegments].
  void go(Address destination) => _write(destination);

  /// Replaces this level's segments, keeping everything above.
  ///
  /// Deeper segments go with them, and that is the point rather than a
  /// limitation: changing the package cannot leave the previous package's entry
  /// behind, because it names nothing there.
  void setSegments(List<String> segments) => update(segments: segments);

  /// Sets one parameter in this level's namespace. Null removes it.
  void setParam(String name, String? value) => update(params: {name: value});

  /// Sets several at once, so a control that moves two together costs one
  /// address and one rebuild.
  void setParams(Map<String, String?> values) => update(params: values);

  /// Segments and parameters in **one** write.
  ///
  /// A panel catching the address up on several things at once — the entry it
  /// settled on *and* the device it is framed in — would otherwise navigate
  /// twice, and the address between the two writes names a state that never
  /// existed. Anything reading it in that gap acts on a half-applied address.
  ///
  /// Null values remove a parameter; a null [segments] or [params] leaves that
  /// half alone. Writes nothing when the result is the address it already was,
  /// so a level restating where it is costs no navigation.
  ///
  /// [drop] empties whole namespaces, which is **how a lifetime is expressed**.
  /// A namespace belonging to something a segment names — a demo's knobs, under
  /// the entry — cannot outlive a change to that segment, and the write that
  /// changes it is the only place that knows. The nesting says which namespace
  /// sits below which segment; this is where that stops being a diagram.
  void update({
    List<String>? segments,
    Map<String, String?>? params,
    Set<String> drop = const {},
  }) {
    var next = view.full;

    if (drop.isNotEmpty) {
      next = next.copyWith(
        axes: {
          for (var entry in next.axes.entries)
            if (!drop.any((ns) => entry.key.startsWith('$ns.')))
              entry.key: entry.value,
        },
      );
    }

    if (segments != null) {
      next = next.copyWith(
        segments: [...view.full.segments.take(view.segmentOffset), ...segments],
      );
    }

    if (params != null) {
      var axes = {...next.axes};
      for (var entry in params.entries) {
        var key = view.keyFor(entry.key);
        if (entry.value == null) {
          axes.remove(key);
        } else {
          axes[key] = entry.value!;
        }
      }
      next = next.copyWith(axes: axes);
    }

    if (next != view.full) _write(next);
  }

  AddressHandle nest({int eat = 0, String? namespace}) =>
      AddressHandle(view.nest(eat: eat, namespace: namespace), _write);

  @override
  bool operator ==(Object other) =>
      other is AddressHandle && other.view == view && other._write == _write;

  @override
  int get hashCode => Object.hash(view, _write);
}

/// Installs the top of the tree: the whole address, nothing eaten yet.
///
/// Stateful because it listens rather than being rebuilt from above. That is
/// load-bearing — [build] rewraps the *same* child widget instance every time,
/// so an address change rebuilds this one widget and then only the dependents
/// whose aspect moved. If the root were rebuilt by its parent instead, the
/// child would be a new widget each time and the whole subtree would go with
/// it, which is exactly the rebuild this design exists to avoid.
class AddressRoot extends StatefulWidget {
  const AddressRoot({
    super.key,
    required this.address,
    required this.onChanged,
    required this.child,
  });

  final ValueListenable<Address> address;

  /// Where a write goes. The shell, normally — it validates the destination and
  /// remembers it against its worktree, neither of which belongs here.
  final ValueChanged<Address> onChanged;

  final Widget child;

  @override
  State<AddressRoot> createState() => _AddressRootState();
}

class _AddressRootState extends State<AddressRoot> {
  @override
  void initState() {
    super.initState();
    widget.address.addListener(_moved);
  }

  @override
  void didUpdateWidget(AddressRoot old) {
    super.didUpdateWidget(old);
    if (old.address != widget.address) {
      old.address.removeListener(_moved);
      widget.address.addListener(_moved);
    }
  }

  @override
  void dispose() {
    widget.address.removeListener(_moved);
    super.dispose();
  }

  void _moved() => setState(() {});

  @override
  Widget build(BuildContext context) => _AddressModel(
    handle: AddressHandle(AddressView(widget.address.value), widget.onChanged),
    child: widget.child,
  );
}

/// One level of the tree: eats its part, exposes the rest.
///
/// What nesting enforces is **writes**: [AddressHandle.setSegments] rebuilds the
/// address from this level's offset, so a level physically cannot move anything
/// above it. Reads are not sealed — [AddressHandle.full] stays available at
/// every depth, because a write has to produce a whole address and the address
/// bar has to display one. So the plugin boundary [Address] describes is
/// enforced in the direction that can do damage and left open in the direction
/// that cannot.
class AddressScope extends StatelessWidget {
  const AddressScope({
    super.key,
    this.eat = 0,
    this.namespace,
    required this.child,
  });

  /// How many segments this level consumes.
  final int eat;

  /// The parameter namespace this level owns, if it owns one.
  final String? namespace;

  final Widget child;

  /// The nearest handle, subscribed to [AddressAspect.whole].
  ///
  /// Rebuilds on any change, which makes it the wrong choice for a leaf. Read
  /// [segment], [segments] or [param] instead — each subscribes to just itself.
  static AddressHandle of(BuildContext context) =>
      _model(context, AddressAspect.whole).handle;

  static AddressHandle? maybeOf(BuildContext context) =>
      _maybeModel(context, AddressAspect.whole)?.handle;

  /// The handle **without subscribing** — for writing from a callback, where
  /// depending on what you are about to change would be a rebuild for nothing.
  static AddressHandle write(BuildContext context) {
    var model = context.getInheritedWidgetOfExactType<_AddressModel>();
    assert(model != null, 'No AddressScope above this context.');
    return model!.handle;
  }

  static String? segment(BuildContext context, int index) =>
      _model(context, AddressAspect.segment(index)).handle.segment(index);

  static List<String> segments(BuildContext context) =>
      _model(context, AddressAspect.segments).handle.segments;

  static String? param(BuildContext context, String name) =>
      _model(context, AddressAspect.param(name)).handle.param(name);

  /// Every parameter of this level's namespace, or of [namespace] when one is
  /// named. See [AddressAspect.paramsIn].
  static Map<String, String> params(BuildContext context, {String? namespace}) {
    if (namespace == null) {
      return _model(context, AddressAspect.params).handle.params;
    }
    return _model(
      context,
      AddressAspect.paramsIn(namespace),
    ).handle.view.nest(namespace: namespace).params;
  }

  static _AddressModel _model(BuildContext context, AddressAspect aspect) {
    var model = _maybeModel(context, aspect);
    assert(model != null, 'No AddressScope above this context.');
    return model!;
  }

  static _AddressModel? _maybeModel(
    BuildContext context,
    AddressAspect aspect,
  ) => InheritedModel.inheritFrom<_AddressModel>(context, aspect: aspect);

  @override
  Widget build(BuildContext context) => _AddressModel(
    handle: of(context).nest(eat: eat, namespace: namespace),
    child: child,
  );
}

class _AddressModel extends InheritedModel<AddressAspect> {
  const _AddressModel({required this.handle, required super.child});

  final AddressHandle handle;

  AddressView get view => handle.view;

  @override
  bool updateShouldNotify(_AddressModel old) => old.view != view;

  @override
  bool updateShouldNotifyDependent(
    _AddressModel old,
    Set<AddressAspect> aspects,
  ) {
    for (var aspect in aspects) {
      if (_changed(old.view, view, aspect)) return true;
    }
    return false;
  }
}

/// Whether [aspect] reads differently between two views. The whole of the
/// granularity, in one function.
bool _changed(AddressView before, AddressView after, AddressAspect aspect) {
  var key = aspect._key;
  if (key == 'whole') return before != after;
  if (key == 'segs') return !listEquals(before.segments, after.segments);
  if (key == 'params') return !mapEquals(before.params, after.params);
  if (key.startsWith('params:')) {
    var namespace = key.substring(7);
    return !mapEquals(
      before.nest(namespace: namespace).params,
      after.nest(namespace: namespace).params,
    );
  }
  if (key.startsWith('seg:')) {
    var index = int.parse(key.substring(4));
    return before.segment(index) != after.segment(index);
  }
  if (key.startsWith('param:')) {
    var name = key.substring(6);
    return before.param(name) != after.param(name);
  }
  // An aspect this file does not know about is a bug, and rebuilding is the
  // safe way to be wrong.
  return true;
}
