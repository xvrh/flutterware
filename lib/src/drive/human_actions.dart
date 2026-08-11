import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' show Tooltip;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'resolve.dart' show visibleTextCap;

/// One human gesture the guest saw between two tool steps.
class HumanAction {
  HumanAction({required this.at, required this.verb, required this.target});

  final DateTime at;

  /// `tap` or `longPress` — the two gestures a down-up pair within slop can
  /// be. Scrolls and drags are deliberately not recorded: a fling is a dozen
  /// pointer sequences and none of them is a decision worth journaling.
  final String verb;

  /// The nearest nameable widget under the finger, in the same spelling the
  /// drive targets use — `"Pay"`, `key 'shop.next'` — or the bare position
  /// when nothing named was hit.
  final String target;

  Map<String, Object?> toJson() => {
    'at': at.toUtc().toIso8601String(),
    'verb': verb,
    'target': target,
  };
}

/// Records the human's taps in the driven app, so the journal can carry
/// `actor: human` entries between the tool steps.
///
/// The co-driving premise made the journal one-eyed: every agent step lands
/// with its picture, but what the human did between them was invisible — the
/// agent only saw that the screen had moved. This is the mechanism the design
/// noted as known and cheap: a global pointer route, a hit test on pointer-up,
/// the nearest nameable widget as the target.
///
/// Pull, like everything else on this wire: actions buffer here and ride the
/// next act/observe reply as a since-last-step delta. Nothing pushes.
class HumanActions {
  HumanActions({this.cap = 100});

  /// Buffered actions past this are counted, not kept — the take reports how
  /// many were dropped rather than silently forgetting them.
  final int cap;

  final _records = <HumanAction>[];
  var _dropped = 0;
  var _installed = false;
  final _downs = <int, PointerDownEvent>{};

  /// True while a drive verb is injecting pointer events, which arrive on the
  /// same global route as real ones. Without this, every agent tap would be
  /// journaled twice — once as its step, once as a phantom human.
  var suppress = false;

  /// Adds the global route. Call once, with the binding initialized.
  void install() {
    if (_installed) return;
    _installed = true;
    GestureBinding.instance.pointerRouter.addGlobalRoute(handlePointerEvent);
  }

  /// The route itself — public so a test can feed events without a binding
  /// route registration of its own.
  void handlePointerEvent(PointerEvent event) {
    if (suppress) return;
    switch (event) {
      case PointerDownEvent():
        _downs[event.pointer] = event;
      case PointerUpEvent():
        var down = _downs.remove(event.pointer);
        if (down == null) return;
        if ((event.position - down.position).distance > kTouchSlop) return;
        var held = event.timeStamp - down.timeStamp;
        _add(
          HumanAction(
            at: DateTime.now(),
            verb: held >= kLongPressTimeout ? 'longPress' : 'tap',
            target: describeHit(down.position, viewId: down.viewId),
          ),
        );
      case PointerCancelEvent():
        _downs.remove(event.pointer);
    }
  }

  void _add(HumanAction action) {
    if (_records.length >= cap) {
      _dropped++;
      return;
    }
    _records.add(action);
  }

  /// Everything recorded since the last take, oldest first, cleared on the
  /// way out. A drop past [cap] becomes a visible final entry, per the
  /// stated-caps rule.
  List<Map<String, Object?>> take() {
    var out = [for (var record in _records) record.toJson()];
    if (_dropped > 0) {
      out.add(
        HumanAction(
          at: DateTime.now(),
          verb: 'dropped',
          target: '$_dropped more past the $cap-action cap',
        ).toJson(),
      );
    }
    _records.clear();
    _dropped = 0;
    return out;
  }
}

/// Names what a pointer at [position] would land on: hit test, then walk from
/// the leaf element upward for the first widget a drive target could spell —
/// visible text, a string key, a tooltip, a semantics label.
String describeHit(Offset position, {int? viewId}) {
  var binding = WidgetsBinding.instance;
  var view = viewId != null
      ? binding.renderViews
            .where((v) => v.flutterView.viewId == viewId)
            .firstOrNull
      : binding.renderViews.firstOrNull;
  if (view == null) return _at(position);
  var result = HitTestResult();
  binding.hitTestInView(result, position, view.flutterView.viewId);
  for (var entry in result.path) {
    var target = entry.target;
    if (target is! RenderObject) continue;
    if (target.debugCreator case DebugCreator(:var element)) {
      var name = _nameFrom(element);
      if (name != null) return name;
    }
    // Only the leaf-most render object's element is walked: it already
    // visits every ancestor, and later path entries are those ancestors.
    break;
  }
  return _at(position);
}

String _at(Offset position) =>
    'at (${position.dx.round()}, ${position.dy.round()})';

String? _nameFrom(Element leaf) {
  String? name;
  var hops = 0;
  bool visit(Element element) {
    // Deep enough for a Material control's internals (an IconButton is ~40
    // elements of ripple and style between its RenderParagraph and its key),
    // shallow enough not to name the page for a tap on its background.
    if (++hops > 100) return false;
    switch (element.widget) {
      case Text(:var data, :var textSpan):
        name = '"${_cap(data ?? textSpan?.toPlainText() ?? '')}"';
        return false;
      case Tooltip(:var message?):
        name = "tooltip '$message'";
        return false;
      case Semantics(properties: SemanticsProperties(:var label?))
          when label.isNotEmpty:
        name = "label '${_cap(label)}'";
        return false;
      case Widget(key: ValueKey<String>(:var value)):
        name = "key '$value'";
        return false;
    }
    return true;
  }

  if (visit(leaf)) leaf.visitAncestorElements(visit);
  return name;
}

String _cap(String text) => text.length <= visibleTextCap
    ? text
    : '${text.substring(0, visibleTextCap)}…';
