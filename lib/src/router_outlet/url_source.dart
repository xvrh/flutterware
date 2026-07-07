import 'path.dart';
import 'url_source_fake.dart'
    if (dart.library.js_interop) 'url_source_web.dart'
    as source;
import 'url_source_fake.dart' as fake_lib;

abstract class UrlSource {
  static UrlSource auto() => source.createSource();

  static UrlSource Function() defaultFactory = UrlSource.auto;

  static UrlSource fake({PagePath? initial}) =>
      fake_lib.UrlSourceFake(initial: initial);

  /// Navigates to [path]. When [replace] is true, the current history entry is
  /// overwritten instead of a new one being pushed — so in-page state that maps
  /// to the URL (a selected tab, a filter) stays shareable without every change
  /// adding a back-button stop. In-app listeners are notified either way.
  void go(PagePath path, {bool replace = false});
  Stream<PagePath> get onChange;
  PagePath get current;
  void dispose();
}
