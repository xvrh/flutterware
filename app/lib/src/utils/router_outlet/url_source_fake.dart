import 'dart:async';
import 'path.dart';
import 'url_source.dart';

UrlSource createSource() => UrlSourceFake();

class UrlSourceFake implements UrlSource {
  final _onChangeController = StreamController<PagePath>.broadcast();
  PagePath _current = PagePath.root;

  @override
  Stream<PagePath> get onChange => _onChangeController.stream;

  @override
  PagePath get current => _current;

  @override
  void go(PagePath path) {
    assert(path.isAbsolute);

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
