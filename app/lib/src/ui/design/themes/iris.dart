import 'package:flutter/widgets.dart';

import '../palette.dart';
import 'fw_theme.dart';

/// Iris — the default look, and the palette behind `defaultTokens`.
const irisPalette = FwPalette(
  accent: Color(0xFF5b5bd6),
  accentDark: Color(0xFF4a4ac4),
  accentSoft: Color(0xFFeeeefb),
  accentSoft2: Color(0xFFf5f5fd),
  bg: Color(0xFFffffff),
  panel: Color(0xFFf7f8fa),
  panel2: Color(0xFFfbfbfa),
  ink: Color(0xFF15181d),
  ink2: Color(0xFF3a3d43),
  mut: Color(0xFF6b7280),
  mut2: Color(0xFF9aa1ac),
  mut3: Color(0xFFc4c7cd),
  line: Color(0xFFe8eaee),
  line2: Color(0xFFf0f1f4),
  grn: Color(0xFF2f9e63),
  amber: Color(0xFFcf8a00),
  red: Color(0xFFd24b3e),
  warningText: Color(0xFF9a6700),
  primaryOnMenu: Color(0xFF669df6),
  menuBackground: Color(0xFF0b1d32),
  menuSecondaryBackground: Color(0xFF182a41),
  dividerDark: Color(0xFF243447),
  tabDivider: Color(0xFFc5cfdc),
  info: Color(0xFF4EABFB),
);

const irisDarkPalette = FwPalette(
  accent: Color(0xFF8B8BF0),
  accentDark: Color(0xFF6F6FE0),
  accentSoft: Color(0xFF1F2233),
  accentSoft2: Color(0xFF282C42),
  bg: Color(0xFF15171F),
  panel: Color(0xFF1C1F29),
  panel2: Color(0xFF222633),
  ink: Color(0xFFECEDF2),
  ink2: Color(0xFFCDCFD9),
  mut: Color(0xFF9A9DAD),
  mut2: Color(0xFF73768A),
  mut3: Color(0xFF565A6E),
  line: Color(0xFF2A2E3C),
  line2: Color(0xFF383D4F),
  grn: Color(0xFF6FD68A),
  amber: Color(0xFFE6B450),
  red: Color(0xFFF07171),
  warningText: Color(0xFFCB983B),
  primaryOnMenu: Color(0xFF9B9BF4),
  menuBackground: Color(0xFF191B24),
  menuSecondaryBackground: Color(0xFF1F2230),
  dividerDark: Color(0xFF2A2E3C),
  tabDivider: Color(0xFF383D4F),
  info: Color(0xFF8B8BF0),
);

final irisTheme = FwTheme.from(
  name: 'Iris',
  palette: irisPalette,
  dark: irisDarkPalette,
);
