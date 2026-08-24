import 'dart:async';

import 'path.dart';
import 'url_source.dart';

UrlSource createSource() => UrlSourceFake();

class UrlSourceFake implements UrlSource {
  final _onChangeController = StreamController<PagePath>.broadcast();
  late PagePath _current;

  UrlSourceFake({PagePath? initial}) : _current = initial ?? PagePath.root;

  @override
  Stream<PagePath> get onChange => _onChangeController.stream;

  @override
  PagePath get current => _current;

  @override
  void go(PagePath path, {bool replace = false}) {
    assert(path.isAbsolute);

    // No history stack to distinguish push from replace here; both just move
    // the current path and notify.
    if (path != _current) {
      _current = path;
      _onChangeController.add(path);
    }
  }

  @override
  void dispose() {
    _onChangeController.close();
  }
}
