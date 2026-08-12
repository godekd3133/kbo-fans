import 'package:flutter/foundation.dart';

import 'api_endpoints.dart';
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
  final bool enableLocalGameEventAlerts;

  AppConfig._({
    required this.environment,
    required this.apiBaseUrl,
    required this.hasApiBaseUrlOverride,
    required this.preferDirectScrape,
    required this.useBackendApi,
    required this.showDevConsole,
    required this.enableLocalGameEventAlerts,
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
    const enableLocalGameEventAlerts = bool.fromEnvironment(
      'ENABLE_LOCAL_GAME_EVENT_ALERTS',
      defaultValue: false,
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
      enableLocalGameEventAlerts: enableLocalGameEventAlerts,
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
        return developmentApiBaseUrl;
      case AppEnvironment.release:
        return productionApiBaseUrl;
    }
  }

  bool get isLocal => environment == AppEnvironment.local;
  bool get isDev => environment == AppEnvironment.dev;
  bool get isRelease => environment == AppEnvironment.release;
  bool get isProduction => environment == AppEnvironment.release;
  // Web previews are user-facing surfaces; keep diagnostics in the browser
  // console instead of floating over cards and controls. Native local/debug
  // builds can still opt in with SHOW_DEV_CONSOLE=true.
  bool get shouldShowDevConsole => !isRelease && !kIsWeb && showDevConsole;
  bool get shouldUseBackendApi => useBackendApi;
  bool get shouldUseDirectData => !useBackendApi;
  bool get shouldPreferLocalNativeData => shouldUseDirectData && !kIsWeb;
}
