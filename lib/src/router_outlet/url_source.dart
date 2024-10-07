import 'path.dart';
import 'url_source_fake.dart'
    if (dart.library.js_interop) 'url_source_web.dart' as source;

UrlSource Function() urlSourceFactory = UrlSource.auto;

abstract class UrlSource {
  static UrlSource auto() => source.createSource();

  void go(PagePath path);
  Stream<PagePath> get onChange;
  PagePath get current;
  void dispose();
}
