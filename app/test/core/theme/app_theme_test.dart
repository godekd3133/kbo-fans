import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kbo_fans/core/theme/app_theme.dart';
import 'package:kbo_fans/core/theme/theme_mode_controller.dart';

void main() {
  test('dark theme uses a non-shader splash factory', () {
    expect(AppTheme.dark.splashFactory, same(InkRipple.splashFactory));
  });

  test('light theme uses a non-shader splash factory', () {
    expect(AppTheme.light.splashFactory, same(InkRipple.splashFactory));
  });

  test('dark theme uses playful rounded app font with stable fallbacks', () {
    final theme = AppTheme.dark;

    expect(AppTypography.primaryFontFamily, 'Jua');
    expect(AppTypography.fallbackFontFamilies, contains('NanumSquareRound'));
    expect(AppTypography.fallbackFontFamilies, contains('Pretendard'));
    expect(theme.textTheme.bodyMedium?.fontFamily, 'Jua');
  });

  test('light and dark themes expose distinct app color tokens', () {
    final lightColors = AppTheme.light.extension<AppThemeColors>();
    final darkColors = AppTheme.dark.extension<AppThemeColors>();

    expect(lightColors, isNotNull);
    expect(darkColors, isNotNull);
    expect(lightColors!.background, isNot(darkColors!.background));
    expect(lightColors.textPrimary, isNot(darkColors.textPrimary));
    expect(AppTheme.light.brightness, Brightness.light);
    expect(AppTheme.dark.brightness, Brightness.dark);
  });

  test('legacy app colors can be synced to the active theme palette', () {
    AppColors.sync(AppTheme.lightColors);
    expect(AppColors.background, AppTheme.lightColors.background);
    expect(AppColors.textPrimary, AppTheme.lightColors.textPrimary);

    AppColors.sync(AppTheme.darkColors);
    expect(AppColors.background, AppTheme.darkColors.background);
    expect(AppColors.textPrimary, AppTheme.darkColors.textPrimary);
  });

  test('theme mode preference keeps dark as the no-storage default', () {
    expect(
      AppThemeModePreference.fromStorage(null),
      AppThemeModePreference.dark,
    );
    expect(
      AppThemeModePreference.fromStorage('system').themeMode,
      ThemeMode.system,
    );
    expect(
      AppThemeModePreference.fromStorage('light').themeMode,
      ThemeMode.light,
    );
    expect(
      AppThemeModePreference.fromStorage('dark').themeMode,
      ThemeMode.dark,
    );
  });
}
