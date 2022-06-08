String ellipsisCenter(String input,
    {required int maxLength, String ellipsis = '..'}) {
  if (ellipsis.length > maxLength) {
    throw Exception('Ellipsis is longer than max length');
  }
  if (input.length <= maxLength) return input;

  var takeLength = maxLength - ellipsis.length;

  var before = (takeLength / 2).ceil();
  var after = takeLength - before;

  return '${input.substring(0, before)}$ellipsis${input.substring(input.length - after)}';
}
