import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'colors.dart';

export 'colors.dart';

ThemeData? __theme;
ThemeData get appTheme {
  if (kDebugMode) {
    return _buildAppTheme();
  } else {
    return __theme ??= _buildAppTheme();
  }
}

ThemeData _buildAppTheme() {
  var base = ThemeData(useMaterial3: true, colorSchemeSeed: AppColors.primary);

  return base;

  base = base.copyWith(
    scaffoldBackgroundColor: AppColors.scaffoldBackground,
    inputDecorationTheme: base.inputDecorationTheme.copyWith(
      border: OutlineInputBorder(
        borderSide: BorderSide(
          color: Color(0xffe0e0e0),
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderSide: BorderSide(
          color: Color(0xffe0e0e0),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: BorderSide(color: AppColors.primary, width: 2),
      ),
      filled: true,
      isDense: true,
      fillColor: Colors.white,
      hoverColor: Colors.white,
      hintStyle: const TextStyle(color: Colors.black38),
      contentPadding: EdgeInsets.symmetric(vertical: 13, horizontal: 10),
    ),
    dialogTheme: base.dialogTheme.copyWith(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
      ),
    ),
    cardTheme: base.cardTheme.copyWith(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(7),
      ),
    ),
  );

  return base;
}

ThemeData get darkTheme {
  var theme = ThemeData(
    brightness: Brightness.dark,
    primaryColor: AppColors.primary,
  ).copyWith(
    listTileTheme: ListTileThemeData(
      //dense: true,
      contentPadding: EdgeInsets.symmetric(horizontal: 10),
      minLeadingWidth: 0,
    ),
  );

  return theme;
}
