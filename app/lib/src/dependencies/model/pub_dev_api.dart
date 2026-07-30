import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

/// What pub.dev knows about a package, beyond what is on disk.
///
/// The vendored `pub_scores` snapshot exists to work around GitHub's throttled
/// API, and it is the right answer for star counts. It is the wrong answer for
/// everything pub.dev serves itself: the copy in the tree is dated 2024-11-23,
/// so every popularity figure it carries is well over a year stale and anything
/// published since has no entry at all. pub.dev's own API is neither throttled
/// nor stale, so this asks it directly and keeps `pub_scores` for GitHub.
///
/// Two endpoints per package:
///
/// ```
/// /api/packages/<name>        latest version, published dates, repository
/// /api/packages/<name>/score  points, likes, 30-day downloads, tags
/// ```
///
/// The `tags` list is the surprise — publisher, license, supported platforms
/// and `is:wasm-ready` all arrive from one call, which is most of a
/// compatibility section for free.
class PubDevPackage {
  PubDevPackage({
    required this.name,
    this.latestVersion,
    this.published,
    this.repository,
    this.topics = const [],
    this.versions = const {},
    this.grantedPoints,
    this.maxPoints,
    this.likeCount,
    this.downloadCount30Days,
    this.tags = const [],
    this.isDiscontinued = false,
    this.replacedBy,
  });

  final String name;

  /// The newest version pub.dev has. Null when the package is not on pub.dev at
  /// all — a git or path dependency, or a private one.
  final String? latestVersion;

  /// When [latestVersion] was published.
  final DateTime? published;

  final String? repository;
  final List<String> topics;

  /// Publication date per version, so a resolved version can say how old it is.
  final Map<String, DateTime> versions;

  final int? grantedPoints;
  final int? maxPoints;
  final int? likeCount;

  /// Downloads in the last 30 days — a far more legible number than the
  /// percentile "popularity" the old snapshot carried.
  final int? downloadCount30Days;

  /// Raw pub.dev tags: `publisher:dart.dev`, `license:bsd-3-clause`,
  /// `platform:android`, `sdk:flutter`, `is:wasm-ready`, …
  final List<String> tags;

  final bool isDiscontinued;
  final String? replacedBy;

  String? get publisher => _tagValue('publisher');

  /// SPDX-ish license id. pub.dev also emits `license:fsf-libre` and
  /// `license:osi-approved` alongside the real one, which are properties of the
  /// licence rather than its name.
  String? get license {
    var licenses = _tagValues(
      'license',
    ).where((e) => e != 'fsf-libre' && e != 'osi-approved').toList();
    return licenses.isEmpty ? null : licenses.first;
  }

  List<String> get platforms => _tagValues('platform');

  List<String> get sdks => _tagValues('sdk');

  bool get isWasmReady => tags.contains('is:wasm-ready');

  bool get isDart3Compatible => tags.contains('is:dart3-compatible');

  /// When the version you resolved was published, if pub.dev lists it.
  DateTime? publishedAt(String version) => versions[version];

  /// Whether [version] is what pub.dev currently serves as latest.
  bool isLatest(String version) => latestVersion == version;

  String? _tagValue(String prefix) {
    var values = _tagValues(prefix);
    return values.isEmpty ? null : values.first;
  }

  List<String> _tagValues(String prefix) => [
    for (var tag in tags)
      if (tag.startsWith('$prefix:')) tag.substring(prefix.length + 1),
  ];

  Map<String, Object?> toJson() => {
    'name': name,
    if (latestVersion != null) 'latestVersion': latestVersion,
    if (published != null) 'published': published!.toIso8601String(),
    if (repository != null) 'repository': repository,
    if (topics.isNotEmpty) 'topics': topics,
    if (versions.isNotEmpty)
      'versions': {
        for (var entry in versions.entries)
          entry.key: entry.value.toIso8601String(),
      },
    if (grantedPoints != null) 'grantedPoints': grantedPoints,
    if (maxPoints != null) 'maxPoints': maxPoints,
    if (likeCount != null) 'likeCount': likeCount,
    if (downloadCount30Days != null) 'downloadCount30Days': downloadCount30Days,
    if (tags.isNotEmpty) 'tags': tags,
    if (isDiscontinued) 'isDiscontinued': true,
    if (replacedBy != null) 'replacedBy': replacedBy,
  };

  factory PubDevPackage.fromJson(Map<String, Object?> json) => PubDevPackage(
    name: json['name']! as String,
    latestVersion: json['latestVersion'] as String?,
    published: _date(json['published']),
    repository: json['repository'] as String?,
    topics: _strings(json['topics']),
    versions: {
      for (var entry in (json['versions'] as Map? ?? const {}).entries)
        '${entry.key}': ?_date(entry.value),
    },
    grantedPoints: json['grantedPoints'] as int?,
    maxPoints: json['maxPoints'] as int?,
    likeCount: json['likeCount'] as int?,
    downloadCount30Days: json['downloadCount30Days'] as int?,
    tags: _strings(json['tags']),
    isDiscontinued: json['isDiscontinued'] == true,
    replacedBy: json['replacedBy'] as String?,
  );

  /// Merges the two endpoints into one record.
  factory PubDevPackage.fromApi(
    String name, {
    Map<String, Object?>? package,
    Map<String, Object?>? score,
  }) {
    var latest = package?['latest'] as Map<String, Object?>?;
    var pubspec = latest?['pubspec'] as Map<String, Object?>?;

    return PubDevPackage(
      name: name,
      latestVersion: latest?['version'] as String?,
      published: _date(latest?['published']),
      repository:
          pubspec?['repository'] as String? ?? pubspec?['homepage'] as String?,
      topics: _strings(pubspec?['topics']),
      versions: {
        for (var version in (package?['versions'] as List? ?? const []))
          if (version is Map<String, Object?>)
            '${version['version']}': ?_date(version['published']),
      },
      grantedPoints: score?['grantedPoints'] as int?,
      maxPoints: score?['maxPoints'] as int?,
      likeCount: score?['likeCount'] as int?,
      downloadCount30Days: score?['downloadCount30Days'] as int?,
      tags: _strings(score?['tags']),
      isDiscontinued: package?['isDiscontinued'] == true,
      replacedBy: package?['replacedBy'] as String?,
    );
  }

  static DateTime? _date(Object? value) =>
      value is String ? DateTime.tryParse(value) : null;

  static List<String> _strings(Object? value) => [
    for (var entry in value as List? ?? const []) '$entry',
  ];
}

/// Fetches [PubDevPackage]s, with an on-disk cache.
///
/// **Never throws for a network problem.** A detail page that failed to load
/// because pub.dev was unreachable would be worse than one missing its download
/// count: everything else on it comes from disk and is still true. A failed
/// fetch returns the cached copy if there is one, and null otherwise.
class PubDevApi {
  PubDevApi({http.Client? client, Directory? cacheDirectory, this.ttl = _ttl})
    : _client = client ?? http.Client(),
      _cacheDirectory = cacheDirectory ?? defaultCacheDirectory();

  static const _ttl = Duration(hours: 12);

  final http.Client _client;
  final Directory _cacheDirectory;

  /// How long a cached entry is served without asking again. Package metadata
  /// changes on the order of days; a working session should hit the network
  /// about once.
  final Duration ttl;

  final _memory = <String, PubDevPackage>{};

  /// `~/.flutterware/cache/pub.dev` — the same home-directory convention the
  /// bootstrapper uses for the installed copy.
  static Directory defaultCacheDirectory() {
    var home =
        Platform.environment[Platform.isWindows ? 'APPDATA' : 'HOME'] ?? '.';
    return Directory(p.join(home, '.flutterware', 'cache', 'pub.dev'));
  }

  Future<PubDevPackage?> fetch(String name) async {
    if (_memory[name] case var cached?) return cached;

    var file = _fileFor(name);
    var fresh = await _readCache(file);
    if (fresh != null) return _memory[name] = fresh;

    var downloaded = await _download(name);
    if (downloaded != null) {
      _memory[name] = downloaded;
      await _writeCache(file, downloaded);
      return downloaded;
    }

    // Offline, rate-limited, or the package is not on pub.dev. A stale cache
    // beats nothing; expiry is a refresh policy, not a correctness boundary.
    var stale = await _readCache(file, ignoreAge: true);
    if (stale != null) _memory[name] = stale;
    return stale;
  }

  Future<PubDevPackage?> _download(String name) async {
    try {
      var results = await Future.wait([
        _getJson('/api/packages/$name'),
        _getJson('/api/packages/$name/score'),
      ]);
      // No package document means there is nothing to describe — a git-only or
      // private package. The score alone would be meaningless.
      if (results.first == null) return null;
      return PubDevPackage.fromApi(
        name,
        package: results.first,
        score: results.last,
      );
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, Object?>?> _getJson(String path) async {
    var response = await _client.get(
      Uri.https('pub.dev', path),
      headers: const {'Accept': 'application/vnd.pub.v2+json'},
    );
    if (response.statusCode != 200) return null;
    return jsonDecode(response.body) as Map<String, Object?>;
  }

  File _fileFor(String name) =>
      File(p.join(_cacheDirectory.path, '$name.json'));

  Future<PubDevPackage?> _readCache(File file, {bool ignoreAge = false}) async {
    try {
      if (!file.existsSync()) return null;
      if (!ignoreAge) {
        var age = DateTime.now().difference(file.lastModifiedSync());
        if (age > ttl) return null;
      }
      return PubDevPackage.fromJson(
        jsonDecode(await file.readAsString()) as Map<String, Object?>,
      );
    } catch (_) {
      // A truncated or older-shaped cache file is not worth a crash.
      return null;
    }
  }

  Future<void> _writeCache(File file, PubDevPackage package) async {
    try {
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode(package.toJson()));
    } catch (_) {
      // A cache that cannot be written is a slower tool, not a broken one.
    }
  }

  void dispose() => _client.close();
}
