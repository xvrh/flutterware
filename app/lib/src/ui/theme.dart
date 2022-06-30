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
  var base = ThemeData(
    useMaterial3: true,
    colorSchemeSeed: AppColors.primary,
  );

  var inputBorder = OutlineInputBorder(
    borderRadius: BorderRadius.circular(8),
    borderSide: BorderSide(
      color: Color(0xffe0e0e0),
    ),
  );
  base = base.copyWith(
    scaffoldBackgroundColor: AppColors.scaffoldBackground,
    tabBarTheme: base.tabBarTheme.copyWith(
      labelColor: AppColors.primary,
      indicatorSize: TabBarIndicatorSize.label,
      unselectedLabelColor: AppColors.foregroundSecondary,
      labelStyle:
          base.textTheme.titleMedium!.copyWith(fontWeight: FontWeight.w500),
      unselectedLabelStyle:
          base.textTheme.titleMedium!.copyWith(fontWeight: FontWeight.w500),
      indicator: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppColors.primary, width: 3),
        ),
      ),
    ),
    popupMenuTheme: base.popupMenuTheme.copyWith(
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Colors.black12),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        elevation: 0,
        primary: AppColors.primary,
        onPrimary: Colors.white,
      ),
    ),
    cardColor: Colors.white,
    cardTheme: base.cardTheme.copyWith(
      surfaceTintColor: Colors.white,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
      elevation: 2,
    ),
    inputDecorationTheme: base.inputDecorationTheme.copyWith(
      border: inputBorder,
      enabledBorder: inputBorder,
      focusedBorder: inputBorder.copyWith(
        borderSide: BorderSide(color: AppColors.primary, width: 2),
      ),
      filled: true,
      isDense: true,
      fillColor: Colors.white,
      hoverColor: Colors.white,
      hintStyle: const TextStyle(color: Colors.black38),
      contentPadding: EdgeInsets.symmetric(vertical: 13, horizontal: 10),
    ),
    dividerTheme: base.dividerTheme.copyWith(
      color: AppColors.primaryBorder,
      thickness: 1,
    ),
  );

  return base;
}
