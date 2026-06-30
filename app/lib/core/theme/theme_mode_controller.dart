import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppThemeModePreference {
  system('system'),
  light('light'),
  dark('dark');

  final String storageValue;

  const AppThemeModePreference(this.storageValue);

  ThemeMode get themeMode {
    return switch (this) {
      AppThemeModePreference.system => ThemeMode.system,
      AppThemeModePreference.light => ThemeMode.light,
      AppThemeModePreference.dark => ThemeMode.dark,
    };
  }

  String get label {
    return switch (this) {
      AppThemeModePreference.system => '시스템',
      AppThemeModePreference.light => '라이트',
      AppThemeModePreference.dark => '다크',
    };
  }

  String get description {
    return switch (this) {
      AppThemeModePreference.system => '휴대폰 설정을 따릅니다',
      AppThemeModePreference.light => '밝은 배경으로 봅니다',
      AppThemeModePreference.dark => '기존 어두운 화면입니다',
    };
  }

  IconData get icon {
    return switch (this) {
      AppThemeModePreference.system => Icons.settings_brightness_rounded,
      AppThemeModePreference.light => Icons.light_mode_rounded,
      AppThemeModePreference.dark => Icons.dark_mode_rounded,
    };
  }

  static AppThemeModePreference fromStorage(String? value) {
    for (final mode in AppThemeModePreference.values) {
      if (mode.storageValue == value) {
        return mode;
      }
    }
    return AppThemeModePreference.dark;
  }
}

class AppThemeModeNotifier extends Notifier<AppThemeModePreference> {
  static const prefsKey = 'appearance.theme_mode';

  @override
  AppThemeModePreference build() => AppThemeModePreference.dark;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    state = AppThemeModePreference.fromStorage(prefs.getString(prefsKey));
  }

  Future<void> setMode(AppThemeModePreference mode) async {
    if (state == mode) {
      return;
    }
    state = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(prefsKey, mode.storageValue);
  }
}

final appThemeModeProvider =
    NotifierProvider<AppThemeModeNotifier, AppThemeModePreference>(
      AppThemeModeNotifier.new,
    );
