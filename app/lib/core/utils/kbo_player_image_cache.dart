import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

const kboPlayerImageHeaders = {
  'Referer': 'https://www.koreabaseball.com/',
  'User-Agent':
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36',
};

Future<void> precacheKboPlayerImageUrls(
  BuildContext context,
  Iterable<String?> imageUrls, {
  int? limit,
  int batchSize = 4,
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
      batch.map((imageUrl) => _warmKboPlayerImageCache(context, imageUrl)),
    );
    if (!context.mounted) {
      return;
    }
  }
}

Future<void> _warmKboPlayerImageCache(
  BuildContext context,
  String imageUrl,
) async {
  try {
    await DefaultCacheManager().downloadFile(
      imageUrl,
      authHeaders: kboPlayerImageHeaders,
    );
  } catch (_) {
    // Best-effort warm-up: rendering still gets its own CachedNetworkImage path.
  }
  if (!context.mounted) {
    return;
  }
  try {
    await precacheImage(
      CachedNetworkImageProvider(imageUrl, headers: kboPlayerImageHeaders),
      context,
    );
  } catch (_) {
    // Ignore per-player image failures so one missing KBO photo cannot block entry.
  }
}
