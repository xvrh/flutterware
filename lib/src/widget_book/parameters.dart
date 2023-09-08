import 'dart:core' as core;
import 'dart:core';

mixin ParametersMixin {
  DateTime dateTime(String name) {
    return DateTime.now();
  }

  String string(String name, String defaultValue) {
    return '';
  }

  core.num num(String name, core.num defaultValue,
      {core.num? min, core.num? max}) {
    return 0;
  }

  core.int int(String name, core.int defaultValue,
      {core.int? min, core.int? max}) {
    return 0;
  }

  core.double double(String name, core.double defaultValue,
      {core.double? min, core.double? max}) {
    return 0;
  }
}
