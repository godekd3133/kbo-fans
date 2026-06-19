import 'package:flutter_test/flutter_test.dart';
import 'package:kbo_fans/core/router/app_route_sanitizer.dart';

void main() {
  test('keeps supported internal app routes with query parameters', () {
    expect(
      sanitizeAppRoute('/game/20260619SSLG0?tab=relay&focus=relay'),
      '/game/20260619SSLG0?tab=relay&focus=relay',
    );
    expect(
      sanitizeAppRoute('/records/player/52605?season=2026'),
      '/records/player/52605?season=2026',
    );
    expect(sanitizeAppRoute('/standings'), '/standings');
  });

  test('maps bootstrapping routes back to home', () {
    expect(sanitizeAppRoute('/'), '/home');
    expect(sanitizeAppRoute('/boot?redirect=/records'), '/home');
    expect(sanitizeAppRoute('/onboarding'), '/home');
    expect(sanitizeAppRoute('/notifications'), '/notifications');
  });

  test('falls back for unsupported or external routes', () {
    expect(sanitizeAppRoute('/unknown', fallback: '/news'), '/news');
    expect(
      sanitizeAppRoute('https://kbofans.com/news', fallback: '/news'),
      '/news',
    );
    expect(sanitizeAppRoute('//kbofans.com/news', fallback: '/news'), '/news');
    expect(sanitizeAppRoute('/game/', fallback: '/news'), '/news');
  });

  test('can reject unsupported launch routes without fallback', () {
    expect(sanitizeAppRoute('/unknown', fallback: null), isNull);
    expect(sanitizeAppRoute('records', fallback: null), isNull);
  });
}
