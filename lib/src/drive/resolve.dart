import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../scenarios/target.dart';

/// The four ways the actionability ladder refuses a target.
///
/// The kind matters to a live driver: on a screen mid-transition every one of
/// these can be transient — a route still animating holds an `IgnorePointer`
/// up (`covered`), and both pages are in the tree at once (`multiple`) — so
/// the drive verbs retry all of them until their deadline, where a scenario
/// under fake time fails immediately because its screen is already settled.
enum TargetFailure { notFound, multiple, covered, offscreen }

/// A refusal from [TargetResolver] — the message is the whole story, written
/// to say what to do rather than dump matching render objects.
class TargetError implements Exception {
  TargetError(this.failure, this.message);

  final TargetFailure failure;
  final String message;

  @override
  String toString() => message;
}

/// The wording of a refusal, flavored per host.
///
/// The logic of the ladder is shared; the sentences are not quite: a scenario
/// speaks of `s.tap` and offers `s.tester` as the escape hatch, a live driver
/// has no receiver prefix and no raw tester to offer. Everything else is
/// deliberately identical, so a failure reads the same to a scenario author
/// and to an agent driving a live app.
class TargetMessages {
  const TargetMessages({this.prefix = '', this.coveredEscapeHatch = ''});

  /// Goes in front of verb names in messages — `'s.'` for scenarios, where
  /// the reader will retype the verb on a receiver called `s`.
  final String prefix;

  /// Appended to the covered refusal — scenarios offer `s.tester` here.
  final String coveredEscapeHatch;

  String notFound(String verb, String described, String? screen) =>
      'nothing matches $described, which `$prefix$verb` needs. A widget '
      'further down a lazy list is not built yet — `${prefix}scrollTo` walks '
      'to it.${screen == null ? '' : '\nVisible text: $screen'}';

  String multiple(int count, String verb, String described) =>
      '$count widgets match $described, and `$prefix$verb` needs one. '
      'Narrow it: give the widget a Key and use that, or pass a Finder — '
      '`finder.first`, `find.descendant(of: …, matching: …)`.';

  String covered(String verb, String described) =>
      '$described is on screen, but `$prefix$verb` at its center would not '
      'reach it — another widget covers it, or an IgnorePointer/'
      'AbsorbPointer swallows the pointer.$coveredEscapeHatch';

  String offscreen(String described, Offset center) =>
      '$described sits off screen at $center and nothing scrolls it '
      'into view.';

  String nothingScrolls(Object? within) => within == null
      ? 'nothing on screen scrolls, so `${prefix}scrollTo` has nothing to '
            'walk.'
      : 'nothing under $within scrolls, so `${prefix}scrollTo` has nothing '
            'to walk.';

  String scrollExhausted(int maxScrolls, double step, String described) =>
      'scrolled $maxScrolls times by $step without reaching $described. '
      'Wrong direction (try a negative step), wrong scrollable (name one '
      'with `within:`), or it is not in this list at all.';
}

/// Resolves a verb's target and insists it names exactly one widget the
/// pointer can actually reach — the ladder every pointer verb climbs, over
/// any [WidgetController]: a `WidgetTester` under fake time or a live
/// controller over the real binding.
///
/// Found but unreachable usually means "built but below the fold" — a
/// `SingleChildScrollView`, a list child inside cache extent — so the ladder
/// first scrolls it into view, as the user it stands in for would. What
/// scrolling cannot fix is refused loudly, with the kind on the error so a
/// live caller can decide what is worth retrying.
class TargetResolver {
  TargetResolver(
    this.controller, {
    this.messages = const TargetMessages(),
    this._pump,
    this.ensureSemantics,
    this.describeScreen,
  });

  final WidgetController controller;
  final TargetMessages messages;

  /// One pump after `ensureVisible`, so the scroll it triggered is applied
  /// before the recheck. Injected because pumping is the one thing the two
  /// bindings do differently — a live pump must survive a hidden window.
  final Future<void> Function()? _pump;

  /// Called before resolving a [Target] that needs the semantics tree, which
  /// is not free and is turned on lazily by the host.
  final Future<void> Function()? ensureSemantics;

  /// One line describing what is on screen, for the nothing-matches message —
  /// the first thing whoever wrote the target needs to see.
  final String Function()? describeScreen;

  Future<Finder> resolve(dynamic target, String verb) async {
    if (target is Target && target.needsSemantics) {
      await ensureSemantics?.call();
    }
    var finder = finderForTarget(target);
    var count = finder.evaluate().length;
    var described = describeTarget(target);
    if (count == 0) {
      throw TargetError(
        TargetFailure.notFound,
        messages.notFound(verb, described, describeScreen?.call()),
      );
    }
    if (count > 1) {
      throw TargetError(
        TargetFailure.multiple,
        messages.multiple(count, verb, described),
      );
    }
    await _ensureReachable(finder, described, verb);
    return finder;
  }

  Future<void> _ensureReachable(
    Finder finder,
    String described,
    String verb,
  ) async {
    if (_reaches(finder)) return;
    // On a target with no scrollable ancestor `Scrollable.ensureVisible` is a
    // no-op, so the recheck decides — no case to distinguish here.
    await controller.ensureVisible(finder);
    await (_pump?.call() ?? controller.pump());
    // That pump can rebuild the tree from under the finder — the
    // mid-transition flicker this whole ladder exists to survive. A target
    // that vanished is the refusal the retry loop knows how to pump through,
    // not a bare `StateError` out of `.single` below.
    if (finder.evaluate().length != 1) {
      throw TargetError(
        TargetFailure.notFound,
        messages.notFound(verb, described, describeScreen?.call()),
      );
    }
    if (_reaches(finder)) return;
    var render = finder.evaluate().single.renderObject! as RenderBox;
    var center = render.localToGlobal(render.size.center(Offset.zero));
    var bounds = Offset.zero & controller.binding.renderViews.single.size;
    if (bounds.contains(center)) {
      throw TargetError(
        TargetFailure.covered,
        messages.covered(verb, described),
      );
    }
    throw TargetError(
      TargetFailure.offscreen,
      messages.offscreen(described, center),
    );
  }

  /// Whether a pointer event at the target's center would reach it — the
  /// check `flutter_test`'s `warnIfMissed` makes, as a boolean.
  bool _reaches(Finder finder) {
    var render = finder.evaluate().single.renderObject;
    // No box to aim at: leave it to the underlying verb, whose own errors
    // name the shape problem better than a reachability check can.
    if (render is! RenderBox || !render.hasSize) return true;
    var center = render.localToGlobal(render.size.center(Offset.zero));
    // The viewId is passed explicitly: `hitTestOnBinding`'s default comes
    // from the controller's test-typed `view` getter, which throws on a live
    // binding (measured — see 2026-08-11-run-drive-spike-findings.md).
    var viewId = controller.binding.renderViews.single.flutterView.viewId;
    var result = controller.hitTestOnBinding(center, viewId: viewId);
    return result.path.any(
      (entry) => isRenderObjectAncestorOfTarget(render, entry.target),
    );
  }
}

/// Longest string [visibleTextsOf] reports before truncating with an
/// ellipsis. Screens that render logs or protocol dumps put whole essays in
/// single `Text` widgets, and every one of them rides every reply; the cap
/// bounds the worst screen while leaving ordinary UI copy whole. A truncated
/// text still resolves as a target via `containing` with any prefix.
const visibleTextCap = 200;

/// Every `Text` and `EditableText` currently in the tree, in tree order —
/// the text projection of the screen an agent reads next to the pixels, and
/// the material of the nothing-matches message. Strings longer than
/// [visibleTextCap] are truncated with a trailing `…`.
List<String> visibleTextsOf(WidgetController controller) => [
  for (var widget in controller.widgetList(
    find.byWidgetPredicate((w) => w is Text || w is EditableText),
  ))
    _capped(switch (widget) {
      Text(:var data, :var textSpan) => data ?? textSpan?.toPlainText() ?? '',
      EditableText(:var controller) => controller.text,
      _ => '',
    }),
];

String _capped(String text) => text.length <= visibleTextCap
    ? text
    : '${text.substring(0, visibleTextCap)}…';
