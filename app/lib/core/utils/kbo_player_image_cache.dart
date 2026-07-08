import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

const kboPlayerImageHeaders = {
  'Referer': 'https://www.koreabaseball.com/',
  'User-Agent':
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36',
};

const kboPlayerImageDefaultCacheSize = 192;

class KboPlayerImageCacheManager extends CacheManager with ImageCacheManager {
  static const key = 'kboPlayerImageCache';
  static final KboPlayerImageCacheManager _instance =
      KboPlayerImageCacheManager._();

  factory KboPlayerImageCacheManager() => _instance;

  KboPlayerImageCacheManager._()
    : super(
        Config(
          key,
          stalePeriod: const Duration(days: 90),
          maxNrOfCacheObjects: 900,
        ),
      );
}

final BaseCacheManager kboPlayerImageCacheManager =
    KboPlayerImageCacheManager();

int kboPlayerImageCacheSize(
  double logicalSize, {
  double devicePixelRatio = 3,
  int min = 96,
  int max = 720,
}) {
  final cacheSize = (logicalSize * devicePixelRatio).round();
  if (cacheSize < min) {
    return min;
  }
  if (cacheSize > max) {
    return max;
  }
  return cacheSize;
}

CachedNetworkImageProvider kboPlayerImageProvider(
  String imageUrl, {
  int? cacheSize,
}) {
  return CachedNetworkImageProvider(
    imageUrl,
    headers: kboPlayerImageHeaders,
    cacheManager: kboPlayerImageCacheManager,
    maxWidth: cacheSize ?? kboPlayerImageDefaultCacheSize,
    maxHeight: cacheSize ?? kboPlayerImageDefaultCacheSize,
  );
}

Future<void> precacheKboPlayerImageUrls(
  BuildContext context,
  Iterable<String?> imageUrls, {
  int? limit,
  int batchSize = 4,
  int cacheSize = kboPlayerImageDefaultCacheSize,
}) async {
  final urls = <String>[];
  final seen = <String>{};
  for (final rawUrl in imageUrls) {
    final imageUrl = rawUrl?.trim() ?? '';
    if (imageUrl.isEmpty || !seen.add(imageUrl)) {
      continue;
    }
    urls.add(imageUrl);
    if (limit != null && urls.length >= limit) {
      break;
    }
  }

  final effectiveBatchSize = batchSize < 1 ? 1 : batchSize;
  for (var index = 0; index < urls.length; index += effectiveBatchSize) {
    final batch = urls.skip(index).take(effectiveBatchSize);
    await Future.wait(
      batch.map(
        (imageUrl) =>
            _warmKboPlayerImageCache(context, imageUrl, cacheSize: cacheSize),
      ),
    );
    if (!context.mounted) {
      return;
    }
  }
}

Future<void> _warmKboPlayerImageCache(
  BuildContext context,
  String imageUrl, {
  required int cacheSize,
}) async {
  if (!context.mounted) {
    return;
  }
  try {
    await precacheImage(
      kboPlayerImageProvider(imageUrl, cacheSize: cacheSize),
      context,
    );
  } catch (_) {
    // Ignore per-player image failures so one missing KBO photo cannot block entry.
  }
}
