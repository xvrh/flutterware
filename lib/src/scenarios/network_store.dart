import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

/// Where a package keeps what its scenarios recorded, unless it says otherwise.
///
/// Package-relative and committed. Both lanes run with the package root as
/// their working directory — `flutter test` does, and the runner spawns
/// `flutter_tester` with `workingDirectory: packageRoot` — so this resolves
/// the same in both without anybody passing a path.
///
/// Under `test/` rather than under `build/` because it is an **input**. A
/// recording that is not committed makes a fresh clone need a network to
/// reproduce yesterday's screenshots, which is the whole thing this exists to
/// avoid.
const defaultScenarioNetworkStore = 'test/scenarios/network';

/// Where the recording is, when something says so: a `fw.network.store`
/// dart-define, then `FW_NETWORK_STORE`, then [defaultScenarioNetworkStore].
///
/// The same pair every other "the host tells the test process something"
/// setting reads. A monorepo whose packages share one API is the case it is
/// for — and a test that needs a temporary one sets [scenarioNetworkStorePath]
/// directly.
String resolvedScenarioNetworkStore() {
  if (scenarioNetworkStorePath case var path?) return path;
  const define = String.fromEnvironment('fw.network.store');
  if (define.isNotEmpty) return define;
  var env = Platform.environment['FW_NETWORK_STORE'];
  return env == null || env.isEmpty ? defaultScenarioNetworkStore : env;
}

/// Set by the harness, or by a test that keeps its recording in a temporary
/// directory; null everywhere else.
String? scenarioNetworkStorePath;

/// One recorded exchange.
class ScenarioRecording {
  ScenarioRecording({
    required this.method,
    required this.url,
    required this.status,
    required this.body,
    this.contentType,
    this.recorded,
  });

  final String method;
  final Uri url;
  final int status;
  final Uint8List body;

  /// The only response header kept. See [ScenarioNetworkStore.write] for why
  /// there is exactly one.
  final String? contentType;

  /// When it was fetched — what a stale recording is spotted by.
  final DateTime? recorded;

  /// What identifies this exchange: the method and the whole url, query
  /// included.
  ///
  /// Exact, and no normalisation. A store that quietly answered
  /// `?page=1` with what it recorded for `?page=2` would be worse than no
  /// store at all, and a request carrying a nonce is better served by a stub
  /// that says so than by a matcher guessing which parts of a url matter.
  String get key => '$method $url';
}

/// What the scenarios of one package recorded, on disk.
///
/// **One file per exchange, and no index.** `flutter test` runs test files
/// concurrently, in separate processes, so a single index would be a
/// read-modify-write race between them — and a recording that loses entries
/// depending on how the runner scheduled the suite is not a recording. Two
/// processes writing the same exchange write the same path, which is a
/// last-writer-wins on identical bytes.
///
/// The body is a **sibling file with the right extension**, never a string
/// inside the metadata. A committed recording is read in a diff, and a 5KB
/// JSON response escaped into one line of a `.json` field is a recording
/// nobody reviews.
class ScenarioNetworkStore {
  ScenarioNetworkStore(this.directory);

  /// Where the files live. Absolute, or relative to the working directory —
  /// which both lanes set to the package root.
  final String directory;

  /// What [method] [url] was recorded as, or null when nothing was.
  ScenarioRecording? read(String method, Uri url) {
    var file = File(p.join(directory, '${_name(method, url)}.json'));
    if (!file.existsSync()) return null;
    var json = jsonDecode(file.readAsStringSync());
    if (json is! Map<String, Object?>) return null;
    // The url is read back off the file rather than trusted from the caller:
    // a digest collision, or a hand-edited file, must answer for what it
    // actually holds or refuse — never for what was asked.
    if (json['method'] != method || json['url'] != '$url') return null;
    return ScenarioRecording(
      method: method,
      url: url,
      status: switch (json['status']) {
        int code => code,
        _ => 200,
      },
      contentType: json['contentType'] as String?,
      body: switch (json['body']) {
        String name => _readBody(p.join(directory, name)),
        _ => Uint8List(0),
      },
      recorded: switch (json['recorded']) {
        String raw => DateTime.tryParse(raw),
        _ => null,
      },
    );
  }

  /// Writes [recording], replacing whatever was there for the same exchange.
  ///
  /// **Only the status, the content type and the body are kept.** No request
  /// headers — they are not part of the key, so storing them would be storing
  /// an `Authorization` into a committed file for nothing — and no response
  /// headers but the one the body cannot be decoded without. `Set-Cookie` is
  /// the header a recording would leak a session through, and the way it is
  /// not leaked is that nothing here can write it.
  ///
  /// A response *body* is still yours to read before committing: an endpoint
  /// that answers with a token answers with a token. That is true of any
  /// fixture and there is nothing this can do about it beyond saying so.
  void write(ScenarioRecording recording) {
    Directory(directory).createSync(recursive: true);
    var name = _name(recording.method, recording.url);
    var body = recording.body.isEmpty
        ? null
        : '$name.body.${_extensionFor(recording.contentType)}';
    if (body != null) {
      File(p.join(directory, body)).writeAsBytesSync(recording.body);
    } else {
      _deleteBodies(name);
    }
    File(p.join(directory, '$name.json')).writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert({'version': 1, 'method': recording.method, 'url': '${recording.url}', 'status': recording.status, 'contentType': ?recording.contentType, 'bytes': recording.body.length, 'body': ?body, 'recorded': (recording.recorded ?? DateTime.now().toUtc()).toIso8601String()})}\n',
    );
  }

  /// Every exchange the store holds, as `METHOD url`, in file order.
  ///
  /// Read by a refusal rather than by the funnel: a miss is worth answering
  /// with what the store *does* have for that host, and the walk is only paid
  /// for on the step that already failed.
  List<String> keys() {
    var dir = Directory(directory);
    if (!dir.existsSync()) return const [];
    var keys = <String>[];
    for (var entry in dir.listSync().whereType<File>()) {
      if (!entry.path.endsWith('.json')) continue;
      try {
        var json = jsonDecode(entry.readAsStringSync());
        if (json case {'method': String method, 'url': String url}) {
          keys.add('$method $url');
        }
      } on FormatException {
        // A file somebody hand-edited into invalid JSON is not a reason for a
        // refusal to fail instead of explaining itself.
        continue;
      }
    }
    return keys..sort();
  }

  Uint8List _readBody(String path) {
    var file = File(path);
    return file.existsSync() ? file.readAsBytesSync() : Uint8List(0);
  }

  void _deleteBodies(String name) {
    var dir = Directory(directory);
    if (!dir.existsSync()) return;
    for (var entry in dir.listSync().whereType<File>()) {
      if (p.basename(entry.path).startsWith('$name.body.')) {
        entry.deleteSync();
      }
    }
  }

  /// A file name that is readable in a diff and unique by construction.
  ///
  /// The slug is for the human reading `git status`; the digest is what makes
  /// it an identity. Neither alone would do: two urls slug to the same thing
  /// often (`/users/1` and `/users/2` once the digits are stripped is a design
  /// nobody wants, and keeping them still collides on length), and a bare
  /// digest is a folder of hex nobody can review.
  static String _name(String method, Uri url) {
    var digest = sha1.convert(utf8.encode('$method $url')).toString();
    return '${_slug(method, url)}-${digest.substring(0, 8)}';
  }

  static String _slug(String method, Uri url) {
    var text = '$method ${url.host}${url.path}'.toLowerCase();
    var slug = text
        .replaceAll(RegExp('[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return slug.length <= 60 ? slug : slug.substring(0, 60);
  }

  /// What a body file is called, so an editor opens it as what it is.
  static String _extensionFor(String? contentType) {
    var type = (contentType ?? '').split(';').first.trim().toLowerCase();
    return switch (type) {
      'application/json' || 'text/json' => 'json',
      'image/png' => 'png',
      'image/jpeg' || 'image/jpg' => 'jpg',
      'image/gif' => 'gif',
      'image/webp' => 'webp',
      'image/svg+xml' => 'svg',
      'text/html' => 'html',
      'text/css' => 'css',
      'text/csv' => 'csv',
      'application/xml' || 'text/xml' => 'xml',
      _ when type.startsWith('text/') => 'txt',
      _ when type.endsWith('+json') => 'json',
      _ => 'bin',
    };
  }
}
