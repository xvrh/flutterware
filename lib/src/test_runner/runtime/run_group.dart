import 'package:test_api/src/backend/group.dart'; // ignore: implementation_imports
import 'package:test_api/src/backend/live_test.dart'; // ignore: implementation_imports
import 'package:test_api/src/backend/runtime.dart'; // ignore: implementation_imports
import 'package:test_api/src/backend/suite.dart'; // ignore: implementation_imports
import 'package:test_api/src/backend/suite_platform.dart'; // ignore: implementation_imports
import 'package:test_api/src/backend/test.dart'; // ignore: implementation_imports

Future<List<LiveTest>> runGroup(Group builtGroup) async {
  final suite = Suite(builtGroup, SuitePlatform(Runtime.vm));
  return await _runGroup(suite, builtGroup, <Group>[]).toList();
}

Stream<LiveTest> _runGroup(
    Suite suiteConfig, Group group, List<Group> parents) async* {
  parents.add(group);
  try {
    final skipGroup = group.metadata.skip;
    var setUpAllSucceeded = true;
    if (!skipGroup && group.setUpAll != null) {
      final liveTest = group.setUpAll!.load(suiteConfig, groups: parents);
      yield await _runLiveTest(suiteConfig, liveTest);
      setUpAllSucceeded = liveTest.state.result.isPassing;
    }
    if (setUpAllSucceeded) {
      for (final entry in group.entries) {
        if (entry is Group) {
          yield* _runGroup(suiteConfig, entry, parents);
        } else if (!entry.metadata.skip) {
          final test = entry as Test;
          yield await _runLiveTest(
              suiteConfig, test.load(suiteConfig, groups: parents));
        }
      }
    }
    // Even if we're closed or setUpAll failed, we want to run all the
    // teardowns to ensure that any state is properly cleaned up.
    if (!skipGroup && group.tearDownAll != null) {
      final liveTest = group.tearDownAll!.load(suiteConfig, groups: parents);
      yield await _runLiveTest(suiteConfig, liveTest);
    }
  } finally {
    parents.remove(group);
  }
}

Future<LiveTest> _runLiveTest(Suite suiteConfig, LiveTest liveTest) async {
  await liveTest.run();
  return liveTest;
}
