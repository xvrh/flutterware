import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../scenarios/target.dart';
import 'live_settle.dart';
import 'resolve.dart';

/// What one drive verb did — the engine half of a journal step. The wire and
/// observation bundle live with the guest extensions, not here.
class DriveStep {
  DriveStep({
    required this.verb,
    required this.settle,
    required this.elapsed,
    this.target,
    this.attempts = 1,
  });

  final String verb;
  final String? target;

  /// Resolve attempts the actionability retry ladder spent, 1 when the first
  /// try reached the target.
  final int attempts;

  final LiveSettleResult settle;

  /// Whole transaction: retries + act + settle.
  final Duration elapsed;

  Map<String, Object?> toJson() => {
    'verb': verb,
    if (target != null) 'target': target,
    'attempts': attempts,
    'elapsedMs': elapsed.inMilliseconds,
    'settle': settle.toJson(),
  };
}

/// `LiveWidgetController` with a pump that survives a hidden window: frames
/// are forced when the platform has disabled them, and every wait is capped
/// so nothing here can hang the verb that pumps.
class _DriveController extends LiveWidgetController {
  _DriveController(super.binding);

  @override
  Future<void> pump([Duration? duration]) async {
    if (duration != null) {
      await Future<void>.delayed(duration);
    }
    binding.scheduleFrame();
    if (!binding.framesEnabled) binding.scheduleForcedFrame();
    await Future.any([
      binding.endOfFrame,
      Future<void>.delayed(const Duration(milliseconds: 250)),
    ]);
  }
}

/// The live half of the verb engine: scenarios' vocabulary — same targets,
/// same actionability ladder, same refusal wording — executed against a
/// running app's real `WidgetsBinding`.
///
/// The one behavioral difference from a scenario is time. A scenario's screen
/// is settled by construction when a verb runs; a live screen is mid-flight —
/// a route transition holds an `IgnorePointer` up and both pages are briefly
/// in the tree — so every refusal here is treated as possibly transient:
/// resolve + reachability retry until [actTimeout], settling between attempts
/// (a plain wait advances zero frames on a hidden window), and only the
/// deadline surfaces the error. Measured: taps land on the first frame a
/// transition releases them (`2026-08-11-run-drive-spike-findings.md`).
class Drive {
  Drive({WidgetsBinding? binding})
    : controller = _DriveController(binding ?? WidgetsBinding.instance);

  final LiveWidgetController controller;

  /// Deadline for the resolve/reachability retry ladder.
  var actTimeout = const Duration(seconds: 3);

  /// Settle budget between retry attempts.
  var retryPump = const Duration(milliseconds: 60);

  /// Default settle budget after an act.
  var settleBudget = const Duration(milliseconds: 800);

  SemanticsHandle? _semantics;

  late final TargetResolver _resolver = TargetResolver(
    controller,
    describeScreen: _describeScreen,
    ensureSemantics: () async {
      _semantics ??= controller.binding.ensureSemantics();
      await settleLive(budget: const Duration(milliseconds: 100));
    },
  );

  Future<DriveStep> tap(dynamic target, {Duration? settle}) {
    return _act(
      'tap',
      target,
      settle,
      (finder) => controller.tap(finder, warnIfMissed: false),
    );
  }

  Future<DriveStep> longPress(dynamic target, {Duration? settle}) {
    return _act(
      'longPress',
      target,
      settle,
      (finder) => controller.longPress(finder, warnIfMissed: false),
    );
  }

  Future<DriveStep> drag(dynamic target, Offset by, {Duration? settle}) {
    return _act(
      'drag',
      target,
      settle,
      (finder) => controller.drag(finder, by, warnIfMissed: false),
    );
  }

  /// Scrolls until [target] is on screen. Same contract as the scenario verb:
  /// the target may match nothing yet — being off screen is the whole point.
  Future<DriveStep> scrollTo(
    dynamic target, {
    dynamic within,
    double step = 200,
    int maxScrolls = 50,
    Duration? settle,
  }) async {
    var watch = Stopwatch()..start();
    var scrollable = within == null
        ? find.byType(Scrollable)
        : find.descendant(
            of: finderForTarget(within),
            matching: find.byType(Scrollable),
            matchRoot: true,
          );
    if (scrollable.evaluate().isEmpty) {
      throw TargetError(
        TargetFailure.notFound,
        _resolver.messages.nothingScrolls(within),
      );
    }
    try {
      await controller.scrollUntilVisible(
        finderForTarget(target),
        step,
        scrollable: scrollable.first,
        maxScrolls: maxScrolls,
      );
    } on StateError {
      throw TargetError(
        TargetFailure.notFound,
        _resolver.messages.scrollExhausted(
          maxScrolls,
          step,
          describeTarget(target),
        ),
      );
    }
    var result = await settleLive(budget: settle ?? settleBudget);
    return DriveStep(
      verb: 'scrollTo',
      target: describeTarget(target),
      settle: result,
      elapsed: watch.elapsed,
    );
  }

  /// Focuses the field at [target] and pushes [text] as one editing value —
  /// `TextInput.updateEditingValue`, the control-side API, with no input
  /// control installed so the platform IME stays in place.
  Future<DriveStep> enterText(dynamic target, String text, {Duration? settle}) {
    return _act('enterText', target, settle, (finder) async {
      var editable = find.descendant(
        of: finder,
        matching: find.byType(EditableText),
        matchRoot: true,
      );
      var elements = editable.evaluate().toList();
      if (elements.length != 1) {
        throw TargetError(
          TargetFailure.notFound,
          '${describeTarget(target)} contains ${elements.length} text fields, '
          'and `enterText` needs one.',
        );
      }
      var state =
          (elements.single as StatefulElement).state as EditableTextState;
      state.requestKeyboard();
      // Focus and the input connection apply over a frame; give them one.
      await settleLive(budget: const Duration(milliseconds: 100));
      TextInput.updateEditingValue(
        TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: text.length),
        ),
      );
    });
  }

  /// The platform back gesture, injected the way the engine injects it — down
  /// `flutter/navigation` — so `PopScope`s run on the way in.
  Future<DriveStep> back({Duration? settle}) async {
    var watch = Stopwatch()..start();
    var completer = Completer<void>();
    ui.channelBuffers.push(
      'flutter/navigation',
      const JSONMethodCodec().encodeMethodCall(const MethodCall('popRoute')),
      (_) => completer.complete(),
    );
    await completer.future;
    var result = await settleLive(budget: settle ?? settleBudget);
    return DriveStep(verb: 'back', settle: result, elapsed: watch.elapsed);
  }

  /// Real elapsed time, then a settle so what the wait released is applied.
  Future<DriveStep> wait(Duration duration, {Duration? settle}) async {
    var watch = Stopwatch()..start();
    await Future<void>.delayed(duration);
    var result = await settleLive(budget: settle ?? settleBudget);
    return DriveStep(verb: 'wait', settle: result, elapsed: watch.elapsed);
  }

  /// The act-less transaction: settle and look.
  Future<DriveStep> observe({Duration? settle}) async {
    var watch = Stopwatch()..start();
    var result = await settleLive(budget: settle ?? settleBudget);
    return DriveStep(verb: 'observe', settle: result, elapsed: watch.elapsed);
  }

  List<String> visibleTexts() => visibleTextsOf(controller);

  Future<DriveStep> _act(
    String verb,
    dynamic target,
    Duration? settle,
    Future<void> Function(Finder finder) act,
  ) async {
    var watch = Stopwatch()..start();
    var attempts = 0;
    while (true) {
      attempts++;
      try {
        var finder = await _resolver.resolve(target, verb);
        await act(finder);
        break;
      } on TargetError {
        if (watch.elapsed >= actTimeout) rethrow;
        await settleLive(budget: retryPump);
      }
    }
    var result = await settleLive(budget: settle ?? settleBudget);
    return DriveStep(
      verb: verb,
      target: describeTarget(target),
      settle: result,
      elapsed: watch.elapsed,
      attempts: attempts,
    );
  }

  String _describeScreen() {
    var texts = visibleTexts().where((t) => t.isNotEmpty).toList();
    if (texts.isEmpty) return 'none on screen';
    var shown = texts.take(20).map((t) => '"$t"').join(', ');
    return texts.length > 20 ? '$shown, …' : shown;
  }
}
