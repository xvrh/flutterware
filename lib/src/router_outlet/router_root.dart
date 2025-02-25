import 'package:flutter/widgets.dart';
import '../utils/value_stream.dart';
import 'path.dart';
import 'provider.dart';
import 'url_source.dart';

class RouterRoot extends StatefulWidget {
  final UrlSource urlSource;
  final Widget child;

  const RouterRoot({super.key, required this.urlSource, required this.child});

  @override
  State<RouterRoot> createState() => _RouterRootState();

  static UrlSource sourceOf(BuildContext context) {
    return context
        .findAncestorStateOfType<_RouterRootState>()!
        .widget
        .urlSource;
  }

  static UrlSource? maybeSourceOf(BuildContext context) {
    return context
        .findAncestorStateOfType<_RouterRootState>()?.widget.urlSource;
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

  const SubMatchTracker({super.key, required this.child});

  @override
  SubMatchTrackerState createState() => SubMatchTrackerState();

  static SubMatchTrackerState of(BuildContext context) {
    return context.findAncestorStateOfType<SubMatchTrackerState>()!;
  }
}

class SubMatchTrackerState extends State<SubMatchTracker> {
  final allMatches = ValueStream<List<MatchedPath>>([]);

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
    allMatches.dispose();
    super.dispose();
  }
}

class SubMatches extends InheritedWidget {
  final List<MatchedPath> allMatches;

  const SubMatches({
    super.key,
    required super.child,
    required this.allMatches,
  });

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

  const RouterRootAuto({super.key, required this.child});

  @override
  State<RouterRootAuto> createState() => _RouterRootAuto();
}

class _RouterRootAuto extends State<RouterRootAuto> {
  final _urlSource = UrlSource.defaultFactory();

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
