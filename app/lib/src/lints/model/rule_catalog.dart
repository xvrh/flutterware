import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../../utils/run_dir.dart';

/// Everything the SDK knows about one lint rule, as published in the SDK
/// repository's machine-readable `rules.json`.
class LintRule {
  final String name;
  final String description;

  /// The full rule documentation, markdown with GOOD/BAD examples.
  final String details;

  /// `stable`, `experimental`, `deprecated` or `removed`.
  final String state;

  /// The Dart SDK that introduced the rule, e.g. `3.13`.
  final String sinceDartSdk;

  final List<String> categories;

  /// Rules that must not be enabled together with this one.
  final List<String> incompatible;

  /// `hasFix`, `needsFix`, `noFix` or `unregistered`.
  final String fixStatus;

  LintRule({
    required this.name,
    required this.description,
    required this.details,
    required this.state,
    required this.sinceDartSdk,
    required this.categories,
    required this.incompatible,
    required this.fixStatus,
  });

  bool get isActive => state == 'stable' || state == 'experimental';

  factory LintRule.fromJson(Map<String, dynamic> json) => LintRule(
    name: json['name'] as String,
    description: json['description'] as String? ?? '',
    details: json['details'] as String? ?? '',
    state: json['state'] as String? ?? 'stable',
    sinceDartSdk: json['sinceDartSdk'] as String? ?? '',
    categories: (json['categories'] as List<dynamic>? ?? []).cast<String>(),
    incompatible: (json['incompatible'] as List<dynamic>? ?? []).cast<String>(),
    fixStatus: json['fixStatus'] as String? ?? '',
  );

  Map<String, dynamic> toJson() => {
    'name': name,
    'description': description,
    'details': details,
    'state': state,
    'sinceDartSdk': sinceDartSdk,
    'categories': categories,
    'incompatible': incompatible,
    'fixStatus': fixStatus,
  };
}

/// The full rule universe for one Dart SDK version.
class LintCatalog {
  final String dartVersion;
  final List<LintRule> rules;
  final Map<String, LintRule> byName;

  LintCatalog({required this.dartVersion, required this.rules})
    : byName = {for (var r in rules) r.name: r};

  /// The rules a project on this SDK could turn on today.
  Iterable<LintRule> get active => rules.where((r) => r.isActive);
}

/// Fetches and caches `rules.json` — the linter's own machine-readable rule
/// list, published in the SDK repository at the tag of every release.
///
/// The rule set is not enumerable offline: the `analyzer` package carries only
/// an empty registry, and the rules themselves are compiled into the analysis
/// server. So the universe comes from the network once per SDK version and is
/// cached forever — the file at a version tag is immutable, which is why there
/// is no TTL.
///
/// Modeled on [PubDevApi]: a network problem is an answer (`null`), never an
/// exception. The panel degrades to the buckets it can compute locally.
class LintCatalogStore {
  final http.Client _client;
  final Directory _cacheDirectory;
  final Map<String, LintCatalog> _memory = {};

  LintCatalogStore({http.Client? client, Directory? cacheDirectory})
    : _client = client ?? http.Client(),
      _cacheDirectory = cacheDirectory ?? defaultCacheDirectory();

  static Directory defaultCacheDirectory() =>
      Directory(p.join(flutterwareDir(), 'cache', 'lint-rules'));

  /// Reads the Dart version string for [flutterSdkRoot] — the exact tag the
  /// SDK repository carries for it, e.g. `3.13.0-282.1.beta`.
  static String? dartVersionOf(String flutterSdkRoot) {
    var file = File(
      p.join(flutterSdkRoot, 'bin', 'cache', 'dart-sdk', 'version'),
    );
    try {
      var version = file.readAsStringSync().trim();
      return version.isEmpty ? null : version;
    } catch (e) {
      return null;
    }
  }

  Future<LintCatalog?> fetch(String dartVersion) async {
    var cached = cachedOnly(dartVersion);
    if (cached != null) return cached;

    var downloaded = await _download(dartVersion);
    if (downloaded != null) return _memory[dartVersion] = downloaded;
    return null;
  }

  /// Memory and disk only — the path `computeAll` may take, where the network
  /// is out of budget. After any one successful [fetch] for this SDK version
  /// this answers forever.
  LintCatalog? cachedOnly(String dartVersion) {
    var memory = _memory[dartVersion];
    if (memory != null) return memory;

    var cached = _readCache(dartVersion);
    if (cached != null) return _memory[dartVersion] = cached;
    return null;
  }

  Future<LintCatalog?> _download(String dartVersion) async {
    var url = Uri.https(
      'raw.githubusercontent.com',
      '/dart-lang/sdk/$dartVersion/pkg/linter/tool/machine/rules.json',
    );
    String body;
    try {
      var response = await _client.get(url);
      if (response.statusCode != 200) return null;
      body = response.body;
    } catch (e) {
      return null;
    }
    var catalog = _parse(dartVersion, body);
    if (catalog == null) return null;
    try {
      var file = _fileFor(dartVersion);
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(body);
    } catch (e) {
      // A cache that cannot be written only costs a refetch.
    }
    return catalog;
  }

  LintCatalog? _readCache(String dartVersion) {
    try {
      var file = _fileFor(dartVersion);
      if (!file.existsSync()) return null;
      return _parse(dartVersion, file.readAsStringSync());
    } catch (e) {
      return null;
    }
  }

  LintCatalog? _parse(String dartVersion, String body) {
    try {
      var list = jsonDecode(body) as List<dynamic>;
      return LintCatalog(
        dartVersion: dartVersion,
        rules: [
          for (var entry in list)
            LintRule.fromJson((entry as Map).cast<String, dynamic>()),
        ],
      );
    } catch (e) {
      return null;
    }
  }

  File _fileFor(String dartVersion) =>
      File(p.join(_cacheDirectory.path, '$dartVersion.json'));

  void dispose() {
    _client.close();
  }
}
