import 'dart:io';

import 'package:flutterware_app/src/run/device/device_settings.dart';

/// A stand-in for `Process.run`, scripted by substring.
///
/// The two backends are almost entirely command construction and output
/// parsing, and both halves deserve pinning without a booted device anywhere —
/// so every test in this directory drives them through one of these. The
/// outputs the tests script it with are **real bytes** captured on 2026-08-24
/// against an iPhone 17 Pro on iOS 26.2 and an API 35 emulator; the awkward
/// ones especially, because the awkward ones are where the bugs live.
class FakeProcesses {
  FakeProcesses([Map<String, String>? stdout]) : _stdout = {...?stdout};

  final Map<String, String> _stdout;

  /// Every command spawned, as `executable arg arg …`, in order — so a test can
  /// assert on the *sequence* a write issues and not only on what it answered.
  final calls = <String>[];

  /// Substrings whose command should come back as a failure.
  final failing = <String>{};

  void reply(String contains, String stdout) => _stdout[contains] = stdout;

  RunDeviceProcess get run => (executable, arguments) async {
    var call = '$executable ${arguments.join(' ')}';
    calls.add(call);
    for (var pattern in failing) {
      if (call.contains(pattern)) {
        return ProcessResult(0, 1, '', 'no such thing');
      }
    }
    for (var entry in _stdout.entries) {
      if (call.contains(entry.key)) {
        return ProcessResult(0, 0, entry.value, '');
      }
    }
    // Unscripted: a successful command that said nothing, which is what
    // every write in both backends actually does.
    return ProcessResult(0, 0, '', '');
  };

  /// Whether any spawned command contained [pattern].
  bool ran(String pattern) => calls.any((call) => call.contains(pattern));

  /// Where [pattern] was spawned in the sequence, or -1.
  int indexOf(String pattern) =>
      calls.indexWhere((call) => call.contains(pattern));
}

extension SettingLookup on List<DeviceSetting> {
  /// The row for [id]. Named rather than `operator []`, which `List` already
  /// has and an extension cannot take back.
  DeviceSetting of(DeviceSettingId id) =>
      firstWhere((setting) => setting.id == id);
}
