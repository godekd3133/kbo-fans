import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

String? sanitizeAppRoute(String? route, {String? fallback = '/home'}) {
  final fallbackRoute = _validInternalRoute(fallback) ? fallback : null;
  if (route == null || route.trim().isEmpty) {
    return fallbackRoute;
  }

  final rawRoute = route.trim();
  final uri = Uri.tryParse(rawRoute);
  if (uri == null ||
      uri.hasScheme ||
      uri.host.isNotEmpty ||
      !rawRoute.startsWith('/') ||
      rawRoute.startsWith('//')) {
    return fallbackRoute;
  }

  final path = uri.path;
  if (path == '/' || path == '/boot' || path == '/onboarding') {
    return fallbackRoute ?? '/home';
  }
  if (!_validInternalRoute(path)) {
    return fallbackRoute;
  }
  return uri.toString();
}

extension AppRouteSanitizerContext on BuildContext {
  void pushAppRoute(String? route, {String? fallback = '/home'}) {
    final target = sanitizeAppRoute(route, fallback: fallback);
    if (target == null) {
      return;
    }
    push(target);
  }

  void goAppRoute(String? route, {String? fallback = '/home'}) {
    final target = sanitizeAppRoute(route, fallback: fallback);
    if (target == null) {
      return;
    }
    go(target);
  }
}

bool _validInternalRoute(String? route) {
  if (route == null || route.isEmpty) {
    return false;
  }
  final uri = Uri.tryParse(route);
  if (uri == null || uri.hasScheme || uri.host.isNotEmpty) {
    return false;
  }
  final path = uri.path;
  if (path == '/home' ||
      path == '/schedule' ||
      path == '/news' ||
      path == '/standings' ||
      path == '/records' ||
      path == '/settings' ||
      path == '/diagnostics' ||
      path == '/release-notes' ||
      path == '/patch-notes' ||
      path == '/notifications') {
    return true;
  }
  if (RegExp(r'^/game/[^/]+$').hasMatch(path)) {
    return true;
  }
  if (RegExp(r'^/records/team/[^/]+$').hasMatch(path)) {
    return true;
  }
  if (RegExp(r'^/records/player/[^/]+$').hasMatch(path)) {
    return true;
  }
  if (RegExp(r'^/records/leaderboard/[^/]+$').hasMatch(path)) {
    return true;
  }
  return false;
}
