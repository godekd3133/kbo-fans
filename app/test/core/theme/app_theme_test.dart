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

  test('high contrast themes expose their own distinct color palettes', () {
    final lightColors = AppTheme.light.extension<AppThemeColors>();
    final darkColors = AppTheme.dark.extension<AppThemeColors>();
    final highContrastLightColors = AppTheme.highContrastLight
        .extension<AppThemeColors>();
    final highContrastDarkColors = AppTheme.highContrastDark
        .extension<AppThemeColors>();

    expect(highContrastLightColors, same(AppTheme.highContrastLightColors));
    expect(highContrastDarkColors, same(AppTheme.highContrastDarkColors));
    expect(highContrastLightColors, isNot(same(lightColors)));
    expect(highContrastDarkColors, isNot(same(darkColors)));
    expect(highContrastLightColors!.background, isNot(lightColors!.background));
    expect(
      highContrastLightColors.textSecondary,
      isNot(lightColors.textSecondary),
    );
    expect(highContrastDarkColors!.background, isNot(darkColors!.background));
    expect(
      highContrastDarkColors.textSecondary,
      isNot(darkColors.textSecondary),
    );
    expect(AppTheme.highContrastLight.brightness, Brightness.light);
    expect(AppTheme.highContrastDark.brightness, Brightness.dark);
  });

  test(
    'high contrast readable text roles meet WCAG AA on every app surface',
    () {
      final palettes = <String, AppThemeColors>{
        'high contrast light': AppTheme.highContrastLightColors,
        'high contrast dark': AppTheme.highContrastDarkColors,
      };

      for (final paletteEntry in palettes.entries) {
        final colors = paletteEntry.value;
        final textRoles = <String, Color>{
          'primary': colors.textPrimary,
          'secondary': colors.textSecondary,
          'supporting': colors.textSupporting,
          'disabled': colors.textDisabled,
        };
        final surfaces = <String, Color>{
          'background': colors.background,
          'surface': colors.surface,
          'card': colors.card,
          'cardSub': colors.cardSub,
        };

        for (final textEntry in textRoles.entries) {
          for (final surfaceEntry in surfaces.entries) {
            expect(
              _contrastRatio(textEntry.value, surfaceEntry.value),
              greaterThanOrEqualTo(4.5),
              reason:
                  '${paletteEntry.key} ${textEntry.key} text must remain '
                  'readable on ${surfaceEntry.key}',
            );
          }
        }
      }
    },
  );

  test('default theme supporting text meets WCAG AA on every app surface', () {
    final palettes = <String, AppThemeColors>{
      'light': AppTheme.lightColors,
      'dark': AppTheme.darkColors,
    };

    for (final paletteEntry in palettes.entries) {
      final colors = paletteEntry.value;
      final surfaces = <String, Color>{
        'background': colors.background,
        'surface': colors.surface,
        'card': colors.card,
        'cardSub': colors.cardSub,
      };

      for (final surfaceEntry in surfaces.entries) {
        expect(
          _contrastRatio(colors.textSupporting, surfaceEntry.value),
          greaterThanOrEqualTo(4.5),
          reason:
              '${paletteEntry.key} supporting text must remain readable on '
              '${surfaceEntry.key}',
        );
      }
    }
  });

  test('high contrast dark accent meets AA on every dark app surface', () {
    final colors = AppTheme.highContrastDarkColors;
    final surfaces = <String, Color>{
      'background': colors.background,
      'surface': colors.surface,
      'card': colors.card,
      'cardSub': colors.cardSub,
    };

    for (final surface in surfaces.entries) {
      expect(
        _contrastRatio(colors.accent, surface.value),
        greaterThanOrEqualTo(4.5),
        reason: 'selected tabs and controls must be readable on ${surface.key}',
      );
    }
  });

  test('legacy app colors can be synced to the active theme palette', () {
    AppColors.sync(AppTheme.lightColors);
    expect(AppColors.background, AppTheme.lightColors.background);
    expect(AppColors.textPrimary, AppTheme.lightColors.textPrimary);
    expect(AppColors.textSupporting, AppTheme.lightColors.textSupporting);

    AppColors.sync(AppTheme.darkColors);
    expect(AppColors.background, AppTheme.darkColors.background);
    expect(AppColors.textPrimary, AppTheme.darkColors.textPrimary);
    expect(AppColors.textSupporting, AppTheme.darkColors.textSupporting);
  });

  test('readable accent lifts black team color on dark backgrounds', () {
    final accent = AppTheme.darkColors.readableAccent(Colors.black);

    expect(accent, isNot(Colors.black));
    expect(
      _contrastRatio(accent, AppTheme.darkColors.background),
      greaterThanOrEqualTo(4.5),
    );
  });

  test('foreground helper chooses readable text over colored fills', () {
    final darkFillForeground = AppTheme.darkColors.readableForegroundOn(
      Colors.black,
    );
    final orangeFillForeground = AppTheme.lightColors.readableForegroundOn(
      const Color(0xFFFF6600),
    );

    expect(
      _contrastRatio(darkFillForeground, Colors.black),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      _contrastRatio(orangeFillForeground, const Color(0xFFFF6600)),
      greaterThanOrEqualTo(4.5),
    );
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

double _contrastRatio(Color foreground, Color background) {
  final foregroundLuminance = foreground.computeLuminance();
  final backgroundLuminance = background.computeLuminance();
  final lighter = foregroundLuminance > backgroundLuminance
      ? foregroundLuminance
      : backgroundLuminance;
  final darker = foregroundLuminance > backgroundLuminance
      ? backgroundLuminance
      : foregroundLuminance;
  return (lighter + 0.05) / (darker + 0.05);
}
