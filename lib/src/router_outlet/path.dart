import 'dart:core' as core;
import 'dart:core';
import 'package:collection/collection.dart';
import 'package:path/path.dart' as p;

class PagePath {
  static final root = PagePath._(const [], isAbsolute: true);
  static final _empty = PagePath._(const [], isAbsolute: false);

  final List<String> _segments;
  final bool isAbsolute;

  PagePath._(this._segments, {required this.isAbsolute})
      : assert(_segments.every((s) => s.isNotEmpty));

  factory PagePath(String path, {bool? isAbsolute}) {
    path = path.trim();
    isAbsolute ??= path.startsWith('/');
    path = _trimSlashes(path);
    var segments = path.split('/').where((e) => e.isNotEmpty).toList();
    if (segments.isNotEmpty) {
      var normalized = p.url.normalize(segments.join('/'));
      segments = p.url.split(normalized);
    }

    return PagePath._(segments, isAbsolute: isAbsolute);
  }

  MatchedPath? matches(PathPattern pattern) {
    throw core.UnimplementedError();
  }

  MatchedPath? _rootMatch;
  MatchedPath get rootMatch {
    assert(isAbsolute);

    return _rootMatch ??= MatchedPath._(
      full: this,
      current: _empty,
      matched: root,
      pattern: PathPattern._empty,
      remaining: asRelative,
      args: const {},
    );
  }

  PagePath get asRelative => PagePath._(_segments, isAbsolute: false);

  PagePath subPath(PagePath subPath) {
    assert(!subPath.isAbsolute);
    return PagePath(p.url.join(toString(), subPath.toString()),
        isAbsolute: isAbsolute);
  }

  @override
  String toString() => (isAbsolute ? '/' : '') + _segments.join('/');

  @override
  bool operator ==(other) =>
      (other is PagePath && other.toString() == toString()) ||
      (other is String && other == toString());

  @override
  int get hashCode => toString().hashCode;
}

class PathPattern {
  static final _empty = PathPattern('');

  final List<String> _segments;

  PathPattern._(this._segments);

  factory PathPattern(String path) {
    path = path.trim();
    path = _trimSlashes(path);
    return PathPattern._(path.split('/').where((e) => e.isNotEmpty).toList());
  }

  String get pattern => _segments.join('/');

  int get length => _segments.length;

  @override
  String toString() => 'PathPattern($pattern)';

  @override
  bool operator ==(other) => other is PathPattern && pattern == other.pattern;

  @override
  int get hashCode => pattern.hashCode;
}

enum RouteSelectedType { self, descendant }

class MatchedPath {
  final PathPattern pattern;
  final PagePath full;
  final PagePath matched;
  final PagePath current;
  final PagePath remaining;
  final Map<String, String> args;

  MatchedPath._({
    required this.pattern,
    required this.full,
    required this.matched,
    required this.current,
    required this.remaining,
    required this.args,
  })  : assert(matched.isAbsolute),
        assert(full.isAbsolute);

  String operator [](String key) {
    return args[key] ?? '';
  }

  core.int int(String key) => core.int.parse(this[key]);

  PagePath go(String url) {
    PagePath newPath;
    if (url.startsWith('/')) {
      newPath = PagePath(url);
    } else {
      newPath = matched.subPath(PagePath(url));
    }
    assert(newPath.isAbsolute);
    return newPath;
  }

  RouteSelectedType? isSelectedType(String url) {
    PagePath toMatch;
    if (url.startsWith('/')) {
      toMatch = PagePath(url);
    } else {
      toMatch = matched.subPath(PagePath(url));
    }

    var toMatchUrl = toMatch.toString();
    var fullUrl = full.toString();
    if (toMatchUrl == fullUrl) {
      return RouteSelectedType.self;
    } else if (p.isWithin(toMatchUrl, fullUrl)) {
      return RouteSelectedType.descendant;
    }

    return null;
  }

  bool isSelected(String url) => isSelectedType(url) != null;

  static final _findParameters = RegExp(r':([a-zA-Z0-9_]+)');
  MatchedPath? matchesRemaining(PathPattern pattern) {
    var remainingSegments = remaining._segments;
    if (remainingSegments.length < pattern._segments.length) return null;

    var matchedSegments = <String>[];
    var parameters = {...args};
    for (var segmentIndex = 0;
        segmentIndex < pattern._segments.length;
        segmentIndex++) {
      var patternSegment = pattern._segments[segmentIndex];
      var actualSegment = remainingSegments[segmentIndex];

      var matcher = RegExp(r'^' +
          patternSegment.replaceAll(_findParameters,
              r"((?:[\w'\.\-~!\$&\(\)\*\+,;=:@]|%[0-9a-fA-F]{2})+)") +
          r'$');
      var match = matcher.firstMatch(actualSegment);
      if (match == null) {
        return null;
      }
      matchedSegments.add(actualSegment);
      var parameterNames =
          _findParameters.allMatches(patternSegment).map((m) => m.group(1)!);
      var i = 0;
      for (var parameterName in parameterNames) {
        parameters[parameterName] = Uri.decodeComponent(match.group(i + 1)!);
        ++i;
      }
    }

    return MatchedPath._(
      full: full,
      current: PagePath._(matchedSegments, isAbsolute: false),
      matched: PagePath._([...matched._segments, ...matchedSegments],
          isAbsolute: true),
      pattern: pattern,
      remaining: PagePath._(
          remainingSegments.skip(pattern._segments.length).toList(),
          isAbsolute: false),
      args: parameters,
    );
  }

  @override
  String toString() =>
      'MatchedPath(full: $full, matched: $matched, remaining: $remaining)';

  @override
  bool operator ==(other) =>
      other is MatchedPath &&
      other.pattern == pattern &&
      other.full == full &&
      other.matched == matched &&
      other.current == current &&
      other.remaining == remaining &&
      const MapEquality().equals(other.args, args);

  @override
  core.int get hashCode => Object.hash(pattern, full, matched, current,
      remaining, const MapEquality().hash(args));

  core.int? selectedIndex(Iterable<String> urls) {
    var i = 0;

    core.int? selectedIndex;
    core.int? selectedLength;

    for (var url in urls) {
      if (isSelected(url)) {
        var length = url.split('/').where((e) => e.isNotEmpty).length;
        if (selectedIndex == null || length > selectedLength!) {
          selectedIndex = i;
          selectedLength = length;
        }
      }
      ++i;
    }
    return selectedIndex;
  }
}

String _trimSlashes(String url) {
  while (true) {
    var oldUrl = url;

    if (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    if (url.startsWith('/')) {
      url = url.substring(1);
    }

    if (url == oldUrl) {
      return url;
    }
  }
}
