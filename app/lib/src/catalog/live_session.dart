import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../embedder/guest_vm_service.dart';
import '../utils/run_dir.dart';

/// Where a running GUI session publishes the guest it is driving, so that `fw`
/// and MCP can read the demo a person is **actually looking at**.
///
/// The same shape as [DaemonAddress] and for the same reason: *"the address is
/// derived, not assigned, so every consumer that wants the same catalog — the
/// GUI, `fw`, an agent, a test — arrives at the same socket without being told
/// about each other."* That sentence was written about the compiler daemon.
/// This is it one level up, about the running guest.
///
/// **Keyed on the project root alone**, not on a [DaemonConfig]. The two sides
/// build different configs for the same package today — the GUI's
/// `appPackageRoot` is the app tool directory, `fw`'s is the package itself —
/// so a config-derived key would never match. The project root is what both
/// sides genuinely agree on, and it is the identity that matters: *is anyone
/// looking at this package's catalog right now.*
class LiveSession {
  const LiveSession({
    required this.projectRoot,
    required this.vmServiceUri,
    required this.pid,
  });

  factory LiveSession.fromJson(Map<String, Object?> json) => LiveSession(
    projectRoot: json['projectRoot'] as String? ?? '',
    vmServiceUri: json['vmServiceUri'] as String? ?? '',
    pid: json['pid'] as int? ?? 0,
  );

  final String projectRoot;

  /// The `http://` URI the guest printed at startup — what
  /// [GuestVmService.connect] takes.
  final String vmServiceUri;

  /// The GUI process, for a human reading the file. Liveness is decided by
  /// connecting, not by this — see [attachToLiveSession].
  final int pid;

  Map<String, Object?> toJson() => {
    'projectRoot': projectRoot,
    'vmServiceUri': vmServiceUri,
    'pid': pid,
  };

  /// **Deliberately does not carry the entry on screen.** It changes every time
  /// someone clicks, and a file kept in step with a browsing user is a file
  /// that is wrong for the moment between the click and the write. The guest
  /// knows which entry it is holding and is asked.
  static File fileFor(String projectRoot) =>
      File(p.join(flutterwareRunDir(), 'live-${keyFor(projectRoot)}.json'));

  /// Canonicalised so that `/a/b`, `/a/b/` and `/a/b/.` are one catalog — the
  /// GUI joins a package path onto a worktree and `fw` does the same, and for
  /// the root package that join ends in `/.`.
  static String keyFor(String projectRoot) => sha1
      .convert(utf8.encode(p.canonicalize(projectRoot)))
      .toString()
      .substring(0, 16);

  /// Announces this session. Called once the guest's VM service is up, because
  /// a URI published before it answers is a URI that fails to connect.
  static void publish(LiveSession session) {
    var file = fileFor(session.projectRoot);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(jsonEncode(session.toJson()));
  }

  static LiveSession? read(String projectRoot) {
    var file = fileFor(projectRoot);
    if (!file.existsSync()) return null;
    try {
      return LiveSession.fromJson(
        jsonDecode(file.readAsStringSync()) as Map<String, Object?>,
      );
    } catch (_) {
      // A half-written or hand-edited file is the same as no session. Nothing
      // here is worth failing a read the caller could answer another way.
      return null;
    }
  }

  static void clear(String projectRoot) {
    var file = fileFor(projectRoot);
    if (file.existsSync()) file.deleteSync();
  }
}

/// Connects to the session published for [projectRoot], or null when there is
/// none to connect to.
///
/// **Liveness is decided by connecting**, not by checking a pid. A GUI that
/// crashed cannot delete its own file, and Dart offers no way to probe a pid
/// without signalling it — where trying the URI answers the only question that
/// matters, which is whether the guest will talk. A handle that will not
/// connect is deleted on the way past, so a stale file costs one timeout once
/// rather than on every call forever.
///
/// The caller owns the returned connection and must close it.
Future<GuestVmService?> attachToLiveSession(
  String projectRoot, {
  Duration timeout = const Duration(seconds: 2),
}) async {
  var session = LiveSession.read(projectRoot);
  if (session == null || session.vmServiceUri.isEmpty) return null;
  try {
    return await GuestVmService.connect(session.vmServiceUri).timeout(timeout);
  } catch (_) {
    LiveSession.clear(projectRoot);
    return null;
  }
}
