import 'package:flutter/widgets.dart';
import 'provider.dart';
import 'router_root.dart';

extension UrlRouterExtension on BuildContext {
  void go(String url) => router.go(url);

  RouterReference get router => RouterReference(this);
}

class RouterReference {
  final BuildContext context;
  late final urlSource = RouterRoot.sourceOf(context);
  late final path = MatchedPathProvider.of(context);
  late final _subMatches = SubMatches.of(context);

  RouterReference(this.context);

  Map<String, String> get allArgs {
    return {
      for (var subMatch in _subMatches) ...subMatch.args,
    };
  }

  void go(String url) {
    var newPath = path.go(url);
    urlSource.go(newPath);
  }

  bool isSelected(String url) {
    return path.isSelected(url);
  }

  int? selectedIndex(Iterable<String> urls) {
    return path.selectedIndex(urls);
  }
}
