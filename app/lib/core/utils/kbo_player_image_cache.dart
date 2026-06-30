import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

const kboPlayerImageHeaders = {
  'Referer': 'https://www.koreabaseball.com/',
  'User-Agent':
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36',
};

Future<void> precacheKboPlayerImageUrls(
  BuildContext context,
  Iterable<String?> imageUrls, {
  int limit = 12,
}) async {
  final urls = <String>{};
  for (final rawUrl in imageUrls) {
    final imageUrl = rawUrl?.trim() ?? '';
    if (imageUrl.isEmpty) {
      continue;
    }
    urls.add(imageUrl);
    if (urls.length >= limit) {
      break;
    }
  }

  await Future.wait(
    urls.map(
      (imageUrl) => precacheImage(
        CachedNetworkImageProvider(imageUrl, headers: kboPlayerImageHeaders),
        context,
      ).catchError((_) {}),
    ),
  );
}
