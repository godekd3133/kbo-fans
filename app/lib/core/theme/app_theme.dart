import 'package:flutter/material.dart';

class AppColors {
  static const background = Color(0xFF0F0F0F);
  static const surface = Color(0xFF171717);
  static const card = Color(0xFF1D1D1D);
  static const cardSub = Color(0xFF292929);
  static const divider = Color(0xFF373737);
  static const textPrimary = Color(0xFFF7F9FC);
  static const textSecondary = Color(0xFFA6B0BD);
  static const textDisabled = Color(0xFF6E7784);
  static const live = Color(0xFFFF4444);
  static const positive = Color(0xFF18C67A);
  static const accent = Color(0xFF2979FF);
  static const ballYellow = Color(0xFFFFD600);
}

class AppTypography {
  static const primaryFontFamily = 'NanumSquareRound';
  static const fallbackFontFamilies = [
    'Pretendard',
    'Apple SD Gothic Neo',
    'Noto Sans KR',
  ];
}

class AppTheme {
  static ThemeData get dark => ThemeData(
    brightness: Brightness.dark,
    splashFactory: InkRipple.splashFactory,
    fontFamily: AppTypography.primaryFontFamily,
    fontFamilyFallback: AppTypography.fallbackFontFamilies,
    scaffoldBackgroundColor: AppColors.background,
    colorScheme: const ColorScheme.dark(
      surface: AppColors.background,
      primary: AppColors.live,
      secondary: AppColors.accent,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.background,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(
        fontFamily: AppTypography.primaryFontFamily,
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
      ),
      iconTheme: IconThemeData(color: AppColors.textPrimary),
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: AppColors.background,
      selectedItemColor: AppColors.textPrimary,
      unselectedItemColor: AppColors.textDisabled,
      type: BottomNavigationBarType.fixed,
      selectedLabelStyle: TextStyle(
        fontFamily: AppTypography.primaryFontFamily,
        fontSize: 10,
      ),
      unselectedLabelStyle: TextStyle(
        fontFamily: AppTypography.primaryFontFamily,
        fontSize: 10,
      ),
    ),
    cardTheme: CardThemeData(
      color: AppColors.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      elevation: 0,
      margin: EdgeInsets.zero,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.accent,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        textStyle: const TextStyle(
          fontFamily: AppTypography.primaryFontFamily,
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.textPrimary,
        side: const BorderSide(color: AppColors.divider),
        textStyle: const TextStyle(
          fontFamily: AppTypography.primaryFontFamily,
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.card,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.divider),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.divider),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.accent),
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: AppColors.divider,
      thickness: 0.5,
    ),
    textTheme: const TextTheme(
      headlineLarge: TextStyle(
        fontFamily: AppTypography.primaryFontFamily,
        fontSize: 28,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
      ),
      headlineMedium: TextStyle(
        fontFamily: AppTypography.primaryFontFamily,
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
      ),
      titleLarge: TextStyle(
        fontFamily: AppTypography.primaryFontFamily,
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
      ),
      titleMedium: TextStyle(
        fontFamily: AppTypography.primaryFontFamily,
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
      ),
      bodyLarge: TextStyle(
        fontFamily: AppTypography.primaryFontFamily,
        fontSize: 16,
        color: AppColors.textPrimary,
      ),
      bodyMedium: TextStyle(
        fontFamily: AppTypography.primaryFontFamily,
        fontSize: 14,
        color: AppColors.textPrimary,
      ),
      bodySmall: TextStyle(
        fontFamily: AppTypography.primaryFontFamily,
        fontSize: 12,
        color: AppColors.textSecondary,
      ),
      labelSmall: TextStyle(
        fontFamily: AppTypography.primaryFontFamily,
        fontSize: 10,
        color: AppColors.textDisabled,
      ),
    ),
  );
}
