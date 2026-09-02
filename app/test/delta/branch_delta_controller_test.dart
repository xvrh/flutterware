import 'dart:async';

import 'package:flutterware_app/src/delta/branch_delta.dart';
import 'package:flutterware_app/src/delta/branch_delta_controller.dart';
import 'package:test/test.dart';

/// The controller's sequencing, with an injected loader and no git: what a
/// tracked set does, how a mid-load refresh is remembered, what settling
/// waits for, and what a panel's attach costs.
void main() {
  BranchDelta answer(BranchDeltaRequest request, {String head = 'head'}) =>
      BranchDelta(
        worktreePath: request.worktreePath,
        base: 'main',
        mergeBase: '0123456789abcdef',
        head: head,
        readAt: DateTime.now(),
        files: {
          'lib/a.dart': const DeltaFile(
            path: 'lib/a.dart',
            status: ChangeStatus.modified,
          ),
        },
        reach: {for (var file in request.files) file: const []},
      );

  test(
    'tracking files loads for their union, and every landing looks',
    () async {
      var requests = <BranchDeltaRequest>[];
      var controller = BranchDeltaController(
        worktreePath: '/w',
        packages: ['.', 'app'],
        load: (request) async {
          requests.add(request);
          return answer(request);
        },
      );
      addTearDown(controller.dispose);

      controller.track('previews:.', ['demo/a.dart']);
      expect(controller.pending, isNotNull);
      await controller.whenSettled();
      expect(requests.single.files, {'demo/a.dart'});
      expect(requests.single.packageConfigs, [
        '/w/.dart_tool/package_config.json',
        '/w/app/.dart_tool/package_config.json',
      ]);

      // The same set again is a scan that landed, which is a save: look again.
      controller.track('previews:.', ['demo/a.dart']);
      await controller.whenSettled();
      expect(requests, hasLength(2));
      expect(requests.last.previous, isNotNull);

      controller.track('scenarios:.', ['test/s.dart']);
      await controller.whenSettled();
      expect(requests.last.files, {'demo/a.dart', 'test/s.dart'});
      expect(
        controller.value?.reachedFiles,
        containsAll(['demo/a.dart', 'test/s.dart']),
      );
    },
  );

  test(
    'a refresh during a load runs again after it, with the newer set',
    () async {
      var gate = Completer<void>();
      var loads = 0;
      var seen = <Set<String>>[];
      var controller = BranchDeltaController(
        worktreePath: '/w',
        load: (request) async {
          loads++;
          seen.add(request.files);
          if (loads == 1) await gate.future;
          return answer(request);
        },
      );
      addTearDown(controller.dispose);

      var first = controller.refresh();
      expect(controller.isLoading, isTrue);
      controller.track('previews:.', ['demo/late.dart']);
      var second = controller.refresh();
      expect(identical(first, second), isTrue, reason: 'joined, not doubled');
      expect(loads, 1);

      gate.complete();
      await first;
      // The remembered call started before the first was reported done —
      // which is what lets a caller follow the chain to the end. With a loader
      // this quick it may already have landed too.
      expect(loads, 2);
      expect(seen.last, {'demo/late.dart'});
      if (controller.pending case var running?) await running;
      expect(controller.isLoading, isFalse);
    },
  );

  test(
    'settling waits past the load that was asked before the files',
    () async {
      // A's scan starts load 1; B's lands mid-load. The answer B's caller wants
      // is load 2's, which carries B's files.
      var gate = Completer<void>();
      var loads = 0;
      var controller = BranchDeltaController(
        worktreePath: '/w',
        load: (request) async {
          loads++;
          if (loads == 1) await gate.future;
          return answer(request);
        },
      );
      addTearDown(controller.dispose);

      controller.track('previews:.', ['demo/a.dart']);
      controller.track('scenarios:.', ['test/b.dart']);
      var settled = controller.whenSettled();
      gate.complete();
      await settled;
      expect(loads, 2);
      expect(controller.value?.reachOf('test/b.dart'), isNotNull);
      expect(controller.value?.reachedFiles, contains('test/b.dart'));
      expect(controller.pending, isNull);
    },
  );

  test('an unchanged answer keeps its object and does not notify', () async {
    var controller = BranchDeltaController(
      worktreePath: '/w',
      load: (request) async => answer(request),
    );
    addTearDown(controller.dispose);
    var notifications = 0;
    controller.addListener(() => notifications++);

    controller.track('previews:.', ['demo/a.dart']);
    await controller.whenSettled();
    var first = controller.value;
    expect(notifications, 1);

    await controller.refresh();
    expect(identical(controller.value, first), isTrue);
    expect(notifications, 1, reason: 'nothing to redraw');
  });

  test('a changed answer replaces the object and notifies once', () async {
    var head = 'one';
    var controller = BranchDeltaController(
      worktreePath: '/w',
      load: (request) async => answer(request, head: head),
    );
    addTearDown(controller.dispose);
    var notifications = 0;
    controller.addListener(() => notifications++);

    await controller.refresh();
    head = 'two';
    await controller.refresh();
    expect(controller.value?.head, 'two');
    expect(notifications, 2);
  });

  test('a failed load keeps the last answer and reports the failure', () async {
    var fail = false;
    var controller = BranchDeltaController(
      worktreePath: '/w',
      load: (request) async {
        if (fail) throw StateError('git went away');
        return answer(request);
      },
    );
    addTearDown(controller.dispose);

    await controller.refresh();
    var good = controller.value;
    fail = true;
    await controller.refresh();
    expect(identical(controller.value, good), isTrue);
    expect('${controller.failure}', contains('git went away'));

    // A stale check retries after a failure rather than trusting the age.
    fail = false;
    await controller.refreshIfStale();
    expect(controller.failure, isNull);
  });

  test(
    'a loader that fails synchronously does not pin the in-flight slot',
    () async {
      var calls = 0;
      var controller = BranchDeltaController(
        worktreePath: '/w',
        load: (request) {
          calls++;
          if (calls == 1) throw StateError('before the first await');
          return Future.value(answer(request));
        },
      );
      addTearDown(controller.dispose);

      await controller.refresh();
      expect(controller.isLoading, isFalse);
      expect(controller.failure, isNotNull);
      await controller.refresh();
      expect(calls, 2, reason: 'the second refresh started a load');
      expect(controller.failure, isNull);
    },
  );

  test('a fresh answer is not re-read by an arriving panel', () async {
    var loads = 0;
    var controller = BranchDeltaController(
      worktreePath: '/w',
      load: (request) async {
        loads++;
        return answer(request);
      },
      tick: const Duration(hours: 1),
    );
    addTearDown(controller.dispose);

    controller.attach();
    await controller.refreshIfStale();
    expect(loads, 0, reason: 'nothing registered yet, nothing to read for');
    controller.track('previews:.', ['demo/a.dart']);
    await controller.whenSettled();
    expect(loads, 1);
    controller.attach();
    await controller.refreshIfStale();
    expect(loads, 1, reason: 'seconds old is fresh');
    expect(controller.isAttached, isTrue);
    controller.detach();
    controller.detach();
    expect(controller.isAttached, isFalse);
  });

  test('attached, the delta is re-read on the tick', () async {
    var loads = 0;
    var controller = BranchDeltaController(
      worktreePath: '/w',
      load: (request) async {
        loads++;
        return answer(request);
      },
      tick: const Duration(milliseconds: 20),
    );
    addTearDown(controller.dispose);

    controller.track('previews:.', ['demo/a.dart']);
    controller.attach();
    await Future<void>.delayed(const Duration(milliseconds: 70));
    expect(loads, greaterThanOrEqualTo(3));
    controller.detach();
    var settled = loads;
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(loads, settled, reason: 'detached, the tick stops');
  });
}
