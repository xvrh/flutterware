import 'package:flutter/widgets.dart';
import 'link.dart';
import 'service.dart';

class FigmaDownloaderWeb extends FigmaDownloader {
  @override
  void clearCacheForLink(FigmaLink link) {
    throw UnimplementedError();
  }

  @override
  Future<ImageProvider<Object>> readFigmaScreenshot(FigmaLink url,
      {FigmaCredentials? credentials}) async {
    return NetworkImage(
        'https://upload.wikimedia.org/wikipedia/commons/thumb/6/65/No-Image-Placeholder.svg/1665px-No-Image-Placeholder.svg.png');
  }
}

class FigmaLinksSourceWeb extends FigmaLinksSource {
  @override
  bool get canSave => false;

  @override
  Future<FigmaLinks> read() async {
    // TODO: load a real json file added by the "offline" figma downloader
    return FigmaLinks({});
  }

  @override
  void save(FigmaLinks data) {
    throw UnimplementedError();
  }
}
