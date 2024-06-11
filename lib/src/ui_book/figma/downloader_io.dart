import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutterware/src/ui_book/figma/service.dart';
import 'package:http/http.dart';
import 'package:flutter/rendering.dart';
import 'package:path/path.dart' as p;
import 'link.dart';

class FigmaCredentialsRequiredException implements Exception {}

class FigmaDownloaderIO implements FigmaDownloader {
  final FigmaCache cache;

  FigmaDownloaderIO(this.cache);

  @override
  Future<ImageProvider> readFigmaScreenshot(FigmaLink url, {FigmaCredentials? credentials}) async {
    if (credentials == null) {
      throw FigmaCredentialsRequiredException();
    }
    var file = cache.get(url);
    if (file == null) {
      var figmaId = FigmaId.parse(url);
      var bytes = await _download(figmaId, credentials: credentials);
      file = await cache.store(url, bytes);
    }

    return FileImage(file);
  }

  @override
  void clearCacheForLink(FigmaLink link) {
    cache.remove(link);
  }

  Future<Uint8List> _download(FigmaId id, {required FigmaCredentials credentials}) async {
    var basePath = Uri(
        scheme: 'https',
        host: 'api.figma.com',
        path: 'v1/images/${id.fileId}',
        queryParameters: {
          'ids': id.nodeId,
          'scale': '1',
        }).toString();

    var json = await read(Uri.parse(basePath), headers: {
      'X-Figma-Token': credentials.token,
      'Accept': 'application/json',
    });

    var images = (jsonDecode(json) as Map<String, dynamic>)['images']
        as Map<String, dynamic>;
    var myImage = images[id.nodeId.replaceAll('-', ':')]! as String;

    var bytes = await readBytes(Uri.parse(myImage));

    return bytes;
  }

  @override
  void clearCache() {
    cache.clear();
  }
}

class FigmaCache {
  final Directory directory;

  FigmaCache(this.directory);

  String _fileNameFor(FigmaLink uri) {
    var hash = sha1.convert(utf8.encode(uri.uri));
    return p.join(directory.path, '$hash.png');
  }

  File? get(FigmaLink uri) {
    var file = File(_fileNameFor(uri));
    if (file.existsSync()) {
      return file;
    }
    return null;
  }

  Future<File> store(FigmaLink uri, Uint8List bytes) async {
    var file = File(_fileNameFor(uri))..createSync(recursive: true);
    await file.writeAsBytes(bytes);
    return file;
  }

  void remove(FigmaLink uri) {
    var file = File(_fileNameFor(uri));
    if (file.existsSync()) {
      file.deleteSync();
    }
  }

  void clear() {
    directory.deleteSync(recursive: true);
  }
}
