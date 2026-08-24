import 'package:flutter/widgets.dart';

import 'provider.dart';
import 'router_root.dart';

extension UrlRouterExtension on BuildContext {
  void go(String url, {Map<String, dynamic>? extra, bool replace = false}) =>
      router.go(url, extra: extra, replace: replace);

  RouterReference get router => RouterReference(this);
}

class RouterReference {
  final BuildContext context;
  late final urlSource = RouterRoot.sourceOf(context);
  late final path = MatchedPathProvider.of(context);
  late final _subMatches = SubMatches.of(context);

  RouterReference(this.context);

  Map<String, String> get allArgs {
    return {for (var subMatch in _subMatches) ...subMatch.args};
  }

  void go(String url, {Map<String, dynamic>? extra, bool replace = false}) {
    var newPath = path.resolve(url, extra: extra);
    urlSource.go(newPath, replace: replace);
  }

  bool isSelected(String url) {
    return path.isSelected(url);
  }

  int? selectedIndex(Iterable<String> urls) {
    return path.selectedIndex(urls);
  }
}
