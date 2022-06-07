import 'dart:async';

import 'package:collection/collection.dart';

abstract class GroupEntry {
  final String name;
}

class GroupName implements GroupEntry {
  final String name;

  GroupName(this.name);
}

class TestName implements GroupEntry {
  final String name;

  TestName(this.name);
}

class NameDeclarer {
  final NameDeclarer? parent;

  final String? name;

  final _entries = <GroupEntry>[];

  static NameDeclarer? get current =>
      Zone.current[#studio.declarer] as NameDeclarer;

  T declare<T>(T Function() body) =>
      runZoned(body, zoneValues: {#studio.declarer: this});

  /// Defines a test case with the given name and body.
  void test(String name) {
    _addEntry(TestName(name));
  }

  /// Creates a group of tests.
  void group(String name, void Function() body,
      {String? testOn, skip, Map<String, dynamic>? onPlatform, tags}) {
    var declarer = Declarer(this, fullTestPrefix, metadata, _platformVariables,
        _collectTraces, trace, _noRetry, _fullTestName, _seenNames);
    declarer.declare(body);
    _addEntry(declarer.build());
  }

  GroupName build() {
    var entries = _entries.toList();
    return GroupName(_name ?? '', entries);
  }

  void _addEntry(GroupEntry entry) {
    if (_seenNames?.add(entry.name) == false) {
      throw DuplicateTestNameException(entry.name);
    }
    _entries.add(entry);
  }
}

/// An exception thrown when two test cases in the same test suite (same `main`)
/// have an identical name.
class DuplicateTestNameException implements Exception {
  final String name;
  DuplicateTestNameException(this.name);

  @override
  String toString() => 'A test with the name "$name" was already declared. '
      'Test cases must have unique names.\n\n'
      'See https://github.com/dart-lang/test/blob/master/pkgs/test/doc/'
      'configuration.md#allow_test_randomization for info on enabling this.';
}
