// GENERATED CODE - DO NOT MODIFY BY HAND

import '../src/common_modes.dart';
import '../src/mode.dart';

final erb = Mode(refs: {}, subLanguage: [
  "xml"
], contains: [
  Mode(className: "comment", begin: "<%#", end: "%>", contains: [
    PHRASAL_WORDS_MODE,
    Mode(
        className: "doctag",
        begin: "(?:TODO|FIXME|NOTE|BUG|XXX):",
        relevance: 0)
  ]),
  Mode(
      begin: "<%[%=-]?",
      end: "[%-]?%>",
      subLanguage: ["ruby"],
      excludeBegin: true,
      excludeEnd: true)
]);
