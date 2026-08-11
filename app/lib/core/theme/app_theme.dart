import 'package:flutter/material.dart';

@immutable
class AppThemeColors extends ThemeExtension<AppThemeColors> {
  final Color background;
  final Color surface;
  final Color card;
  final Color cardSub;
  final Color divider;
  final Color textPrimary;
  final Color textSecondary;
  final Color textSupporting;
  final Color textDisabled;
  final Color live;
  final Color positive;
  final Color accent;
  final Color ballYellow;
  final Color navShadow;

  const AppThemeColors({
    required this.background,
    required this.surface,
    required this.card,
    required this.cardSub,
    required this.divider,
    required this.textPrimary,
    required this.textSecondary,
    required this.textSupporting,
    required this.textDisabled,
    required this.live,
    required this.positive,
    required this.accent,
    required this.ballYellow,
    required this.navShadow,
  });

  @override
  AppThemeColors copyWith({
    Color? background,
    Color? surface,
    Color? card,
    Color? cardSub,
    Color? divider,
    Color? textPrimary,
    Color? textSecondary,
    Color? textSupporting,
    Color? textDisabled,
    Color? live,
    Color? positive,
    Color? accent,
    Color? ballYellow,
    Color? navShadow,
  }) {
    return AppThemeColors(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      card: card ?? this.card,
      cardSub: cardSub ?? this.cardSub,
      divider: divider ?? this.divider,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textSupporting: textSupporting ?? this.textSupporting,
      textDisabled: textDisabled ?? this.textDisabled,
      live: live ?? this.live,
      positive: positive ?? this.positive,
      accent: accent ?? this.accent,
      ballYellow: ballYellow ?? this.ballYellow,
      navShadow: navShadow ?? this.navShadow,
    );
  }

  @override
  AppThemeColors lerp(ThemeExtension<AppThemeColors>? other, double t) {
    if (other is! AppThemeColors) {
      return this;
    }
    return AppThemeColors(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      card: Color.lerp(card, other.card, t)!,
      cardSub: Color.lerp(cardSub, other.cardSub, t)!,
      divider: Color.lerp(divider, other.divider, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textSupporting: Color.lerp(textSupporting, other.textSupporting, t)!,
      textDisabled: Color.lerp(textDisabled, other.textDisabled, t)!,
      live: Color.lerp(live, other.live, t)!,
      positive: Color.lerp(positive, other.positive, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      ballYellow: Color.lerp(ballYellow, other.ballYellow, t)!,
      navShadow: Color.lerp(navShadow, other.navShadow, t)!,
    );
  }

  Color readableAccent(Color color, {double minContrast = 4.5}) {
    if (_contrastRatio(color, background) >= minContrast) {
      return color;
    }

    final target = background.computeLuminance() > 0.5
        ? Colors.black
        : Colors.white;
    for (final amount in const [0.28, 0.42, 0.56, 0.7, 0.84]) {
      final candidate = Color.lerp(color, target, amount)!;
      if (_contrastRatio(candidate, background) >= minContrast) {
        return candidate;
      }
    }

    if (_contrastRatio(accent, background) >= minContrast) {
      return accent;
    }
    return target;
  }

  Color readableForegroundOn(Color fill, {double minContrast = 4.5}) {
    final candidates = [textPrimary, background, Colors.white, Colors.black];
    var best = candidates.first;
    var bestContrast = _contrastRatio(best, fill);
    for (final candidate in candidates.skip(1)) {
      final contrast = _contrastRatio(candidate, fill);
      if (contrast > bestContrast) {
        best = candidate;
        bestContrast = contrast;
      }
    }
    return best;
  }
}

double _contrastRatio(Color first, Color second) {
  final firstLuminance = first.computeLuminance();
  final secondLuminance = second.computeLuminance();
  final lighter = firstLuminance > secondLuminance
      ? firstLuminance
      : secondLuminance;
  final darker = firstLuminance > secondLuminance
      ? secondLuminance
      : firstLuminance;
  return (lighter + 0.05) / (darker + 0.05);
}

class AppColors {
  static const _background = Color(0xFF0F0F0F);
  static const _surface = Color(0xFF171717);
  static const _card = Color(0xFF1D1D1D);
  static const _cardSub = Color(0xFF292929);
  static const _divider = Color(0xFF373737);
  static const _textPrimary = Color(0xFFF7F9FC);
  static const _textSecondary = Color(0xFFA6B0BD);
  static const _textDisabled = Color(0xFF6E7784);
  static const _live = Color(0xFFFF4444);
  static const _positive = Color(0xFF18C67A);
  static const _accent = Color(0xFF2979FF);
  static const _ballYellow = Color(0xFFFFD600);

  static AppThemeColors _active = AppTheme.darkColors;

  static void sync(AppThemeColors colors) {
    _active = colors;
  }

  static Color get background => _active.background;
  static Color get surface => _active.surface;
  static Color get card => _active.card;
  static Color get cardSub => _active.cardSub;
  static Color get divider => _active.divider;
  static Color get textPrimary => _active.textPrimary;
  static Color get textSecondary => _active.textSecondary;
  static Color get textSupporting => _active.textSupporting;
  static Color get textDisabled => _active.textDisabled;
  static Color get live => _active.live;
  static Color get positive => _active.positive;
  static Color get accent => _active.accent;
  static Color get ballYellow => _active.ballYellow;
}

class AppTypography {
  static const primaryFontFamily = 'Jua';
  static const fallbackFontFamilies = [
    'NanumSquareRound',
    'Pretendard',
    'Apple SD Gothic Neo',
    'Noto Sans KR',
  ];
}

class AppTheme {
  static const darkColors = AppThemeColors(
    background: AppColors._background,
    surface: AppColors._surface,
    card: AppColors._card,
    cardSub: AppColors._cardSub,
    divider: AppColors._divider,
    textPrimary: AppColors._textPrimary,
    textSecondary: AppColors._textSecondary,
    textSupporting: AppColors._textSecondary,
    textDisabled: AppColors._textDisabled,
    live: AppColors._live,
    positive: AppColors._positive,
    accent: AppColors._accent,
    ballYellow: AppColors._ballYellow,
    navShadow: Color(0x5C000000),
  );

  static const lightColors = AppThemeColors(
    background: Color(0xFFF4F7FB),
    surface: Color(0xFFFFFFFF),
    card: Color(0xFFFFFFFF),
    cardSub: Color(0xFFEAF0F7),
    divider: Color(0xFFD9E2EC),
    textPrimary: Color(0xFF101828),
    textSecondary: Color(0xFF526173),
    textSupporting: Color(0xFF526173),
    textDisabled: Color(0xFF8A96A8),
    live: Color(0xFFE53935),
    positive: Color(0xFF008A56),
    accent: Color(0xFF0B63CE),
    ballYellow: Color(0xFFC78900),
    navShadow: Color(0x240F172A),
  );

  static const highContrastDarkColors = AppThemeColors(
    background: Color(0xFF000000),
    surface: Color(0xFF080808),
    card: Color(0xFF101010),
    cardSub: Color(0xFF1A1A1A),
    divider: Color(0xFF8A8A8A),
    textPrimary: Color(0xFFFFFFFF),
    textSecondary: Color(0xFFE6E6E6),
    textSupporting: Color(0xFFE6E6E6),
    textDisabled: Color(0xFFB8B8B8),
    live: Color(0xFFFF6B6B),
    positive: Color(0xFF4ADE80),
    accent: Color(0xFF338DFF),
    ballYellow: Color(0xFFFFE45E),
    navShadow: Color(0xCC000000),
  );

  static const highContrastLightColors = AppThemeColors(
    background: Color(0xFFFFFFFF),
    surface: Color(0xFFFFFFFF),
    card: Color(0xFFF7F7F7),
    cardSub: Color(0xFFE8E8E8),
    divider: Color(0xFF5A5A5A),
    textPrimary: Color(0xFF000000),
    textSecondary: Color(0xFF303030),
    textSupporting: Color(0xFF303030),
    textDisabled: Color(0xFF555555),
    live: Color(0xFF9F1D17),
    positive: Color(0xFF005B35),
    accent: Color(0xFF003D80),
    ballYellow: Color(0xFF6B4B00),
    navShadow: Color(0x66000000),
  );

  static AppThemeColors colorsOf(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<AppThemeColors>() ??
        (theme.brightness == Brightness.light ? lightColors : darkColors);
  }

  static ThemeData get dark =>
      _buildTheme(brightness: Brightness.dark, colors: darkColors);

  static ThemeData get light =>
      _buildTheme(brightness: Brightness.light, colors: lightColors);

  static ThemeData get highContrastDark =>
      _buildTheme(brightness: Brightness.dark, colors: highContrastDarkColors);

  static ThemeData get highContrastLight => _buildTheme(
    brightness: Brightness.light,
    colors: highContrastLightColors,
  );

  static ThemeData _buildTheme({
    required Brightness brightness,
    required AppThemeColors colors,
  }) {
    final isDark = brightness == Brightness.dark;
    final buttonForeground = isDark ? colors.textPrimary : Colors.white;
    final scheme =
        ColorScheme.fromSeed(
          seedColor: colors.accent,
          brightness: brightness,
        ).copyWith(
          primary: colors.live,
          secondary: colors.accent,
          surface: colors.background,
          onSurface: colors.textPrimary,
          error: colors.live,
        );

    return ThemeData(
      brightness: brightness,
      useMaterial3: true,
      splashFactory: InkRipple.splashFactory,
      fontFamily: AppTypography.primaryFontFamily,
      fontFamilyFallback: AppTypography.fallbackFontFamilies,
      scaffoldBackgroundColor: colors.background,
      colorScheme: scheme,
      extensions: <ThemeExtension<dynamic>>[colors],
      appBarTheme: AppBarTheme(
        backgroundColor: colors.background,
        foregroundColor: colors.textPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontFamily: AppTypography.primaryFontFamily,
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: colors.textPrimary,
        ),
        iconTheme: IconThemeData(color: colors.textPrimary),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: colors.background,
        selectedItemColor: colors.live,
        unselectedItemColor: colors.textSecondary,
        type: BottomNavigationBarType.fixed,
        selectedLabelStyle: const TextStyle(
          fontFamily: AppTypography.primaryFontFamily,
          fontSize: 10,
        ),
        unselectedLabelStyle: const TextStyle(
          fontFamily: AppTypography.primaryFontFamily,
          fontSize: 10,
        ),
      ),
      cardTheme: CardThemeData(
        color: colors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        elevation: 0,
        margin: EdgeInsets.zero,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: colors.accent,
          foregroundColor: buttonForeground,
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
          foregroundColor: colors.textPrimary,
          side: BorderSide(color: colors.divider),
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
        fillColor: colors.card,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: colors.divider),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: colors.divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: colors.accent),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colors.card,
        surfaceTintColor: Colors.transparent,
      ),
      dividerTheme: DividerThemeData(color: colors.divider, thickness: 0.5),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return colors.accent;
          }
          return colors.textDisabled;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return colors.accent.withValues(alpha: 0.34);
          }
          return colors.cardSub;
        }),
      ),
      textTheme: TextTheme(
        headlineLarge: TextStyle(
          fontFamily: AppTypography.primaryFontFamily,
          fontSize: 28,
          fontWeight: FontWeight.w700,
          color: colors.textPrimary,
        ),
        headlineMedium: TextStyle(
          fontFamily: AppTypography.primaryFontFamily,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: colors.textPrimary,
        ),
        titleLarge: TextStyle(
          fontFamily: AppTypography.primaryFontFamily,
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: colors.textPrimary,
        ),
        titleMedium: TextStyle(
          fontFamily: AppTypography.primaryFontFamily,
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: colors.textPrimary,
        ),
        bodyLarge: TextStyle(
          fontFamily: AppTypography.primaryFontFamily,
          fontSize: 16,
          color: colors.textPrimary,
        ),
        bodyMedium: TextStyle(
          fontFamily: AppTypography.primaryFontFamily,
          fontSize: 14,
          color: colors.textPrimary,
        ),
        bodySmall: TextStyle(
          fontFamily: AppTypography.primaryFontFamily,
          fontSize: 12,
          color: colors.textSecondary,
        ),
        labelSmall: TextStyle(
          fontFamily: AppTypography.primaryFontFamily,
          fontSize: 10,
          color: colors.textDisabled,
        ),
      ),
    );
  }
}
