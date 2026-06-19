import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../constants/team_data.dart';
import '../theme/app_theme.dart';

const kboImageHeaders = {
  'Referer': 'https://www.koreabaseball.com/',
  'User-Agent':
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36',
};

String? kboReferenceTeamLogoAsset(String? teamId) {
  final normalized = (teamId ?? '').trim().toUpperCase();
  return switch (normalized) {
    'LG' ||
    'KT' ||
    'SK' ||
    'SS' ||
    'NC' ||
    'HH' ||
    'LT' ||
    'HT' ||
    'OB' ||
    'WO' => 'assets/visuals/reference_team_logos/$normalized.png',
    _ => null,
  };
}

class KboTeamLogoImage extends StatelessWidget {
  final String? teamId;
  final String fallback;
  final double size;
  final double padding;
  final bool preferReferenceAsset;

  const KboTeamLogoImage({
    super.key,
    required this.teamId,
    required this.fallback,
    required this.size,
    this.padding = 2,
    this.preferReferenceAsset = true,
  });

  @override
  Widget build(BuildContext context) {
    final team = KboTeams.resolve(
      id: teamId,
      name: fallback,
      shortName: fallback,
    );
    final referenceAsset = preferReferenceAsset
        ? kboReferenceTeamLogoAsset(team?.id ?? teamId)
        : null;
    return SizedBox(
      width: size,
      height: size,
      child: Padding(
        padding: EdgeInsets.all(padding),
        child: referenceAsset == null
            ? _networkLogo(team)
            : Image.asset(
                referenceAsset,
                fit: BoxFit.contain,
                width: double.infinity,
                height: double.infinity,
                filterQuality: FilterQuality.high,
                errorBuilder: (_, _, _) => _networkLogo(team),
              ),
      ),
    );
  }

  Widget _networkLogo(KboTeam? team) {
    final imageUrl = team?.logoUrl ?? '';
    if (imageUrl.isEmpty) {
      return _fallbackAvatar(team);
    }
    return CachedNetworkImage(
      imageUrl: imageUrl,
      httpHeaders: kboImageHeaders,
      width: double.infinity,
      height: double.infinity,
      fit: BoxFit.contain,
      memCacheWidth: (size * 4).round(),
      memCacheHeight: (size * 4).round(),
      placeholder: (_, _) => _fallbackAvatar(team),
      errorWidget: (_, _, _) => _fallbackAvatar(team),
    );
  }

  Widget _fallbackAvatar(KboTeam? team) {
    final label = fallback.trim().isEmpty
        ? '?'
        : fallback.trim().substring(0, 1);
    return Container(
      decoration: BoxDecoration(
        color: (team?.primaryColor ?? AppColors.cardSub).withValues(
          alpha: 0.18,
        ),
        borderRadius: BorderRadius.circular(size * 0.22),
        border: Border.all(color: AppColors.divider),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: TextStyle(
          fontSize: size * 0.34,
          fontWeight: FontWeight.w900,
          color: AppColors.textPrimary,
        ),
      ),
    );
  }
}
