// GENERATED CODE - DO NOT MODIFY BY HAND

import '../src/common_modes.dart';
import '../src/mode.dart';

final bnf = Mode(refs: {}, contains: [
  Mode(className: "attribute", begin: "<", end: ">"),
  Mode(
      begin: "::=",
      starts: Mode(end: "\$", contains: [
        Mode(begin: "<", end: ">"),
        C_LINE_COMMENT_MODE,
        C_BLOCK_COMMENT_MODE,
        APOS_STRING_MODE,
        QUOTE_STRING_MODE
      ]))
]);
