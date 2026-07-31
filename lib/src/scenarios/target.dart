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

  Finder toFinder();

  /// Whether resolving this needs the semantics tree, which a scenario turns
  /// on lazily — it is not free, and it changes what the app builds.
  bool get needsSemantics => false;
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
  String toString() => 'Target.within($scope, $child)';
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
  String toString() => 'Target.nth($target, $index)';
}
