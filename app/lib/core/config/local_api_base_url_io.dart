import 'package:flutter/foundation.dart';

String defaultLocalApiBaseUrl() {
  if (defaultTargetPlatform == TargetPlatform.android) {
    return 'http://10.0.2.2:8000/api';
  }

  return 'http://localhost:8000/api';
}
