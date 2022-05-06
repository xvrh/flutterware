import 'package:flutter/widgets.dart';
import 'package:rxdart/rxdart.dart';
import 'path.dart';
import 'provider.dart';
import 'url_source.dart';

//TODO(xha): try to get rid of the class, we can just inject it at the first
// RouterOutlet?
class RouterRoot extends StatefulWidget {
  final UrlSource urlSource;
  final Widget child;

  const RouterRoot({Key? key, required this.urlSource, required this.child})
      : super(key: key);

  @override
  _RouterRootState createState() => _RouterRootState();

  static UrlSource sourceOf(BuildContext context) {
    return context
        .findAncestorStateOfType<_RouterRootState>()!
        .widget
        .urlSource;
  }
}

class _RouterRootState extends State<RouterRoot> {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<PagePath>(
      stream: widget.urlSource.onChange,
      initialData: widget.urlSource.current,
      builder: (context, snapshot) {
        return MatchedPathProvider(
          path: snapshot.requireData.rootMatch,
          child: SubMatchTracker(child: widget.child),
        );
      },
    );
  }
}

class SubMatchTracker extends StatefulWidget {
  final Widget child;

  const SubMatchTracker({Key? key, required this.child}) : super(key: key);

  @override
  SubMatchTrackerState createState() => SubMatchTrackerState();

  static SubMatchTrackerState of(BuildContext context) {
    return context.findAncestorStateOfType<SubMatchTrackerState>()!;
  }
}

class SubMatchTrackerState extends State<SubMatchTracker> {
  final allMatches = BehaviorSubject<List<MatchedPath>>.seeded([]);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<MatchedPath>>(
      stream: allMatches.stream,
      initialData: allMatches.value,
      builder: (context, snapshot) {
        return SubMatches(
          allMatches: snapshot.requireData,
          child: widget.child,
        );
      },
    );
  }

  void addSubMatch(MatchedPath path) {
    if (!allMatches.value.contains(path)) {
      allMatches.add(allMatches.value..add(path));
    }
  }

  void removeSubMatch(MatchedPath? path) {
    if (path != null) {
      allMatches.add(allMatches.value..remove(path));
    }
  }

  @override
  void dispose() {
    allMatches.close();
    super.dispose();
  }
}

class SubMatches extends InheritedWidget {
  final List<MatchedPath> allMatches;

  const SubMatches({
    Key? key,
    required Widget child,
    required this.allMatches,
  }) : super(key: key, child: child);

  static List<MatchedPath> of(BuildContext context) {
    final result = context.dependOnInheritedWidgetOfExactType<SubMatches>()!;
    return result.allMatches;
  }

  @override
  bool updateShouldNotify(SubMatches oldWidget) {
    return true;
  }
}

class RouterRootAuto extends StatefulWidget {
  final Widget child;

  const RouterRootAuto({Key? key, required this.child}) : super(key: key);

  @override
  _RouterRootAuto createState() => _RouterRootAuto();
}

class _RouterRootAuto extends State<RouterRootAuto> {
  final _urlSource = UrlSource.auto();

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return RouterRoot(
      urlSource: _urlSource,
      child: widget.child,
    );
  }

  @override
  void dispose() {
    _urlSource.dispose();
    super.dispose();
  }
}
