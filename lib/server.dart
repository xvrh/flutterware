/// Live inspection for Dart servers.
///
/// The server side is [FlutterwareServer] — four primitives (`event`,
/// `span`/`spanSync`, `handle`) plus zone correlation, inert in release
/// builds and on machines without flutterware. Adapters for shelf, SQL
/// drivers and `package:logging` are copy-paste snippets over these
/// primitives; see the design doc and `examples/example/bin/example_server.dart`.
///
/// The attacher side — [scanServerHandles], [attachToServer],
/// [ServerAttachClient] — is what the GUI, `fw` and MCP read a live server
/// with. It is exported here too because it is the same protocol, and a
/// pure-Dart tool wanting to observe a server needs nothing else.
library;

export 'src/server/attach_client.dart'
    show
        ServerAttachClient,
        ServerEvent,
        ServerHello,
        ServerRequestException,
        attachToServer;
export 'src/server/inspector.dart'
    show FlutterwareServer, ServerCommandHandler, ServerInspector;
export 'src/server/normalize_sql.dart' show normalizeSql;
export 'src/server/protocol.dart'
    show ServerHandle, deleteServerHandle, existingRunDir, scanServerHandles;
