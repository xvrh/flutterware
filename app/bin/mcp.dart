import 'package:flutterware_app/src/session/mcp_server.dart';

/// flutterware as an MCP server, over stdio.
///
///     cd app && dart run bin/mcp.dart
///
/// The developer's entry point. An MCP client should be pointed at `fw mcp`
/// instead: this file only exists inside a checkout, where `flutterware_app`
/// is a package you can `dart run`, and an ordinary install has it unpacked
/// under a content hash in `~/.flutterware/` with no name to reach it by.
///
/// It is an adapter and nothing more: every tool opens the same `Session` and
/// reads the same `PluginCore`s that `fw` and the GUI sidebar do. A capability
/// added to a plugin's core reaches all three without being written three
/// times — that is the parity rule holding structurally rather than by
/// discipline.
///
/// **Pure Dart, and guarded** by `test/utils/entry_point_purity_test.dart`.
///
/// stdout belongs to the protocol. Anything this process wants to say to a
/// human has to go to stderr — including the session's own log records, which
/// is why [serveMcpOnStdio] and not a bare server is what both entry points
/// call.
void main() => serveMcpOnStdio();
