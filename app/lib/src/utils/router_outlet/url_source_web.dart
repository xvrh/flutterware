import 'dart:async';
import 'dart:html' as html;
import 'dart:ui';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'path.dart';
import 'url_source.dart';

UrlSource createSource() => UrlSourceWeb();

class UrlSourceWeb implements UrlSource {
  final _onChangeController = StreamController<PagePath>.broadcast();
  late PagePath _current;
  late StreamSubscription _hashChangeSubscription;

  UrlSourceWeb() {
    setUrlStrategy(NoOpUrlStrategy());

    _hashChangeSubscription = html.window.onHashChange.listen((_) {
      go(_getHash());
    });

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
    _hashChangeSubscription.cancel();
  }
}

class NoOpUrlStrategy extends UrlStrategy {
  @override
  VoidCallback addPopStateListener(html.EventListener fn) {
    return () {};
  }

  @override
  String getPath() {
    return '';
  }

  @override
  Object? getState() {
    return {'serialCount': 0};
  }

  @override
  Future<void> go(int count) async {}

  @override
  String prepareExternalUrl(String internalUrl) {
    return internalUrl;
  }

  @override
  void pushState(Object? state, String title, String url) {}

  @override
  void replaceState(Object? state, String title, String url) {}
}
