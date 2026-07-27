import 'dart:io';

import 'package:dart_mcp/stdio.dart';
import 'package:flutterware_app/src/session/mcp_server.dart';

/// flutterware as an MCP server, over stdio.
///
///     cd app && dart run bin/mcp.dart
///
/// It is an adapter and nothing more: every tool opens the same [Session] and
/// reads the same `PluginCore`s that `fw` and the GUI sidebar do. A capability
/// added to a plugin's core reaches all three without being written three
/// times — that is the parity rule holding structurally rather than by
/// discipline.
///
/// **Pure Dart, and guarded** by `test/utils/entry_point_purity_test.dart`.
///
/// stdout belongs to the protocol. Anything this process wants to say to a
/// human has to go to stderr, or it corrupts the JSON-RPC stream.
void main() {
  FlutterwareMcpServer(stdioChannel(input: stdin, output: stdout));
}
