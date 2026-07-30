/// How server inspection writes itself into an address, and how it reads
/// itself back out.
///
/// Both directions in one file, like `splash_address.dart`: the address is
/// written by request rows and server chips, and read by the panel deciding
/// what to show. The round trip is the contract.
///
/// The shape is `…/flutterware.server/<name>/req/<eventId>`. The server is
/// named, not pid-qualified — an address a person pastes tomorrow should
/// survive tonight's restart. When a stopped session and its successor share
/// the name, the panel prefers the one still running; the event id then
/// resolves within whichever session is shown, which is the honest answer to
/// an id from a process that no longer exists.
library;

/// A place in the inspector: a server, and optionally one of its requests.
class ServerPlace {
  const ServerPlace(this.server, {this.requestId});

  /// The announced server name — `example_server`.
  final String server;

  /// The `http` event id of a selected request, or null for the server's
  /// overview.
  final int? requestId;

  @override
  bool operator ==(Object other) =>
      other is ServerPlace &&
      other.server == server &&
      other.requestId == requestId;

  @override
  int get hashCode => Object.hash(server, requestId);

  @override
  String toString() =>
      'ServerPlace($server${requestId == null ? '' : '/req/$requestId'})';
}

/// The segments naming [server] and, if given, one request.
List<String> serverSegments(String server, {int? requestId}) => [
  server,
  if (requestId != null) ...['req', '$requestId'],
];

/// The inverse of [serverSegments].
///
/// A malformed tail (`req` without an id, an id that is not a number) reads
/// back as the server alone rather than throwing — an address is a thing
/// people type.
ServerPlace? serverPlace(List<String> segments) {
  if (segments.isEmpty || segments.first.isEmpty) return null;
  int? requestId;
  if (segments.length >= 3 && segments[1] == 'req') {
    requestId = int.tryParse(segments[2]);
  }
  return ServerPlace(segments.first, requestId: requestId);
}
