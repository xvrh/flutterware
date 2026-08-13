import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;

import 'artifacts.dart';

/// Artifacts fetched from wherever the page was served.
///
/// [base] is resolved against, so the paths in `report.json` stay exactly as
/// the export wrote them — relative, and therefore still correct when the
/// directory is moved, zipped into a CI artifact, or served under a
/// subdirectory with `--base-href`.
class HttpScenarioArtifacts extends ScenarioArtifacts {
  const HttpScenarioArtifacts(this.base);

  final Uri base;

  Uri _uri(String path) => base.resolve(path);

  @override
  Future<Uint8List?> readBytes(String path) async {
    try {
      var response = await http.get(_uri(path));
      return response.statusCode == 200 ? response.bodyBytes : null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<String?> readString(String path) async {
    try {
      var response = await http.get(_uri(path));
      return response.statusCode == 200 ? response.body : null;
    } catch (_) {
      return null;
    }
  }

  @override
  ImageProvider encodedImage(String path) =>
      NetworkImage(_uri(path).toString());

  @override
  Uri uriOf(String path) => _uri(path);

  @override
  bool operator ==(Object other) =>
      other is HttpScenarioArtifacts && other.base == base;

  @override
  int get hashCode => base.hashCode;
}
