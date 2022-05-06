import 'package:test/test.dart';

void check(actual, matcher, {String? reason}) {
  var formatter = (actual, Matcher matcher, String? reason, Map matchState) {
    var mismatchDescription = StringDescription();
    matcher.describeMismatch(actual, mismatchDescription, matchState, false);

    return _formatFailure(matcher, actual, mismatchDescription.toString(),
        reason: reason);
  };

  matcher = wrapMatcher(matcher);

  var matchState = {};
  try {
    if ((matcher as Matcher).matches(actual, matchState)) {
      return;
    }
  } catch (e, trace) {
    reason ??= '$e at $trace';
  }
  fail(formatter(actual, matcher as Matcher, reason, matchState));
}

String _formatFailure(Matcher expected, actual, String which,
    {String? reason}) {
  var buffer = StringBuffer();
  buffer.writeln(_indent(_prettyPrint(expected), first: 'Expected: '));
  buffer.writeln(_indent(_prettyPrint(actual), first: '  Actual: '));
  if (which.isNotEmpty) buffer.writeln(_indent(which, first: '   Which: '));
  if (reason != null) buffer.writeln(reason);
  return buffer.toString();
}

/// Indent each line in [string] by [first.length] spaces.
///
/// [first] is used in place of the first line's indentation.
String _indent(String text, {required String first}) {
  final prefix = ' ' * first.length;
  var lines = text.split('\n');
  if (lines.length == 1) return '$first$text';

  var buffer = StringBuffer('$first${lines.first}\n');

  // Write out all but the first and last lines with [prefix].
  for (var line in lines.skip(1).take(lines.length - 2)) {
    buffer.writeln('$prefix$line');
  }
  buffer.write('$prefix${lines.last}');
  return buffer.toString();
}

/// Returns a pretty-printed representation of [value].
///
/// The matcher package doesn't expose its pretty-print function directly, but
/// we can use it through StringDescription.
String _prettyPrint(value) =>
    StringDescription().addDescriptionOf(value).toString();
