enum AppEnvironment { local, dev, release }

class AppConfig {
  static late final AppConfig _instance;
  static AppConfig get instance => _instance;

  final AppEnvironment environment;
  final String apiBaseUrl;
  final bool useMockData;

  AppConfig._({
    required this.environment,
    required this.apiBaseUrl,
    required this.useMockData,
  });

  /// `--dart-define=APP_ENV=local|dev|release` 로 빌드 시 환경 결정
  static void initialize() {
    const envString = String.fromEnvironment('APP_ENV', defaultValue: 'local');
    final env = AppEnvironment.values.firstWhere(
      (e) => e.name == envString,
      orElse: () => AppEnvironment.local,
    );

    _instance = AppConfig._(
      environment: env,
      apiBaseUrl: _baseUrlFor(env),
      useMockData: env == AppEnvironment.local,
    );
  }

  static String _baseUrlFor(AppEnvironment env) {
    switch (env) {
      case AppEnvironment.local:
        // LOCAL: 로컬 FastAPI 서버 (에뮬레이터에서는 10.0.2.2)
        return const String.fromEnvironment(
          'API_BASE_URL',
          defaultValue: 'http://localhost:8000/api',
        );
      case AppEnvironment.dev:
        // DEV: AWS dev 서버
        return const String.fromEnvironment(
          'API_BASE_URL',
          defaultValue: 'https://dev-api.kbofans.com/api',
        );
      case AppEnvironment.release:
        // RELEASE: AWS 프로덕션 서버
        return const String.fromEnvironment(
          'API_BASE_URL',
          defaultValue: 'https://api.kbofans.com/api',
        );
    }
  }

  bool get isLocal => environment == AppEnvironment.local;
  bool get isDev => environment == AppEnvironment.dev;
  bool get isRelease => environment == AppEnvironment.release;
  bool get isProduction => environment == AppEnvironment.release;
}
