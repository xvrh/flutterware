import 'dart:async';
import 'dart:js_interop';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:web/web.dart' as html;
import 'path.dart';
import 'url_source.dart';

UrlSource createSource() => UrlSourceWeb();

class UrlSourceWeb implements UrlSource {
  final _onChangeController = StreamController<PagePath>.broadcast();
  late PagePath _current;

  UrlSourceWeb() {
    setUrlStrategy(null);

    html.window.addEventListener(
        'hashchange',
        () {
          var path = _getHash();
          if (path != _current) {
            go(path);
          }
        }.toJS);

    _current = _getHash();
  }

  PagePath _getHash() {
    var hash = html.window.location.hash;
    if (hash.startsWith('#')) {
      hash = hash.substring(1);
    }
    return PagePath(hash, isAbsolute: true);
  }

  @override
  Stream<PagePath> get onChange => _onChangeController.stream;

  @override
  PagePath get current => _current;

  @override
  void go(PagePath path) {
    assert(path.isAbsolute);

    if (path != current) {
      _current = path;
      _onChangeController.add(path);
      html.window.location.hash = path.toString();
    }
  }

  @override
  void dispose() {
    _onChangeController.close();
  }
}
