// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' show Tooltip;
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/src/all_elements.dart';
import 'package:flutter_test/src/binding.dart';
import 'package:flutter_test/src/controller.dart';
import 'package:flutter_test/src/finders.dart';
import 'package:flutter_test/src/restoration.dart';
import 'package:flutter_test/src/test_async_utils.dart';
import 'package:flutter_test/src/test_pointer.dart';
import 'package:flutter_test/src/test_text_input.dart';
// The test_api package is not for general use... it's literally for our use.
// ignore: deprecated_member_use
import 'package:test_api/test_api.dart' as test_package;

// Keep users from needing multiple imports to test semantics.
export 'package:flutter/rendering.dart' show SemanticsHandle;
// We re-export the test package minus some features that we reimplement.
//
// Specifically:
//
//  - test, group, setUpAll, tearDownAll, setUp, tearDown, and expect would
//    conflict with our own implementations in test_compat.dart. This handles
//    setting up a declarer when one is not defined, which can happen when a
//    test is executed via `flutter run`.
//
//  - expect is reimplemented below, to catch incorrect async usage.
//
//  - isInstanceOf is reimplemented in matchers.dart because we don't want to
//    mark it as deprecated (ours is just a method, not a class).
//
// The test_api package has a deprecation warning to discourage direct use but
// that doesn't apply here.
// ignore: deprecated_member_use
export 'package:test_api/test_api.dart'
    hide
        test,
        group,
        setUpAll,
        tearDownAll,
        setUp,
        tearDown,
        expect,
        isInstanceOf;

// ignore_for_file: prefer_single_quotes
// ignore_for_file: omit_local_variable_types
// ignore_for_file: implementation_imports
// ignore_for_file: only_throw_errors
// ignore_for_file: curly_braces_in_flow_control_structures

/// Signature for callback to [testWidgets] and [benchmarkWidgets].
typedef WidgetTesterCallback = Future<void> Function(WidgetTester widgetTester);

// Return the last element that satisifes `test`, or return null if not found.
E? _lastWhereOrNull<E>(Iterable<E> list, bool Function(E) test) {
  late E result;
  bool foundMatching = false;
  for (final E element in list) {
    if (test(element)) {
      result = element;
      foundMatching = true;
    }
  }
  if (foundMatching) return result;
  return null;
}

/// Class that programmatically interacts with widgets and the test environment.
///
/// For convenience, instances of this class (such as the one provided by
/// `testWidgets`) can be used as the `vsync` for `AnimationController` objects.
class WidgetTester extends WidgetController
    implements HitTestDispatcher, TickerProvider {
  WidgetTester(AutomatedTestWidgetsFlutterBinding binding) : super(binding);

  /// The binding instance used by the testing framework.
  @override
  TestWidgetsFlutterBinding get binding =>
      super.binding as TestWidgetsFlutterBinding;

  /// Renders the UI from the given [widget].
  ///
  /// Calls [runApp] with the given widget, then triggers a frame and flushes
  /// microtasks, by calling [pump] with the same `duration` (if any). The
  /// supplied [EnginePhase] is the final phase reached during the pump pass; if
  /// not supplied, the whole pass is executed.
  ///
  /// Subsequent calls to this is different from [pump] in that it forces a full
  /// rebuild of the tree, even if [widget] is the same as the previous call.
  /// [pump] will only rebuild the widgets that have changed.
  ///
  /// This method should not be used as the first parameter to an [expect] or
  /// [expectLater] call to test that a widget throws an exception. Instead, use
  /// [TestWidgetsFlutterBinding.takeException].
  ///
  /// {@tool snippet}
  /// ```dart
  /// testWidgets('MyWidget asserts invalid bounds', (WidgetTester tester) async {
  ///   await tester.pumpWidget(MyWidget(-1));
  ///   expect(tester.takeException(), isAssertionError); // or isNull, as appropriate.
  /// });
  /// ```
  /// {@end-tool}
  ///
  /// See also [LiveTestWidgetsFlutterBindingFramePolicy], which affects how
  /// this method works when the test is run with `flutter run`.
  Future<void> pumpWidget(
    Widget widget, [
    Duration? duration,
    EnginePhase phase = EnginePhase.sendSemanticsUpdate,
  ]) {
    return TestAsyncUtils.guard<void>(() {
      binding.attachRootWidget(widget);
      binding.scheduleFrame();
      return binding.pump(duration, phase);
    });
  }

  @override
  Future<List<Duration>> handlePointerEventRecord(
      Iterable<PointerEventRecord> records) {
    assert(records.isNotEmpty);
    return TestAsyncUtils.guard<List<Duration>>(() async {
      final List<Duration> handleTimeStampDiff = <Duration>[];
      DateTime? startTime;
      for (final PointerEventRecord record in records) {
        final DateTime now = binding.clock.now();
        startTime ??= now;
        // So that the first event is promised to receive a zero timeDiff
        final Duration timeDiff = record.timeDelay - now.difference(startTime);
        if (timeDiff.isNegative) {
          // Flush all past events
          handleTimeStampDiff.add(-timeDiff);
          for (final PointerEvent event in record.events) {
            binding.handlePointerEventForSource(event,
                source: TestBindingEventSource.test);
          }
        } else {
          await binding.pump();
          await binding.delayed(timeDiff);
          handleTimeStampDiff.add(
            binding.clock.now().difference(startTime) - record.timeDelay,
          );
          for (final PointerEvent event in record.events) {
            binding.handlePointerEventForSource(event,
                source: TestBindingEventSource.test);
          }
        }
      }
      await binding.pump();
      // This makes sure that a gesture is completed, with no more pointers
      // active.
      return handleTimeStampDiff;
    });
  }

  /// Triggers a frame after `duration` amount of time.
  ///
  /// This makes the framework act as if the application had janked (missed
  /// frames) for `duration` amount of time, and then received a "Vsync" signal
  /// to paint the application.
  ///
  /// For a [FakeAsync] environment (typically in `flutter test`), this advances
  /// time and timeout counting; for a live environment this delays `duration`
  /// time.
  ///
  /// This is a convenience function that just calls
  /// [TestWidgetsFlutterBinding.pump].
  ///
  /// See also [LiveTestWidgetsFlutterBindingFramePolicy], which affects how
  /// this method works when the test is run with `flutter run`.
  @override
  Future<void> pump([
    Duration? duration,
    EnginePhase phase = EnginePhase.sendSemanticsUpdate,
  ]) {
    return TestAsyncUtils.guard<void>(() => binding.pump(duration, phase));
  }

  /// Triggers a frame after `duration` amount of time, return as soon as the frame is drawn.
  ///
  /// This enables driving an artificially high CPU load by rendering frames in
  /// a tight loop. It must be used with the frame policy set to
  /// [LiveTestWidgetsFlutterBindingFramePolicy.benchmark].
  ///
  /// Similarly to [pump], this doesn't actually wait for `duration`, just
  /// advances the clock.
  Future<void> pumpBenchmark(Duration duration) async {
    assert(() {
      final TestWidgetsFlutterBinding widgetsBinding = binding;
      return widgetsBinding is LiveTestWidgetsFlutterBinding &&
          widgetsBinding.framePolicy ==
              LiveTestWidgetsFlutterBindingFramePolicy.benchmark;
    }());

    dynamic caughtException;
    void handleError(dynamic error, StackTrace stackTrace) =>
        caughtException ??= error;

    await Future<void>.microtask(() {
      binding.handleBeginFrame(duration);
    }).catchError(handleError);
    await idle();
    await Future<void>.microtask(() {
      binding.handleDrawFrame();
    }).catchError(handleError);
    await idle();

    if (caughtException != null) {
      throw caughtException as Object; // ignore: rethrowing caught exception.
    }
  }

  @override
  Future<int> pumpAndSettle([
    Duration duration = const Duration(milliseconds: 100),
    EnginePhase phase = EnginePhase.sendSemanticsUpdate,
    Duration timeout = const Duration(minutes: 10),
  ]) {
    assert(duration > Duration.zero);
    assert(timeout > Duration.zero);
    assert(() {
      final WidgetsBinding binding = this.binding;
      if (binding is LiveTestWidgetsFlutterBinding &&
          binding.framePolicy ==
              LiveTestWidgetsFlutterBindingFramePolicy.benchmark) {
        test_package.fail(
          'When using LiveTestWidgetsFlutterBindingFramePolicy.benchmark, '
          'hasScheduledFrame is never set to true. This means that pumpAndSettle() '
          'cannot be used, because it has no way to know if the application has '
          'stopped registering new frames.',
        );
      }
      return true;
    }());
    return TestAsyncUtils.guard<int>(() async {
      final DateTime endTime = binding.clock.fromNowBy(timeout);
      int count = 0;
      do {
        if (binding.clock.now().isAfter(endTime))
          throw FlutterError('pumpAndSettle timed out');
        await binding.pump(duration, phase);
        count += 1;
      } while (binding.hasScheduledFrame);
      return count;
    });
  }

  /// Repeatedly pump frames that render the `target` widget with a fixed time
  /// `interval` as many as `maxDuration` allows.
  ///
  /// The `maxDuration` argument is required. The `interval` argument defaults to
  /// 16.683 milliseconds (59.94 FPS).
  Future<void> pumpFrames(
    Widget target,
    Duration maxDuration, [
    Duration interval = const Duration(milliseconds: 16, microseconds: 683),
  ]) {
    // The interval following the last frame doesn't have to be within the fullDuration.
    Duration elapsed = Duration.zero;
    return TestAsyncUtils.guard<void>(() async {
      binding.attachRootWidget(target);
      binding.scheduleFrame();
      while (elapsed < maxDuration) {
        await binding.pump(interval);
        elapsed += interval;
      }
    });
  }

  /// Simulates restoring the state of the widget tree after the application
  /// is restarted.
  ///
  /// The method grabs the current serialized restoration data from the
  /// [RestorationManager], takes down the widget tree to destroy all in-memory
  /// state, and then restores the widget tree from the serialized restoration
  /// data.
  Future<void> restartAndRestore() async {
    assert(
      binding.restorationManager.debugRootBucketAccessed,
      'The current widget tree did not inject the root bucket of the RestorationManager and '
      'therefore no restoration data has been collected to restore from. Did you forget to wrap '
      'your widget tree in a RootRestorationScope?',
    );
    final Widget widget = (binding.renderViewElement!
            as RenderObjectToWidgetElement<RenderObject>)
        .widget
        .child!;
    final TestRestorationData restorationData =
        binding.restorationManager.restorationData;
    runApp(Container(key: UniqueKey()));
    await pump();
    binding.restorationManager.restoreFrom(restorationData);
    return pumpWidget(widget);
  }

  /// Retrieves the current restoration data from the [RestorationManager].
  ///
  /// The returned [TestRestorationData] describes the current state of the
  /// widget tree under test and can be provided to [restoreFrom] to restore
  /// the widget tree to the state described by this data.
  Future<TestRestorationData> getRestorationData() async {
    assert(
      binding.restorationManager.debugRootBucketAccessed,
      'The current widget tree did not inject the root bucket of the RestorationManager and '
      'therefore no restoration data has been collected. Did you forget to wrap your widget tree '
      'in a RootRestorationScope?',
    );
    return binding.restorationManager.restorationData;
  }

  /// Restores the widget tree under test to the state described by the
  /// provided [TestRestorationData].
  ///
  /// The data provided to this method is usually obtained from
  /// [getRestorationData].
  Future<void> restoreFrom(TestRestorationData data) {
    binding.restorationManager.restoreFrom(data);
    return pump();
  }

  /// Runs a [callback] that performs real asynchronous work.
  ///
  /// This is intended for callers who need to call asynchronous methods where
  /// the methods spawn isolates or OS threads and thus cannot be executed
  /// synchronously by calling [pump].
  ///
  /// If callers were to run these types of asynchronous tasks directly in
  /// their test methods, they run the possibility of encountering deadlocks.
  ///
  /// If [callback] completes successfully, this will return the future
  /// returned by [callback].
  ///
  /// If [callback] completes with an error, the error will be caught by the
  /// Flutter framework and made available via [takeException], and this method
  /// will return a future that completes with `null`.
  ///
  /// Re-entrant calls to this method are not allowed; callers of this method
  /// are required to wait for the returned future to complete before calling
  /// this method again. Attempts to do otherwise will result in a
  /// [TestFailure] error being thrown.
  ///
  /// If your widget test hangs and you are using [runAsync], chances are your
  /// code depends on the result of a task that did not complete. Fake async
  /// environment is unable to resolve a future that was created in [runAsync].
  /// If you observe such behavior or flakiness, you have a number of options:
  ///
  /// * Consider restructuring your code so you do not need [runAsync]. This is
  ///   the optimal solution as widget tests are designed to run in fake async
  ///   environment.
  ///
  /// * Expose a [Future] in your application code that signals the readiness of
  ///   your widget tree, then await that future inside [callback].
  Future<T?> runAsync<T>(Future<T> Function() callback) =>
      binding.runAsync<T?>(callback);

  /// Whether there are any transient callbacks scheduled.
  ///
  /// This essentially checks whether all animations have completed.
  ///
  /// See also:
  ///
  ///  * [pumpAndSettle], which essentially calls [pump] until there are no
  ///    scheduled frames.
  ///  * [SchedulerBinding.transientCallbackCount], which is the value on which
  ///    this is based.
  ///  * [SchedulerBinding.hasScheduledFrame], which is true whenever a frame is
  ///    pending. [SchedulerBinding.hasScheduledFrame] is made true when a
  ///    widget calls [State.setState], even if there are no transient callbacks
  ///    scheduled. This is what [pumpAndSettle] uses.
  bool get hasRunningAnimations => binding.transientCallbackCount > 0;

  @override
  HitTestResult hitTestOnBinding(Offset location) {
    location = binding.localToGlobal(location);
    return super.hitTestOnBinding(location);
  }

  @override
  Future<void> sendEventToBinding(PointerEvent event) {
    return TestAsyncUtils.guard<void>(() async {
      binding.handlePointerEventForSource(event,
          source: TestBindingEventSource.test);
    });
  }

  /// Handler for device events caught by the binding in live test mode.
  @override
  void dispatchEvent(PointerEvent event, HitTestResult result) {
    if (event is PointerDownEvent) {
      final RenderObject innerTarget = result.path
          .map((HitTestEntry candidate) => candidate.target)
          .whereType<RenderObject>()
          .first;
      final Element? innerTargetElement = _lastWhereOrNull(
        collectAllElementsFrom(binding.renderViewElement!, skipOffstage: true),
        (Element element) => element.renderObject == innerTarget,
      );
      if (innerTargetElement == null) {
        printToConsole('No widgets found at ${event.position}.');
        return;
      }
      final List<Element> candidates = <Element>[];
      innerTargetElement.visitAncestorElements((Element element) {
        candidates.add(element);
        return true;
      });
      assert(candidates.isNotEmpty);
      String? descendantText;
      int numberOfWithTexts = 0;
      int numberOfTypes = 0;
      int totalNumber = 0;
      printToConsole(
          'Some possible finders for the widgets at ${event.position}:');
      for (final Element element in candidates) {
        if (totalNumber >
            13) // an arbitrary number of finders that feels useful without being overwhelming
          break;
        totalNumber += 1; // optimistically assume we'll be able to describe it

        final Widget widget = element.widget;
        if (widget is Tooltip) {
          final String message =
              widget.message ?? widget.richMessage!.toPlainText();
          final Iterable<Element> matches = find.byTooltip(message).evaluate();
          if (matches.length == 1) {
            printToConsole("  find.byTooltip('$message')");
            continue;
          }
        }

        if (widget is Text) {
          assert(descendantText == null);
          assert(widget.data != null || widget.textSpan != null);
          final String text = widget.data ?? widget.textSpan!.toPlainText();
          final Iterable<Element> matches = find.text(text).evaluate();
          descendantText = widget.data;
          if (matches.length == 1) {
            printToConsole("  find.text('$text')");
            continue;
          }
        }

        final Key? key = widget.key;
        if (key is ValueKey<dynamic>) {
          String? keyLabel;
          if (key is ValueKey<int> ||
              key is ValueKey<double> ||
              key is ValueKey<bool>) {
            keyLabel = 'const ${key.runtimeType}(${key.value})';
          } else if (key is ValueKey<String>) {
            keyLabel = "const Key('${key.value}')";
          }
          if (keyLabel != null) {
            final Iterable<Element> matches = find.byKey(key).evaluate();
            if (matches.length == 1) {
              printToConsole('  find.byKey($keyLabel)');
              continue;
            }
          }
        }

        if (!_isPrivate(widget.runtimeType)) {
          if (numberOfTypes < 5) {
            final Iterable<Element> matches =
                find.byType(widget.runtimeType).evaluate();
            if (matches.length == 1) {
              printToConsole('  find.byType(${widget.runtimeType})');
              numberOfTypes += 1;
              continue;
            }
          }

          if (descendantText != null && numberOfWithTexts < 5) {
            final Iterable<Element> matches = find
                .widgetWithText(widget.runtimeType, descendantText)
                .evaluate();
            if (matches.length == 1) {
              printToConsole(
                  "  find.widgetWithText(${widget.runtimeType}, '$descendantText')");
              numberOfWithTexts += 1;
              continue;
            }
          }
        }

        if (!_isPrivate(element.runtimeType)) {
          final Iterable<Element> matches =
              find.byElementType(element.runtimeType).evaluate();
          if (matches.length == 1) {
            printToConsole('  find.byElementType(${element.runtimeType})');
            continue;
          }
        }

        totalNumber -=
            1; // if we got here, we didn't actually find something to say about it
      }
      if (totalNumber == 0)
        printToConsole('  <could not come up with any unique finders>');
    }
  }

  bool _isPrivate(Type type) {
    // used above so that we don't suggest matchers for private types
    return '_'.matchAsPrefix(type.toString()) != null;
  }

  /// Returns the exception most recently caught by the Flutter framework.
  ///
  /// See [TestWidgetsFlutterBinding.takeException] for details.
  dynamic takeException() {
    return binding.takeException();
  }

  /// Acts as if the application went idle.
  ///
  /// Runs all remaining microtasks, including those scheduled as a result of
  /// running them, until there are no more microtasks scheduled. Then, runs any
  /// previously scheduled timers with zero time, and completes the returned future.
  ///
  /// May result in an infinite loop or run out of memory if microtasks continue
  /// to recursively schedule new microtasks. Will not run any timers scheduled
  /// after this method was invoked, even if they are zero-time timers.
  Future<void> idle() {
    return TestAsyncUtils.guard<void>(() => binding.idle());
  }

  Set<Ticker>? _tickers;

  @override
  Ticker createTicker(TickerCallback onTick) {
    _tickers ??= <_TestTicker>{};
    final _TestTicker result = _TestTicker(onTick, _removeTicker);
    _tickers!.add(result);
    return result;
  }

  void _removeTicker(_TestTicker ticker) {
    assert(_tickers != null);
    assert(_tickers!.contains(ticker));
    _tickers!.remove(ticker);
  }

  /// Throws an exception if any tickers created by the [WidgetTester] are still
  /// active when the method is called.
  ///
  /// An argument can be specified to provide a string that will be used in the
  /// error message. It should be an adverbial phrase describing the current
  /// situation, such as "at the end of the test".
  void verifyTickersWereDisposed([String when = 'when none should have been']) {
    if (_tickers != null) {
      for (final Ticker ticker in _tickers!) {
        if (ticker.isActive) {
          throw FlutterError.fromParts(<DiagnosticsNode>[
            ErrorSummary('A Ticker was active $when.'),
            ErrorDescription('All Tickers must be disposed.'),
            ErrorHint('Tickers used by AnimationControllers '
                'should be disposed by calling dispose() on the AnimationController itself. '
                'Otherwise, the ticker will leak.'),
            ticker.describeForError('The offending ticker was')
          ]);
        }
      }
    }
  }

  void endOfTestVerifications() {
    verifyTickersWereDisposed('at the end of the test');
  }

  /// Returns the TestTextInput singleton.
  ///
  /// Typical app tests will not need to use this value. To add text to widgets
  /// like [TextField] or [TextFormField], call [enterText].
  ///
  /// Some of the properties and methods on this value are only valid if the
  /// binding's [TestWidgetsFlutterBinding.registerTestTextInput] flag is set to
  /// true as a test is starting (meaning that the keyboard is to be simulated
  /// by the test framework). If those members are accessed when using a binding
  /// that sets this flag to false, they will throw.
  TestTextInput get testTextInput => binding.testTextInput;

  /// Give the text input widget specified by [finder] the focus, as if the
  /// onscreen keyboard had appeared.
  ///
  /// Implies a call to [pump].
  ///
  /// The widget specified by [finder] must be an [EditableText] or have
  /// an [EditableText] descendant. For example `find.byType(TextField)`
  /// or `find.byType(TextFormField)`, or `find.byType(EditableText)`.
  ///
  /// Tests that just need to add text to widgets like [TextField]
  /// or [TextFormField] only need to call [enterText].
  Future<void> showKeyboard(Finder finder) async {
    return TestAsyncUtils.guard<void>(() async {
      final EditableTextState editable = state<EditableTextState>(
        find.descendant(
          of: finder,
          matching:
              find.byType(EditableText, skipOffstage: finder.skipOffstage),
          matchRoot: true,
        ),
      );
      // Setting focusedEditable causes the binding to call requestKeyboard()
      // on the EditableTextState, which itself eventually calls TextInput.attach
      // to establish the connection.
      binding.focusedEditable = editable;
      await pump();
    });
  }

  /// Give the text input widget specified by [finder] the focus and replace its
  /// content with [text], as if it had been provided by the onscreen keyboard.
  ///
  /// The widget specified by [finder] must be an [EditableText] or have
  /// an [EditableText] descendant. For example `find.byType(TextField)`
  /// or `find.byType(TextFormField)`, or `find.byType(EditableText)`.
  ///
  /// When the returned future completes, the text input widget's text will be
  /// exactly `text`, and the caret will be placed at the end of `text`.
  ///
  /// To just give [finder] the focus without entering any text,
  /// see [showKeyboard].
  ///
  /// To enter text into other widgets (e.g. a custom widget that maintains a
  /// TextInputConnection the way that a [EditableText] does), first ensure that
  /// that widget has an open connection (e.g. by using [tap] to to focus it),
  /// then call `testTextInput.enterText` directly (see
  /// [TestTextInput.enterText]).
  Future<void> enterText(Finder finder, String text) async {
    return TestAsyncUtils.guard<void>(() async {
      await showKeyboard(finder);
      testTextInput.enterText(text);
      await idle();
    });
  }

  @override
  void printToConsole(String message) {
    binding.debugPrintOverride(message);
  }
}

typedef _TickerDisposeCallback = void Function(_TestTicker ticker);

class _TestTicker extends Ticker {
  _TestTicker(TickerCallback onTick, this._onDispose) : super(onTick);

  final _TickerDisposeCallback _onDispose;

  @override
  void dispose() {
    _onDispose(this);
    super.dispose();
  }
}
