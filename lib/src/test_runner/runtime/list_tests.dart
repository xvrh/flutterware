import 'package:flutter_test/flutter_test.dart';
import 'package:test_api/src/backend/declarer.dart';
import 'package:test_api/src/backend/group.dart';
import 'package:test_api/src/backend/group_entry.dart';
import 'package:test_api/src/backend/test.dart';
import '../protocol/model/test_reference.dart';

// ignore_for_file: implementation_imports

Group findTest(Map<String, void Function()> allTests, String fullTestName) {
  var declarer = Declarer(fullTestName: fullTestName);
  declarer.declare(() {
    for (var main in allTests.entries) {
      group(main.key, main.value);
    }
  });
  return declarer.build();
}

Iterable<TestReference> listTests(Map<String, void Function()> allMains) {
  var declarer = Declarer();
  declarer.declare(() {
    for (var main in allMains.entries) {
      group(main.key, main.value);
    }
  });
  var builtGroup = declarer.build();
  return _listTests([], builtGroup);
}

Iterable<TestReference> _listTests(List<String> parents, Group group) sync* {
  for (var entry in group.entries) {
    var simpleName = _individualName(entry, group);
    var name = [...parents, simpleName];
    if (entry is Test) {
      yield TestReference(name);
    } else if (entry is Group) {
      yield* _listTests(name, entry);
    } else {
      throw StateError('Unknown type ${entry.runtimeType}');
    }
  }
}

String _individualName(GroupEntry test, Group group) {
  if (group.name.isEmpty) return test.name;
  if (!test.name.startsWith(group.name)) return test.name;

  if (test.name.length == group.name.length) return '';

  return test.name.substring(group.name.length + 1);
}
