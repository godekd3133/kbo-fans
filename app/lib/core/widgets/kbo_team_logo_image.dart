import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../constants/team_data.dart';
import '../theme/app_theme.dart';

const kboImageHeaders = {
  'Referer': 'https://www.koreabaseball.com/',
  'User-Agent':
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36',
};

const _darkLogoContrastPlateKey = ValueKey('kbo-team-logo-contrast-plate');
const _darkLogoContrastTeamIds = {'OB'};

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
  final bool useDarkLogoContrastPlate;

  const KboTeamLogoImage({
    super.key,
    required this.teamId,
    required this.fallback,
    required this.size,
    this.padding = 2,
    this.preferReferenceAsset = true,
    this.useDarkLogoContrastPlate = true,
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
    final showContrastPlate =
        useDarkLogoContrastPlate &&
        _needsDarkLogoContrastPlate(team?.id ?? teamId);
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (showContrastPlate)
            Positioned.fill(
              child: _DarkLogoContrastPlate(size: size, team: team),
            ),
          Positioned.fill(
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
          ),
        ],
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
      filterQuality: FilterQuality.high,
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

bool _needsDarkLogoContrastPlate(String? teamId) {
  final normalized = (teamId ?? '').trim().toUpperCase();
  return _darkLogoContrastTeamIds.contains(normalized);
}

class _DarkLogoContrastPlate extends StatelessWidget {
  final double size;
  final KboTeam? team;

  const _DarkLogoContrastPlate({required this.size, required this.team});

  @override
  Widget build(BuildContext context) {
    final teamColor = team?.primaryColor ?? AppColors.cardSub;
    final plateSize = size * (size < 36 ? 0.92 : 0.88);
    final borderWidth = size < 36 ? 0.8 : 1.0;
    return Center(
      child: Container(
        key: _darkLogoContrastPlateKey,
        width: plateSize,
        height: plateSize,
        decoration: BoxDecoration(
          color: AppColors.textPrimary.withValues(alpha: 0.9),
          shape: BoxShape.circle,
          border: Border.all(
            color: teamColor.withValues(alpha: 0.36),
            width: borderWidth,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.26),
              blurRadius: size * 0.16,
              offset: Offset(0, size * 0.05),
            ),
            BoxShadow(
              color: teamColor.withValues(alpha: 0.22),
              blurRadius: size * 0.14,
            ),
          ],
        ),
      ),
    );
  }
}
