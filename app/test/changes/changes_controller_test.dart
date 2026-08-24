import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware_app/src/changes/change_set.dart';
import 'package:flutterware_app/src/changes/changes_controller.dart';
import 'package:flutterware_app/src/changes/patch_index.dart';
import 'package:flutterware_app/src/worktrees/watchers.dart';

/// What the screen relies on to be **live without being disruptive**: the
/// signal reaches the probe, the probe's answer replaces the last one only when
/// it is a different answer, and an edit that lands mid-probe is not lost.
void main() {
  ChangeSet setOf({
    String patch = 'diff --git a/lib/a.dart b/lib/a.dart\n',
    Set<String> uncommitted = const {},
    List<UntrackedEntry> untracked = const [],
  }) => ChangeSet(
    worktreePath: '/repo/feature',
    patch: PatchIndex(
      bytes: Uint8List.fromList(patch.codeUnits),
      files: const [],
    ),
    base: 'master',
    baseSource: BaseSource.inferred,
    uncommitted: uncommitted,
    untracked: untracked,
  );

  test('an unchanged answer keeps the object the screen is already drawing', () async {
    // **The common case, not the rare one.** Most of what a working-tree watch
    // fires on is build output git ignores, so most re-probes produce exactly
    // this again — and keeping the old object is what keeps every expanded
    // hunk's decoded text and stops the screen rebuilding for nothing.
    var controller = ChangesController(
      worktreePath: '/repo/feature',
      load: (_) async => setOf(),
    );
    addTearDown(controller.dispose);

    await controller.refresh();
    var first = controller.value;
    await controller.refresh();

    expect(identical(controller.value, first), isTrue);
  });

  test('an answer that moved replaces it', () async {
    var patches = ['a', 'a', 'b'];
    var index = 0;
    var controller = ChangesController(
      worktreePath: '/repo/feature',
      load: (_) async => setOf(patch: patches[index++]),
    );
    addTearDown(controller.dispose);

    await controller.refresh();
    var first = controller.value;
    await controller.refresh();
    expect(identical(controller.value, first), isTrue);

    await controller.refresh();
    expect(identical(controller.value, first), isFalse);
  });

  test(
    'committing changes nothing in the patch, and is still a new answer',
    () async {
      // The one that a byte comparison alone would miss: `git commit` moves not
      // one line of the delta, and clears every `uncommitted` mark on screen.
      var marks = [
        {'lib/a.dart'},
        <String>{},
      ];
      var index = 0;
      var controller = ChangesController(
        worktreePath: '/repo/feature',
        load: (_) async => setOf(uncommitted: marks[index++]),
      );
      addTearDown(controller.dispose);

      await controller.refresh();
      var first = controller.value;
      await controller.refresh();

      expect(identical(controller.value, first), isFalse);
      expect(controller.value!.uncommitted, isEmpty);
    },
  );

  test('an edit that lands mid-probe is not lost', () async {
    // **The bug the watcher would have had.** A second `refresh` used to join
    // the running one and return its answer — but the save that triggered it
    // landed *after* that probe read the disk. On a checkout an agent has just
    // gone quiet in, that is the last edit, missing until somebody presses the
    // button.
    var gates = [Completer<void>(), Completer<void>()];
    var reads = 0;
    var controller = ChangesController(
      worktreePath: '/repo/feature',
      load: (_) async {
        var mine = reads++;
        if (mine < gates.length) await gates[mine].future;
        return setOf(patch: 'read $mine');
      },
    );
    addTearDown(controller.dispose);

    var first = controller.refresh();
    await pumpEventQueue();
    expect(reads, 1);

    // The watcher fires while the first probe is still reading.
    unawaited(controller.refresh());
    gates[0].complete();
    await first;
    await pumpEventQueue();

    expect(reads, 2, reason: 'the second read was remembered, not dropped');
    gates[1].complete();
    await pumpEventQueue();
    expect(controller.value!.patch.bytes, 'read 1'.codeUnits);
  });

  test('two arrivals mid-probe still cost one extra read', () async {
    var gate = Completer<void>();
    var reads = 0;
    var controller = ChangesController(
      worktreePath: '/repo/feature',
      load: (_) async {
        if (reads++ == 0) await gate.future;
        return setOf();
      },
    );
    addTearDown(controller.dispose);

    var first = controller.refresh();
    await pumpEventQueue();
    unawaited(controller.refresh());
    unawaited(controller.refresh());
    unawaited(controller.refresh());
    gate.complete();
    await first;
    await pumpEventQueue();

    expect(reads, 2);
  });

  test('the working tree and the git signal both reach the probe', () async {
    var reads = 0;
    var git = StreamController<void>.broadcast();
    addTearDown(git.close);
    var tree = _FakeWatcher();
    var controller = ChangesController(
      worktreePath: '/repo/feature',
      load: (_) async {
        reads++;
        return setOf(patch: 'read $reads');
      },
    );
    addTearDown(controller.dispose);

    controller.watch(gitMoved: git.stream, watcher: tree);
    await controller.refresh();
    expect(reads, 1);

    tree.fire();
    await pumpEventQueue();
    expect(reads, 2, reason: 'a file was written');

    git.add(null);
    await pumpEventQueue();
    expect(reads, 3, reason: 'and something was staged or committed');
  });

  test('a disposed controller stops listening to both', () async {
    var reads = 0;
    var git = StreamController<void>.broadcast();
    addTearDown(git.close);
    var tree = _FakeWatcher();
    var controller = ChangesController(
      worktreePath: '/repo/feature',
      load: (_) async {
        reads++;
        return setOf();
      },
    )..watch(gitMoved: git.stream, watcher: tree);

    await controller.refresh();
    controller.dispose();

    tree.fire();
    git.add(null);
    await pumpEventQueue();
    expect(reads, 1);
  });

  test('watching twice is the same watch', () {
    var tree = _FakeWatcher();
    var other = _FakeWatcher();
    var controller = ChangesController(
      worktreePath: '/repo/feature',
      load: (_) async => setOf(),
    );
    addTearDown(controller.dispose);

    controller
      ..watch(watcher: tree)
      ..watch(watcher: other);

    expect(tree.started, 1);
    expect(other.started, 0);
  });

  test(
    'a failed read leaves the last good answer beside the complaint',
    () async {
      var fail = false;
      var controller = ChangesController(
        worktreePath: '/repo/feature',
        load: (_) async {
          if (fail) throw StateError('the checkout vanished');
          return setOf();
        },
      );
      addTearDown(controller.dispose);

      await controller.refresh();
      var good = controller.value;
      fail = true;
      await controller.refresh();

      expect(identical(controller.value, good), isTrue);
      expect(controller.failure, isA<StateError>());
    },
  );
}

/// A watcher whose only event source is the test.
class _FakeWatcher extends WorkingTreeWatcher {
  _FakeWatcher()
    : super(
        worktreePath: '/repo/feature',
        watch: (_, {required recursive}) => const Stream.empty(),
      );

  var started = 0;
  final _events = StreamController<void>.broadcast();

  @override
  Stream<void> get changes => _events.stream;

  @override
  bool get isWatching => started > 0;

  @override
  void start() => started++;

  /// A no-op once closed, which is what a real watcher does too — disposing
  /// the controller disposes this, and the test then checks nothing arrives.
  void fire() {
    if (!_events.isClosed) _events.add(null);
  }

  @override
  Future<void> dispose() => _events.close();
}
