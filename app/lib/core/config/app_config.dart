import 'package:flutter/foundation.dart';

import 'local_api_base_url_io.dart'
    if (dart.library.js_interop) 'local_api_base_url_web.dart';

enum AppEnvironment { local, dev, release }

class AppConfig {
  static late final AppConfig _instance;
  static AppConfig get instance => _instance;

  final AppEnvironment environment;
  final String apiBaseUrl;
  final bool hasApiBaseUrlOverride;
  final bool preferDirectScrape;
  final bool useBackendApi;
  final bool showDevConsole;

  AppConfig._({
    required this.environment,
    required this.apiBaseUrl,
    required this.hasApiBaseUrlOverride,
    required this.preferDirectScrape,
    required this.useBackendApi,
    required this.showDevConsole,
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
    const useBackendApiFlag = String.fromEnvironment(
      'USE_BACKEND_API',
      defaultValue: '',
    );
    const useBackendApiBool = bool.fromEnvironment(
      'USE_BACKEND_API',
      defaultValue: true,
    );
    const showDevConsoleFlag = String.fromEnvironment(
      'SHOW_DEV_CONSOLE',
      defaultValue: 'true',
    );
    final env = AppEnvironment.values.firstWhere(
      (e) => e.name == envString,
      orElse: () => AppEnvironment.local,
    );
    final preferDirectScrape = preferDirectScrapeFlag.isNotEmpty
        ? preferDirectScrapeFlag == 'true'
        : false;
    final useBackendApi = useBackendApiFlag.isEmpty
        ? true
        : useBackendApiBool || useBackendApiFlag == 'true';

    _instance = AppConfig._(
      environment: env,
      apiBaseUrl: _baseUrlFor(env, override: apiBaseUrlOverride),
      hasApiBaseUrlOverride: apiBaseUrlOverride.isNotEmpty,
      preferDirectScrape: preferDirectScrape,
      useBackendApi: useBackendApi,
      showDevConsole: showDevConsoleFlag != 'false',
    );
  }

  static String _baseUrlFor(AppEnvironment env, {required String override}) {
    if (override.isNotEmpty) {
      return override;
    }

    switch (env) {
      case AppEnvironment.local:
        return defaultLocalApiBaseUrl();
      case AppEnvironment.dev:
        return 'https://dev-api.kbofans.com/api';
      case AppEnvironment.release:
        return 'https://api.kbofans.com/api';
    }
  }

  bool get isLocal => environment == AppEnvironment.local;
  bool get isDev => environment == AppEnvironment.dev;
  bool get isRelease => environment == AppEnvironment.release;
  bool get isProduction => environment == AppEnvironment.release;
  bool get shouldShowDevConsole => !isRelease && showDevConsole;
  bool get shouldUseBackendApi => useBackendApi;
  bool get shouldUseDirectData => !useBackendApi;
  bool get shouldPreferLocalNativeData => shouldUseDirectData && !kIsWeb;
}
