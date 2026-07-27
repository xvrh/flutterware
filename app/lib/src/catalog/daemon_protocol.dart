import 'dart:convert';

import 'catalog_entry.dart';

/// Line-delimited JSON between the GUI and the compiler daemon.
///
/// The daemon owns everything that compiles or builds; the GUI owns the guest
/// process, the texture and the VM-service reload. Nothing that calls
/// `frontend_server` may run inside the Flutter app — see the guard in
/// `ResidentCompiler`.
///
/// stdout carries the protocol and nothing else; the daemon's own logging goes
/// to stderr.
class DaemonConfig {
  DaemonConfig({
    required this.appPackageRoot,
    required this.projectRoot,
    required this.packageConfig,
    required this.entries,
    this.emitProbe = false,
  });

  final String appPackageRoot;
  final String projectRoot;
  final String packageConfig;
  final List<CatalogEntry> entries;

  /// Makes the generated guest print a periodic `FW-PROBE:` line naming the
  /// live entry and the text it is rendering. Used by the headless check.
  final bool emitProbe;

  Map<String, Object?> toJson() => {
    'appPackageRoot': appPackageRoot,
    'projectRoot': projectRoot,
    'packageConfig': packageConfig,
    'emitProbe': emitProbe,
    'entries': [
      for (var e in entries)
        {
          'path': e.path,
          'symbol': e.symbol,
          'name': e.name,
          'annotation': e.annotation,
        },
    ],
  };

  static DaemonConfig fromJson(Map<String, Object?> json) => DaemonConfig(
    appPackageRoot: json['appPackageRoot']! as String,
    projectRoot: json['projectRoot']! as String,
    packageConfig: json['packageConfig']! as String,
    emitProbe: json['emitProbe'] as bool? ?? false,
    entries: [
      for (var e in (json['entries']! as List).cast<Map<String, Object?>>())
        CatalogEntry(
          path: e['path']! as String,
          symbol: e['symbol']! as String,
          name: e['name']! as String,
          annotation: e['annotation']! as String,
        ),
    ],
  );

  String encode() => jsonEncode(toJson());
}

/// What the daemon produced once the guest can be launched.
class DaemonReady {
  DaemonReady({
    required this.hostPath,
    required this.assetsDir,
    required this.icuData,
    required this.coldCompile,
  });

  final String hostPath;
  final String assetsDir;
  final String icuData;
  final Duration coldCompile;

  Map<String, Object?> toJson() => {
    'type': 'ready',
    'hostPath': hostPath,
    'assetsDir': assetsDir,
    'icuData': icuData,
    'coldMs': coldCompile.inMilliseconds,
  };

  static DaemonReady fromJson(Map<String, Object?> json) => DaemonReady(
    hostPath: json['hostPath']! as String,
    assetsDir: json['assetsDir']! as String,
    icuData: json['icuData']! as String,
    coldCompile: Duration(milliseconds: json['coldMs']! as int),
  );
}

/// The result of compiling one entry into the accumulating entrypoint.
class DaemonCompiled {
  DaemonCompiled({
    required this.id,
    required this.ok,
    required this.dill,
    required this.compile,
    required this.newSourceCount,
    this.error,
  });

  final String id;
  final bool ok;

  /// The kernel to hand the VM service as `rootLibUri`. Null when [ok] is false.
  final String? dill;

  final Duration compile;
  final int newSourceCount;
  final String? error;

  Map<String, Object?> toJson() => {
    'type': 'compiled',
    'id': id,
    'ok': ok,
    'dill': dill,
    'compileMs': compile.inMilliseconds,
    'newSources': newSourceCount,
    'error': error,
  };

  static DaemonCompiled fromJson(Map<String, Object?> json) => DaemonCompiled(
    id: json['id']! as String,
    ok: json['ok']! as bool,
    dill: json['dill'] as String?,
    compile: Duration(milliseconds: json['compileMs']! as int),
    newSourceCount: json['newSources']! as int,
    error: json['error'] as String?,
  );
}
