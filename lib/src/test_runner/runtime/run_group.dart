import 'package:test_api/src/backend/declarer.dart'; // ignore: implementation_imports
import 'package:test_api/src/backend/group.dart'; // ignore: implementation_imports
import 'package:test_api/src/backend/group_entry.dart'; // ignore: implementation_imports
import 'package:test_api/src/backend/invoker.dart'; // ignore: implementation_imports
import 'package:test_api/src/backend/live_test.dart'; // ignore: implementation_imports
import 'package:test_api/src/backend/message.dart'; // ignore: implementation_imports
import 'package:test_api/src/backend/runtime.dart'; // ignore: implementation_imports
import 'package:test_api/src/backend/state.dart'; // ignore: implementation_imports
import 'package:test_api/src/backend/suite.dart'; // ignore: implementation_imports
import 'package:test_api/src/backend/suite_platform.dart'; // ignore: implementation_imports
import 'package:test_api/src/backend/test.dart'; // ignore: implementation_imports

Stream<LiveTest> runGroup(Group builtGroup) {
  final Suite suite = Suite(builtGroup, SuitePlatform(Runtime.vm));
  return _runGroup(suite, builtGroup, <Group>[]);
}

Stream<LiveTest> _runGroup(
    Suite suiteConfig, Group group, List<Group> parents) async* {
  parents.add(group);
  try {
    final bool skipGroup = group.metadata.skip;
    bool setUpAllSucceeded = true;
    if (!skipGroup && group.setUpAll != null) {
      final LiveTest liveTest =
          group.setUpAll!.load(suiteConfig, groups: parents);
      yield await _runLiveTest(suiteConfig, liveTest);
      setUpAllSucceeded = liveTest.state.result.isPassing;
    }
    if (setUpAllSucceeded) {
      for (final GroupEntry entry in group.entries) {
        if (entry is Group) {
          yield* _runGroup(suiteConfig, entry, parents);
        } else if (entry.metadata.skip) {
          await _runSkippedTest(suiteConfig, entry as Test, parents);
        } else {
          final Test test = entry as Test;
          yield await _runLiveTest(
              suiteConfig, test.load(suiteConfig, groups: parents));
        }
      }
    }
    // Even if we're closed or setUpAll failed, we want to run all the
    // teardowns to ensure that any state is properly cleaned up.
    if (!skipGroup && group.tearDownAll != null) {
      final LiveTest liveTest =
          group.tearDownAll!.load(suiteConfig, groups: parents);
      yield await _runLiveTest(suiteConfig, liveTest);
    }
  } finally {
    parents.remove(group);
  }
}

Future<LiveTest> _runLiveTest(Suite suiteConfig, LiveTest liveTest) async {
  await Future<void>.microtask(liveTest.run);
  // Once the test finishes, use await null to do a coarse-grained event
  // loop pump to avoid starving non-microtask events.
  await null;
  final bool isSuccess = liveTest.state.result.isPassing;
  print(
      "Immedite result ${liveTest.state} ${liveTest.individualName} $isSuccess");
  return liveTest;
}

Future<void> _runSkippedTest(
    Suite suiteConfig, Test test, List<Group> parents) async {
  final LocalTest skipped =
      LocalTest(test.name, test.metadata, () {}, trace: test.trace);

  final LiveTest liveTest = skipped.load(suiteConfig);
}
