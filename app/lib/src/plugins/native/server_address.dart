/// How server inspection writes itself into an address, and how it reads
/// itself back out.
///
/// Both directions in one file, like `splash_address.dart`: the address is
/// written by request rows, server chips and query rows, and read by the
/// panel deciding what to show. The round trip is the contract.
///
/// The shapes:
///
///     …/flutterware.server/<name>                   the overview
///     …/flutterware.server/<name>/req/<eventId>     one request
///     …/flutterware.server/<name>/sql               the SQL view
///     …/flutterware.server/<name>/sql/<shapeKey>    one query shape
///
/// The server is named, not pid-qualified — an address a person pastes
/// tomorrow should survive tonight's restart. When a stopped session and its
/// successor share the name, the panel prefers the one still running; a
/// request's event id then resolves within whichever session is shown, which
/// is the honest answer to an id from a process that no longer exists. A
/// query's `<shapeKey>` hashes the *normalized* SQL, so it survives restarts
/// outright.
library;

/// Which pane of one server the address names.
enum ServerViewKind { overview, request, sql }

/// A place in the inspector: a server, and which of its panes.
class ServerPlace {
  const ServerPlace(this.server, {this.requestId, this.queryKey})
    : view = requestId != null
          ? ServerViewKind.request
          : queryKey != null
          ? ServerViewKind.sql
          : ServerViewKind.overview;

  const ServerPlace.sql(this.server, {this.queryKey})
    : requestId = null,
      view = ServerViewKind.sql;

  /// The announced server name — `example_server`.
  final String server;

  final ServerViewKind view;

  /// The `http` event id of a selected request; only in [ServerViewKind.request].
  final int? requestId;

  /// The normalized-query hash of a selected shape, or null for the whole
  /// SQL view; only meaningful in [ServerViewKind.sql].
  final String? queryKey;

  @override
  bool operator ==(Object other) =>
      other is ServerPlace &&
      other.server == server &&
      other.view == view &&
      other.requestId == requestId &&
      other.queryKey == queryKey;

  @override
  int get hashCode => Object.hash(server, view, requestId, queryKey);

  @override
  String toString() => 'ServerPlace(${serverSegmentsOf(this).join('/')})';
}

/// The segments naming [server] and, if given, one request.
List<String> serverSegments(String server, {int? requestId}) => [
  server,
  if (requestId != null) ...['req', '$requestId'],
];

/// The segments naming the SQL view, or one query shape within it.
List<String> sqlSegments(String server, {String? queryKey}) => [
  server,
  'sql',
  ?queryKey,
];

List<String> serverSegmentsOf(ServerPlace place) => switch (place.view) {
  ServerViewKind.overview => serverSegments(place.server),
  ServerViewKind.request => serverSegments(
    place.server,
    requestId: place.requestId,
  ),
  ServerViewKind.sql => sqlSegments(place.server, queryKey: place.queryKey),
};

/// The inverse of [serverSegments] and [sqlSegments].
///
/// A malformed tail (`req` without an id, an id that is not a number) reads
/// back as the server alone rather than throwing — an address is a thing
/// people type.
ServerPlace? serverPlace(List<String> segments) {
  if (segments.isEmpty || segments.first.isEmpty) return null;
  var server = segments.first;
  if (segments.length >= 2 && segments[1] == 'sql') {
    return ServerPlace.sql(
      server,
      queryKey: segments.length >= 3 && segments[2].isNotEmpty
          ? segments[2]
          : null,
    );
  }
  if (segments.length >= 3 && segments[1] == 'req') {
    var requestId = int.tryParse(segments[2]);
    if (requestId != null) return ServerPlace(server, requestId: requestId);
  }
  return ServerPlace(server);
}
