/// The typed vocabulary of the `info` channel — what a server says about
/// itself beyond its traffic: where it listens, what it talks to, which pages
/// matter.
///
/// This is state, not timeline, carried over the same ring as everything else:
/// each `info` event carries whole sections ([ServerInfo.toJson]'s top-level
/// keys), and an attacher keeps the latest value per section
/// ([ServerInfo.fromEvents]). Publishing again with only `config:` set updates
/// config and leaves the links alone. Because the ring keeps the events
/// themselves, a config change mid-session is still visible in the raw
/// timeline — state for the panel, history for free.
///
/// Both halves live here on purpose: the server serializes these classes and
/// the attacher parses them back, so the vocabulary is defined once. The
/// masking helpers ([maskDsn], [isSecretLikeKey]) are attacher-side display
/// concerns — the wire is a local unix socket carrying what the server chose
/// to publish; what a screen shows is the attacher's decision, and it improves
/// with flutterware releases without touching anyone's server (the
/// `normalizeSql` argument).
library;

import 'attach_client.dart';

/// The channel [ServerInfo] travels on.
const infoChannel = 'info';

/// A server's self-description, published with `FlutterwareServer.info`.
///
/// Every field is a section; null means "not saying", not "clear it" — a
/// publish only replaces the sections it names.
class ServerInfo {
  ServerInfo({
    this.baseUrl,
    this.environment,
    this.links,
    this.connections,
    this.config,
  });

  /// Where the server listens — `http://localhost:8080`. Load-bearing: it is
  /// what makes the server openable in a browser and what relative
  /// [ServerLink.url]s resolve against.
  final String? baseUrl;

  /// A short environment name — `dev`, `staging`. The GUI colors it, loudly
  /// for anything production-shaped: an inspector forced on with
  /// `FW_SERVER_INSPECT=1` should say where it is pointed.
  final String? environment;

  /// The pages worth a click: health endpoint, API docs, an admin UI, a
  /// dashboard.
  final List<ServerLink>? links;

  /// What the server talks to — databases, caches, brokers.
  final List<ServerConnection>? connections;

  /// Everything else, grouped: `{'Feature flags': {'newCheckout': true}}`.
  /// Values are arbitrary JSON; the GUI renders nested ones as trees.
  final Map<String, Map<String, Object?>>? config;

  bool get isEmpty =>
      baseUrl == null &&
      environment == null &&
      (links == null || links!.isEmpty) &&
      (connections == null || connections!.isEmpty) &&
      (config == null || config!.isEmpty);

  /// Only the sections present — the merge unit on the attacher side.
  Map<String, Object?> toJson() => {
    if (baseUrl != null) 'baseUrl': baseUrl,
    if (environment != null) 'environment': environment,
    if (links != null) 'links': [for (var link in links!) link.toJson()],
    if (connections != null)
      'connections': [for (var c in connections!) c.toJson()],
    if (config != null) 'config': config,
  };

  /// Tolerant of anything the wire hands over: a section that does not have
  /// the expected shape reads back as absent rather than throwing — the same
  /// stance as `tryDecodeFrame`.
  static ServerInfo fromJson(Map<String, Object?> json) {
    List<T>? typedList<T>(Object? value, T? Function(Object?) parse) {
      if (value is! List) return null;
      var out = <T>[];
      for (var item in value) {
        var parsed = parse(item);
        if (parsed != null) out.add(parsed);
      }
      return out;
    }

    Map<String, Map<String, Object?>>? groups(Object? value) {
      if (value is! Map) return null;
      return {
        for (var entry in value.entries)
          if (entry.value is Map)
            '${entry.key}': (entry.value as Map).cast<String, Object?>(),
      };
    }

    return ServerInfo(
      baseUrl: _string(json['baseUrl']),
      environment: _string(json['environment']),
      links: typedList(json['links'], ServerLink.fromJson),
      connections: typedList(json['connections'], ServerConnection.fromJson),
      config: groups(json['config']),
    );
  }

  /// The latest published state: every `info` event's sections, in event
  /// order, later sections replacing earlier ones. What the panel and the
  /// `info` action both show, so they cannot disagree.
  static ServerInfo fromEvents(Iterable<ServerEvent> events) {
    var sections = <String, Object?>{};
    for (var event in events) {
      if (event.channel != infoChannel) continue;
      sections.addAll(event.payload);
    }
    return fromJson(sections);
  }
}

/// One page worth surfacing, rendered as a clickable link.
class ServerLink {
  ServerLink(this.label, this.url, {this.description});

  final String label;

  /// Absolute, or relative to [ServerInfo.baseUrl] — `/health` just works.
  final String url;

  final String? description;

  Map<String, Object?> toJson() => {
    'label': label,
    'url': url,
    if (description != null) 'description': description,
  };

  static ServerLink? fromJson(Object? json) {
    if (json is! Map) return null;
    var label = json['label'];
    var url = json['url'];
    if (label is! String || url is! String) return null;
    return ServerLink(label, url, description: _string(json['description']));
  }
}

/// One thing the server talks to, named by its connection string.
class ServerConnection {
  ServerConnection(this.kind, this.dsn, {this.label});

  /// `postgres`, `sqlite`, `redis`, … — a word, not an enum: the GUI shows it
  /// as a chip and does not need to understand it.
  final String kind;

  /// The connection string as the server holds it. Publish what you are
  /// willing to have on a developer's screen — attachers mask the
  /// password-shaped parts for display ([maskDsn]) but the wire carries this
  /// verbatim.
  final String dsn;

  /// Distinguishes several connections of one kind — `main`, `replica`.
  final String? label;

  Map<String, Object?> toJson() => {
    'kind': kind,
    'dsn': dsn,
    if (label != null) 'label': label,
  };

  static ServerConnection? fromJson(Object? json) {
    if (json is! Map) return null;
    var kind = json['kind'];
    var dsn = json['dsn'];
    if (kind is! String || dsn is! String) return null;
    return ServerConnection(kind, dsn, label: _string(json['label']));
  }
}

String? _string(Object? value) => value is String ? value : null;

/// [ServerLink.url] made absolute, or null when it cannot be — a relative
/// link with no [baseUrl] to resolve against, or text that does not parse.
/// The panel shows null as plain text instead of a dead link.
String? resolveLinkUrl(String url, {String? baseUrl}) {
  var uri = Uri.tryParse(url);
  if (uri == null) return null;
  if (uri.hasScheme) return url;
  if (baseUrl == null) return null;
  var base = Uri.tryParse(baseUrl);
  if (base == null || !base.hasScheme) return null;
  return base.resolveUri(uri).toString();
}

/// [dsn] with its password-shaped parts replaced for display: the userinfo
/// password of a URL (`postgres://app:secret@…`) and `password=`/`pwd=`
/// key-value segments (ADO-style strings). Copy still copies the real value —
/// this guards screenshots and screen shares, not the developer's own machine.
String maskDsn(String dsn) => dsn
    .replaceFirstMapped(
      RegExp(r'://([^/@]*):([^/@]*)@'),
      (m) => '://${m[1]}:••••@',
    )
    .replaceAllMapped(
      RegExp(r'(password|pwd)(\s*=\s*)[^;]+', caseSensitive: false),
      (m) => '${m[1]}${m[2]}••••',
    );

final _secretKeyPattern = RegExp(
  r'password|passwd|secret|token|credential|api[_-]?key|private[_-]?key',
  caseSensitive: false,
);

/// Whether a config key looks like it names a secret — masked in displays,
/// revealable with a click. Deliberately eager: masking a harmless value costs
/// one click, showing a secret on a screen share costs more.
bool isSecretLikeKey(String key) =>
    _secretKeyPattern.hasMatch(key) || key.toLowerCase() == 'key';
