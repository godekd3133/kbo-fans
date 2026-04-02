import 'package:flutter/foundation.dart';

enum AppEnvironment { local, dev, release }

class AppConfig {
  static late final AppConfig _instance;
  static AppConfig get instance => _instance;

  final AppEnvironment environment;
  final String apiBaseUrl;
  final bool useMockData;
  final bool preferDirectScrape;

  AppConfig._({
    required this.environment,
    required this.apiBaseUrl,
    required this.useMockData,
    required this.preferDirectScrape,
  });

  /// `--dart-define=APP_ENV=local|dev|release` 로 빌드 시 환경 결정
  static void initialize() {
    const envString = String.fromEnvironment('APP_ENV', defaultValue: 'local');
    const preferDirectScrapeFlag = String.fromEnvironment(
      'PREFER_DIRECT_SCRAPE',
      defaultValue: '',
    );
    final env = AppEnvironment.values.firstWhere(
      (e) => e.name == envString,
      orElse: () => AppEnvironment.local,
    );
    final preferDirectScrape = preferDirectScrapeFlag.isNotEmpty
        ? preferDirectScrapeFlag == 'true'
        : (env == AppEnvironment.local && !kIsWeb);

    _instance = AppConfig._(
      environment: env,
      apiBaseUrl: _baseUrlFor(env),
      useMockData: false, // 모든 환경에서 실제 데이터 사용 (웹은 providers에서 CORS fallback)
      preferDirectScrape: preferDirectScrape,
    );
  }

  static String _baseUrlFor(AppEnvironment env) {
    const override = String.fromEnvironment('API_BASE_URL', defaultValue: '');
    if (override.isNotEmpty) {
      return override;
    }

    switch (env) {
      case AppEnvironment.local:
        // LOCAL:
        // - 웹은 localhost
        // - Android 에뮬레이터는 10.0.2.2
        // - iOS native 디버그는 실기기에서 localhost가 불가하므로 dev API를 기본 사용
        if (kIsWeb) {
          return 'http://localhost:8000/api';
        }
        if (defaultTargetPlatform == TargetPlatform.android) {
          return 'http://10.0.2.2:8000/api';
        }
        if (defaultTargetPlatform == TargetPlatform.iOS) {
          return 'https://dev-api.kbofans.com/api';
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
}
