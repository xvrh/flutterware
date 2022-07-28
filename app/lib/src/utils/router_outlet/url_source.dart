import 'path.dart';
import 'url_source_fake.dart' if (dart.library.html) 'url_source_web.dart'
    as source;

abstract class UrlSource {
  static UrlSource forPlatform() => source.createSource();

  void go(PagePath path);
  Stream<PagePath> get onChange;
  PagePath get current;
  void dispose();
}
