import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutterware/plugins.dart';

import 'design/design.dart';

export 'design/design.dart';

ThemeData? __theme;
ThemeData get appTheme {
  if (kDebugMode) {
    return buildAppTheme(defaultTokens);
  } else {
    return __theme ??= buildAppTheme(defaultTokens);
  }
}

ThemeData? __darkTheme;

/// The dark build of the same theme. [FwPalette.brightness] is read from the
/// palette's background, so [buildAppTheme] produces dark Material chrome from
/// this without a second code path.
ThemeData get appDarkTheme {
  if (kDebugMode) {
    return buildAppTheme(darkTokens);
  } else {
    return __darkTheme ??= buildAppTheme(darkTokens);
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
      .apply(displayColor: palette.ink, bodyColor: palette.mut);

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
      foregroundColor: palette.mut,
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
      // Sized to the app's own controls, not to Material's default. At the
      // old `vertical: 13` a text field stood 42 tall next to a 33 picker and
      // a 32 button — on the New run page the three sit in one column, and
      // the field read as a different, heavier kind of control. The picker's
      // own padding is the reference, so a field and a picker are one family.
      contentPadding: const EdgeInsets.symmetric(
        vertical: FwSpacing.md,
        horizontal: FwSpacing.md,
      ),
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

/// Maps a plugin [Tone] to a palette colour. The single place tones become
/// pixels — everywhere else they stay data.
Color toneColor(FwPalette colors, Tone tone) => switch (tone) {
  Tone.neutral => colors.mut2,
  Tone.good => colors.grn,
  Tone.info => colors.info,
  Tone.warn => colors.amber,
  Tone.error => colors.red,
};
