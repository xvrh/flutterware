import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'protocol.dart';

/// Where the daemon serving a given [DaemonConfig] listens.
///
/// The address is *derived*, not assigned, so every consumer that wants the
/// same catalog — the GUI, `fw`, an agent, a test — arrives at the same socket
/// without being told about each other. Two configs that would produce
/// different entries, different generated code or different kernels hash
/// differently and get their own daemon.
class DaemonAddress {
  DaemonAddress(this.config);

  final DaemonConfig config;

  /// Everything that changes what the daemon would produce.
  ///
  /// Deliberately the whole config: adding a field to [DaemonConfig] without
  /// thinking about sharing should split the daemon, not silently hand a client
  /// someone else's compiler.
  late final String key = sha1
      .convert(utf8.encode(jsonEncode(_canonical(config.toJson()))))
      .toString()
      .substring(0, 16);

  /// A short, stable directory — unix socket paths are capped near 104 bytes on
  /// macOS, so this cannot live under the project's build directory.
  static String get runDir => p.join(_home, '.flutterware', 'run');

  String get socketPath => p.join(runDir, '$key.sock');

  /// Held while deciding whether to spawn, so two clients starting at once
  /// produce one daemon rather than two.
  String get lockPath => p.join(runDir, '$key.lock');

  /// Where a daemon that dies before it can speak leaves its reason.
  String get logPath => p.join(runDir, '$key.log');

  void ensureRunDir() => Directory(runDir).createSync(recursive: true);

  static String get _home =>
      Platform.environment['HOME'] ??
      Platform.environment['USERPROFILE'] ??
      Directory.systemTemp.path;

  /// Sorts maps by key so the hash depends on the values, not on the order
  /// `toJson` happened to emit them in.
  static Object? _canonical(Object? value) => switch (value) {
    Map<String, Object?> map => {
      for (var key in map.keys.toList()..sort()) key: _canonical(map[key]),
    },
    List<Object?> list => [for (var item in list) _canonical(item)],
    _ => value,
  };
}
