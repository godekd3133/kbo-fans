import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kbo_fans/core/theme/app_theme.dart';

void main() {
  test('dark theme uses a non-shader splash factory', () {
    expect(AppTheme.dark.splashFactory, same(InkRipple.splashFactory));
  });

  test('dark theme uses rounded app font with Pretendard fallback', () {
    final theme = AppTheme.dark;

    expect(AppTypography.primaryFontFamily, 'NanumSquareRound');
    expect(AppTypography.fallbackFontFamilies, contains('Pretendard'));
    expect(theme.textTheme.bodyMedium?.fontFamily, 'NanumSquareRound');
  });
}
