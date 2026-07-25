import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'design/design.dart';

// Re-exported so screens not yet migrated to tokens keep compiling. New code
// should read `context.colors` / `context.type` instead of `AppColors`.
export 'colors.dart';
export 'design/design.dart';

ThemeData? __theme;
ThemeData get appTheme {
  if (kDebugMode) {
    return buildAppTheme(defaultTokens);
  } else {
    return __theme ??= buildAppTheme(defaultTokens);
  }
}

/// Builds the app [ThemeData] for a given token set and attaches [tokens] as a
/// [ThemeExtension] so widgets can read it via `context.colors` / `context.type`.
/// Material-rendered chrome (inputs, cards, dialogs) is driven by the tokens too
/// — surfaces from the palette, corners from the radii — so it tracks the theme.
ThemeData buildAppTheme(FwTokens tokens) {
  var palette = tokens.palette;
  var type = tokens.typography;
  var radii = tokens.radii;

  var base = ThemeData(useMaterial3: true, colorScheme: palette.colorScheme);

  var textTheme = type.spec
      .applyFontTheme(base.textTheme)
      .apply(displayColor: palette.textSteal, bodyColor: palette.textGrey);

  var inputBorder = OutlineInputBorder(
    borderRadius: BorderRadius.circular(radii.radius),
    borderSide: BorderSide(color: palette.line),
  );

  return base.copyWith(
    primaryColor: palette.primary,
    extensions: [tokens],
    textTheme: textTheme.copyWith(
      displayLarge: textTheme.displayLarge!.copyWith(
        fontSize: type.sizeDisplayLarge,
      ),
      displayMedium: textTheme.displayMedium!.copyWith(
        fontSize: type.sizeDisplayMedium,
      ),
      displaySmall: textTheme.displaySmall!.copyWith(
        fontSize: type.sizeDisplaySmall,
      ),
      headlineLarge: textTheme.headlineLarge!.copyWith(
        fontWeight: type.spec.heading,
      ),
      headlineMedium: textTheme.headlineMedium!.copyWith(
        fontSize: type.sizeHeadlineMedium,
        fontWeight: type.spec.heading,
      ),
      headlineSmall: textTheme.headlineSmall!.copyWith(
        fontSize: type.sizeHeadlineSmall,
        fontWeight: type.spec.heading,
      ),
      titleLarge: textTheme.titleLarge!.copyWith(fontSize: type.sizeTitleLarge),
    ),
    scaffoldBackgroundColor: palette.scaffoldBackground,
    appBarTheme: base.appBarTheme.copyWith(
      backgroundColor: palette.scaffoldBackground,
      foregroundColor: palette.textGrey,
      elevation: 0,
    ),
    tabBarTheme: base.tabBarTheme.copyWith(
      labelColor: palette.primary,
      unselectedLabelColor: palette.mut,
      indicatorSize: TabBarIndicatorSize.label,
      labelStyle: type.bodyStrong,
      unselectedLabelStyle: type.bodyStrong,
      indicator: BoxDecoration(
        border: Border(bottom: BorderSide(color: palette.primary, width: 3)),
      ),
    ),
    popupMenuTheme: base.popupMenuTheme.copyWith(
      elevation: 3,
      color: palette.bg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radii.radius),
        side: BorderSide(color: palette.line),
      ),
      textStyle: type.body,
    ),
    inputDecorationTheme: base.inputDecorationTheme.copyWith(
      border: inputBorder,
      enabledBorder: inputBorder,
      focusedBorder: inputBorder.copyWith(
        borderSide: BorderSide(color: palette.primary, width: 2),
      ),
      filled: true,
      isDense: true,
      fillColor: palette.bg,
      hoverColor: palette.bg,
      hintStyle: TextStyle(color: palette.mut2),
      contentPadding: const EdgeInsets.symmetric(vertical: 13, horizontal: 10),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        foregroundColor: palette.onPrimary,
        backgroundColor: palette.primary,
        elevation: 0,
        minimumSize: const Size(10, 42),
        textStyle: type.button,
      ),
    ),
    cardColor: palette.bg,
    cardTheme: base.cardTheme.copyWith(
      surfaceTintColor: palette.bg,
      color: palette.bg,
      elevation: 2,
      margin: const EdgeInsets.symmetric(vertical: 5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radii.radius),
      ),
    ),
    dialogTheme: base.dialogTheme.copyWith(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radii.radiusLarge),
      ),
    ),
    dataTableTheme: base.dataTableTheme.copyWith(
      headingRowColor: WidgetStateProperty.all(palette.tableHeader),
      headingTextStyle: type.micro.copyWith(color: palette.mut),
    ),
    dividerTheme: base.dividerTheme.copyWith(color: palette.line, thickness: 1),
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 400),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: palette.ink,
        borderRadius: BorderRadius.circular(radii.radiusSmall),
      ),
      textStyle: type.caption.copyWith(color: palette.bg),
    ),
  );
}
