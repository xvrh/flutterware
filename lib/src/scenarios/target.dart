import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Resolves a verb's polymorphic target to a `Finder`.
///
/// A `Finder` passes through, a `String` is visible text, a `Key`, an
/// `IconData` and a `Type` mean the obvious thing, and a [Target] says the
/// things that vocabulary cannot.
///
/// `dynamic` is a deliberate exception to the house no-dynamic preference:
/// `tap('NEXT')` / `tap(Icons.add)` / `tap(Keys.next)` read too well to give
/// up.
Finder finderForTarget(dynamic target) {
  return switch (target) {
    Finder() => target,
    Target() => target.toFinder(),
    String() => find.text(target, findRichText: true),
    Key() => find.byKey(target),
    IconData() => find.byIcon(target),
    Type() => find.byType(target),
    _ => throw ArgumentError(
      'a scenario target is a Finder, a String, a Key, an IconData, a Type '
      'or a Target — got ${target.runtimeType}',
    ),
  };
}

/// How a verb's target reads back to a human — quoted when it is the visible
/// text the author wrote, bare otherwise.
///
/// One function because two places need the same spelling: the error a verb
/// throws when its target matches nothing or several, and the target recorded
/// on the captured step. A step that says `tap "Pay"` and an error that says
/// `tap 'Pay'` would be describing the same line two ways.
///
/// A `ValueKey` gets its value rather than its `toString`, which is
/// `[<'shop.getStarted'>]` — three kinds of bracket around the only part
/// anybody wrote. Said as `key 'shop.getStarted'` it stays distinct from the
/// quoted visible-text form, which means something else entirely.
String describeTarget(dynamic target) => switch (target) {
  String() => '"$target"',
  ValueKey(:var value) => "key '$value'",
  _ => '$target',
};

/// The target and index inside a `Target.nth`, or null for anything else.
///
/// Internal, and it exists for one message: `Finder.at(i)` is
/// `candidates.elementAt(i)`, so an index past the end throws a `RangeError`
/// out of the evaluate rather than missing the way every other target misses.
/// Writing the refusal that deserves needs the count of what the *inner*
/// target matched, which only the caller of [Target.nth] can ask for and only
/// this can hand it.
({Object target, int index})? nthPartsOf(dynamic target) =>
    target is _Nth ? (target: target.target, index: target.index) : null;

/// The targets the plain vocabulary cannot express: the ones that need a
/// property other than visible text, a scope, or an index.
///
/// ```dart
/// await s.tap(Target.label('Add to cart'));       // semantics label
/// await s.tap(Target.tooltip('Delete'));
/// await s.tap(Target.within(ShopKeys.cart, 'Buy'));
/// await s.tap(Target.nth('Buy', 1));              // the second one
/// ```
///
/// Anything here composes: the scope and the index take targets of their own,
/// so `Target.nth(Target.within(card, 'Buy'), 0)` says what it looks like.
sealed class Target {
  const Target();

  /// By semantics label — the only handle on an icon button that carries no
  /// text. Scenarios turn semantics on by themselves for this, since the
  /// underlying finder throws without them.
  const factory Target.label(String label) = _Label;

  /// By tooltip message.
  const factory Target.tooltip(String message) = _Tooltip;

  /// Visible text *containing* [text], where the plain `String` form matches
  /// the whole string.
  const factory Target.containing(String text) = _Containing;

  /// [child] as found inside [scope] — the scoped lookup that turns "the Buy
  /// button of *this* card" from a `find.descendant` incantation into a line
  /// that reads. [scope] matches itself too, so scoping to a `ListTile` and
  /// asking for that same tile finds it.
  const factory Target.within(Object scope, Object child) = _Within;

  /// The [index]th match of [target], zero-based — for the deliberate
  /// ambiguity a verb would otherwise refuse.
  const factory Target.nth(Object target, int index) = _Nth;

  /// The widget at a point, in the coordinates every box in an observation is
  /// reported in.
  ///
  /// **What to reach for when a control has no words.** Six or seven of the
  /// forty-odd things on a real screen carry no label, no text and no tooltip
  /// — icon buttons, mostly — and until this there was no way to name one at
  /// all. It is also how a screen item is acted on: the host turns
  /// `{"item": 20}` into the centre of that item's box.
  ///
  /// It resolves through the same ladder as every other target rather than
  /// tapping blind coordinates: the point picks the widget, and being covered,
  /// offscreen or gone is refused exactly as it would be for a text target.
  const factory Target.at(double x, double y) = _At;

  Finder toFinder();

  /// Whether resolving this needs the semantics tree, which a scenario turns
  /// on lazily — it is not free, and it changes what the app builds.
  bool get needsSemantics => false;
}

class _At extends Target {
  const _At(this.x, this.y);

  final double x;
  final double y;

  @override
  Finder toFinder() {
    var hit = _hitAt(x, y);
    if (hit == null) return find.byElementPredicate((_) => false);
    // Several widgets can share one render object — a `Padding` under a
    // `Semantics` under a builder all report the same box — so `.first` takes
    // the outermost, which is the one a click means and the one the tree
    // reports at that position.
    return find
        .byElementPredicate((element) => identical(element.renderObject, hit))
        .first;
  }

  /// The innermost render object the framework's own hit test reaches.
  ///
  /// The framework's, not a rectangle comparison: this has to agree with what
  /// a real pointer would touch, so transforms, clips and `IgnorePointer` are
  /// all in play and only the real hit test knows about them.
  static RenderObject? _hitAt(double x, double y) {
    var view = WidgetsBinding.instance.renderViews.firstOrNull;
    if (view == null) return null;
    var result = BoxHitTestResult();
    view.hitTest(result, position: Offset(x, y));
    for (var entry in result.path) {
      if (entry.target case RenderObject render) return render;
    }
    return null;
  }

  @override
  String toString() => 'Target.at($x, $y)';
}

class _Label extends Target {
  const _Label(this.label);

  final String label;

  @override
  bool get needsSemantics => true;

  @override
  Finder toFinder() => find.bySemanticsLabel(label);

  @override
  String toString() => 'Target.label("$label")';
}

class _Tooltip extends Target {
  const _Tooltip(this.message);

  final String message;

  @override
  Finder toFinder() => find.byTooltip(message);

  @override
  String toString() => 'Target.tooltip("$message")';
}

class _Containing extends Target {
  const _Containing(this.text);

  final String text;

  @override
  Finder toFinder() => find.textContaining(text, findRichText: true);

  @override
  String toString() => 'Target.containing("$text")';
}

class _Within extends Target {
  const _Within(this.scope, this.child);

  final Object scope;
  final Object child;

  @override
  bool get needsSemantics =>
      (scope is Target && (scope as Target).needsSemantics) ||
      (child is Target && (child as Target).needsSemantics);

  @override
  Finder toFinder() => find.descendant(
    of: finderForTarget(scope),
    matching: finderForTarget(child),
    matchRoot: true,
  );

  @override
  String toString() =>
      'Target.within(${describeTarget(scope)}, ${describeTarget(child)})';
}

class _Nth extends Target {
  const _Nth(this.target, this.index);

  final Object target;
  final int index;

  @override
  bool get needsSemantics =>
      target is Target && (target as Target).needsSemantics;

  @override
  Finder toFinder() => finderForTarget(target).at(index);

  @override
  String toString() => 'Target.nth(${describeTarget(target)}, $index)';
}
