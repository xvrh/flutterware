import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;

import 'artifacts.dart';

/// Artifacts read off this machine's disk, where the harness just wrote them.
///
/// [root] is the worktree the report's paths are relative to — the same
/// convention every artifact path in a result follows, so a run can be read on
/// another checkout without rewriting anything.
///
/// **Reads synchronously and hands back a [SynchronousFuture].** The interface
/// is asynchronous because the other implementation fetches over a network;
/// this one opens files the harness wrote a moment ago, and going through the
/// thread pool for them would put a frame — and in a widget test, a hang —
/// between opening a step and seeing its tree.
class FileScenarioArtifacts extends ScenarioArtifacts {
  const FileScenarioArtifacts(this.root);

  final String root;

  File _file(String path) => File(p.join(root, path));

  T? _read<T>(String path, T Function(File) read) {
    var file = _file(path);
    if (!file.existsSync()) return null;
    try {
      return read(file);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<Uint8List?> readBytes(String path) =>
      SynchronousFuture(_read(path, (file) => file.readAsBytesSync()));

  @override
  Future<String?> readString(String path) =>
      SynchronousFuture(_read(path, (file) => file.readAsStringSync()));

  @override
  ImageProvider encodedImage(String path) => FileImage(_file(path));

  @override
  Uri uriOf(String path) => Uri.file(_file(path).absolute.path);

  @override
  bool operator ==(Object other) =>
      other is FileScenarioArtifacts && other.root == root;

  @override
  int get hashCode => root.hashCode;
}
