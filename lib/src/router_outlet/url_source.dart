import 'path.dart';
import 'url_source_fake.dart' if (dart.library.js_interop) 'url_source_web.dart'
    as source;
import 'url_source_fake.dart' as fake_lib;

abstract class UrlSource {
  static UrlSource auto() => source.createSource();

  static UrlSource Function() defaultFactory = UrlSource.auto;

  static UrlSource fake() => fake_lib.createSource();

  void go(PagePath path);
  Stream<PagePath> get onChange;
  PagePath get current;
  void dispose();
}
