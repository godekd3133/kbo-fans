import 'package:flutter/foundation.dart';

enum AppEnvironment { local, dev, release }

class AppConfig {
  static late final AppConfig _instance;
  static AppConfig get instance => _instance;

  final AppEnvironment environment;
  final String apiBaseUrl;
  final bool hasApiBaseUrlOverride;
  final bool preferDirectScrape;

  AppConfig._({
    required this.environment,
    required this.apiBaseUrl,
    required this.hasApiBaseUrlOverride,
    required this.preferDirectScrape,
  });

  /// `--dart-define=APP_ENV=local|dev|release` 로 빌드 시 환경 결정
  static void initialize() {
    const envString = String.fromEnvironment('APP_ENV', defaultValue: 'local');
    const preferDirectScrapeFlag = String.fromEnvironment(
      'PREFER_DIRECT_SCRAPE',
      defaultValue: '',
    );
    const apiBaseUrlOverride = String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: '',
    );
    final env = AppEnvironment.values.firstWhere(
      (e) => e.name == envString,
      orElse: () => AppEnvironment.local,
    );
    final preferDirectScrape = preferDirectScrapeFlag.isNotEmpty
        ? preferDirectScrapeFlag == 'true'
        : false;

    _instance = AppConfig._(
      environment: env,
      apiBaseUrl: _baseUrlFor(env, override: apiBaseUrlOverride),
      hasApiBaseUrlOverride: apiBaseUrlOverride.isNotEmpty,
      preferDirectScrape: preferDirectScrape,
    );
  }

  static String _baseUrlFor(AppEnvironment env, {required String override}) {
    if (override.isNotEmpty) {
      return override;
    }

    switch (env) {
      case AppEnvironment.local:
        // LOCAL:
        // - 웹은 localhost
        // - Android 에뮬레이터는 10.0.2.2
        // - iOS Simulator는 localhost
        // - iOS/Android 실기기는 실행 스크립트에서 Mac LAN IP를 API_BASE_URL로 주입
        if (kIsWeb) {
          return 'http://localhost:8000/api';
        }
        if (defaultTargetPlatform == TargetPlatform.android) {
          return 'http://10.0.2.2:8000/api';
        }
        if (defaultTargetPlatform == TargetPlatform.iOS) {
          return 'http://localhost:8000/api';
        }
        return 'http://localhost:8000/api';
      case AppEnvironment.dev:
        // DEV: AWS dev 서버
        return 'https://dev-api.kbofans.com/api';
      case AppEnvironment.release:
        // RELEASE: AWS 프로덕션 서버
        return 'https://api.kbofans.com/api';
    }
  }

  bool get isLocal => environment == AppEnvironment.local;
  bool get isDev => environment == AppEnvironment.dev;
  bool get isRelease => environment == AppEnvironment.release;
  bool get isProduction => environment == AppEnvironment.release;
  bool get shouldPreferLocalNativeData =>
      isLocal && !kIsWeb && !hasApiBaseUrlOverride && preferDirectScrape;
}
