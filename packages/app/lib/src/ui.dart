import 'dart:ui';

import 'package:flutter/material.dart';

class AppColors {
  static const backgroundGrey = Color(0xfff2f2f2);
  static const separator = Color(0xffd1d1d1);

  static const iconLightBlue = Color(0xffaeb9c0);
  static const selection = Color(0xff2675bf);

  static const sideBarHeader = Color(0xffe1e6ec);

  static const lightText = Color(0xff808080);
}

ThemeData appTheme() {
  var theme = ThemeData.from(
    colorScheme: ColorScheme.fromSeed(seedColor: AppColors.selection),
    useMaterial3: true,
  );
  theme = theme.copyWith(
    textTheme: theme.textTheme.apply(displayColor: Colors.black),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(5),
        ),
      ),
    ),
  );

  return theme;
}
