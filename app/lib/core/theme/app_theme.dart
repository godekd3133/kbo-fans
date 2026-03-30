import 'package:flutter/material.dart';

class AppColors {
  static const background = Color(0xFF0F0F0F);
  static const card = Color(0xFF1A1A1A);
  static const cardSub = Color(0xFF252525);
  static const divider = Color(0xFF333333);
  static const textPrimary = Color(0xFFFFFFFF);
  static const textSecondary = Color(0xFFB0B0B0);
  static const textDisabled = Color(0xFF666666);
  static const live = Color(0xFFFF4444);
  static const positive = Color(0xFF00C853);
  static const accent = Color(0xFF2979FF);
  static const ballYellow = Color(0xFFFFD600);
}

class AppTheme {
  static ThemeData get dark => ThemeData(
        brightness: Brightness.dark,
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
            fontFamily: 'Pretendard',
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
          selectedLabelStyle: TextStyle(fontFamily: 'Pretendard', fontSize: 10),
          unselectedLabelStyle: TextStyle(fontFamily: 'Pretendard', fontSize: 10),
        ),
        cardTheme: CardThemeData(
          color: AppColors.card,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 0,
          margin: EdgeInsets.zero,
        ),
        dividerTheme: const DividerThemeData(
          color: AppColors.divider,
          thickness: 0.5,
        ),
        textTheme: const TextTheme(
          headlineLarge: TextStyle(fontFamily: 'Pretendard', fontSize: 28, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
          headlineMedium: TextStyle(fontFamily: 'Pretendard', fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
          titleLarge: TextStyle(fontFamily: 'Pretendard', fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
          titleMedium: TextStyle(fontFamily: 'Pretendard', fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
          bodyLarge: TextStyle(fontFamily: 'Pretendard', fontSize: 16, color: AppColors.textPrimary),
          bodyMedium: TextStyle(fontFamily: 'Pretendard', fontSize: 14, color: AppColors.textPrimary),
          bodySmall: TextStyle(fontFamily: 'Pretendard', fontSize: 12, color: AppColors.textSecondary),
          labelSmall: TextStyle(fontFamily: 'Pretendard', fontSize: 10, color: AppColors.textDisabled),
        ),
      );
}
