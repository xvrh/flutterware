import 'package:flutter/widgets.dart';
import 'path.dart';

class MatchedPathProvider extends InheritedWidget {
  final MatchedPath path;

  const MatchedPathProvider({
    super.key,
    required super.child,
    required this.path,
  });

  static MatchedPath of(BuildContext context) {
    final result =
        context.dependOnInheritedWidgetOfExactType<MatchedPathProvider>()!;
    return result.path;
  }

  @override
  bool updateShouldNotify(MatchedPathProvider oldWidget) {
    return oldWidget.path != path;
  }
}
