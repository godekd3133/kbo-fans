import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/team_data.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/game.dart';
import '../../../data/models/boxscore.dart';
import '../../../data/models/player.dart';
import '../../../data/models/relay.dart';
import '../../../data/providers.dart';

const _kboImageHeaders = {
  'Referer': 'https://www.koreabaseball.com/',
  'User-Agent':
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36',
};

class LineupTab extends ConsumerWidget {
  final String gameId;
  final GameStatus gameStatus;
  final String awayName;
  final String homeName;
  final String awayTeamId;
  final String homeTeamId;
  final Future<void> Function()? onRefresh;

  const LineupTab({
    super.key,
    required this.gameId,
    required this.gameStatus,
    this.awayName = '원정',
    this.homeName = '홈',
    this.awayTeamId = '',
    this.homeTeamId = '',
    this.onRefresh,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (gameStatus == GameStatus.scheduled) {
      return _buildUnavailableState('경기 시작 후 라인업이 공개됩니다');
    }
    if (gameStatus == GameStatus.cancelled) {
      return _buildUnavailableState('취소된 경기는 라인업이 없습니다');
    }

    final gameLineupAsync = ref.watch(gameLineupProvider(gameId));
    final awayBattersAsync = ref.watch(battersProvider('$gameId|true'));
    final homeBattersAsync = ref.watch(battersProvider('$gameId|false'));
    final awayPitchersAsync = ref.watch(pitchersProvider('$gameId|true'));
    final homePitchersAsync = ref.watch(pitchersProvider('$gameId|false'));
    final relayAsync = ref.watch(relayDataProvider(gameId));
    final season = DateTime.now().year;
    final awayPlayersAsync = awayTeamId.isEmpty
        ? const AsyncValue<List<PlayerProfile>>.data(<PlayerProfile>[])
        : ref.watch(teamPlayersProvider('$awayTeamId|$season'));
    final homePlayersAsync = homeTeamId.isEmpty
        ? const AsyncValue<List<PlayerProfile>>.data(<PlayerProfile>[])
        : ref.watch(teamPlayersProvider('$homeTeamId|$season'));
    final allImageMap =
        ref.watch(allPlayerImageMapProvider(season)).asData?.value ??
        const <String, String>{};

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth > 760
            ? 720.0
            : constraints.maxWidth;

        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: RefreshIndicator(
              onRefresh: onRefresh ?? () async {},
              color: AppColors.live,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                child: gameLineupAsync.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.all(28),
                    child: Center(
                      child: CircularProgressIndicator(color: AppColors.live),
                    ),
                  ),
                  error: (error, _) => Text(
                    '라인업 데이터 로딩 실패: $error',
                    style: const TextStyle(color: AppColors.textDisabled),
                  ),
                  data: (gameLineup) {
                    final awayPitchers =
                        awayPitchersAsync.asData?.value.cast<PitcherRecord>() ??
                        const <PitcherRecord>[];
                    final homePitchers =
                        homePitchersAsync.asData?.value.cast<PitcherRecord>() ??
                        const <PitcherRecord>[];
                    final awayBatters =
                        awayBattersAsync.asData?.value.cast<BatterRecord>() ??
                        const <BatterRecord>[];
                    final homeBatters =
                        homeBattersAsync.asData?.value.cast<BatterRecord>() ??
                        const <BatterRecord>[];
                    final relayData = relayAsync.asData?.value;
                    final awayImageMap = {
                      ...allImageMap,
                      for (final player
                          in awayPlayersAsync.asData?.value ??
                              const <PlayerProfile>[])
                        if (player.name.isNotEmpty &&
                            player.imageUrl != null &&
                            player.imageUrl!.isNotEmpty)
                          player.name: player.imageUrl!,
                    };
                    final homeImageMap = {
                      ...allImageMap,
                      for (final player
                          in homePlayersAsync.asData?.value ??
                              const <PlayerProfile>[])
                        if (player.name.isNotEmpty &&
                            player.imageUrl != null &&
                            player.imageUrl!.isNotEmpty)
                          player.name: player.imageUrl!,
                    };

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _LineupHero(
                          awayTeamId: awayTeamId,
                          awayName: awayName,
                          homeTeamId: homeTeamId,
                          homeName: homeName,
                        ),
                        const SizedBox(height: 16),
                        _CompareSection(
                          title: '선발 라인업',
                          left: _LineupColumn(
                            teamId: awayTeamId,
                            teamName: awayName,
                            sideLabel: 'AWAY',
                            starterName: gameLineup.away.starterName,
                            lineup: gameLineup.away.lineup,
                            batterFallback: awayBatters,
                            pitchers: awayPitchers,
                            relayData: relayData,
                            imageMap: awayImageMap,
                            showBullpen: true,
                            isLive: gameStatus == GameStatus.live,
                            isAwayTeam: true,
                          ),
                          right: _LineupColumn(
                            teamId: homeTeamId,
                            teamName: homeName,
                            sideLabel: 'HOME',
                            starterName: gameLineup.home.starterName,
                            lineup: gameLineup.home.lineup,
                            batterFallback: homeBatters,
                            pitchers: homePitchers,
                            relayData: relayData,
                            imageMap: homeImageMap,
                            showBullpen: true,
                            isLive: gameStatus == GameStatus.live,
                            isAwayTeam: false,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildUnavailableState(String message) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.groups_2_outlined, size: 48, color: AppColors.divider),
          const SizedBox(height: 12),
          Text(message, style: const TextStyle(color: AppColors.textDisabled)),
        ],
      ),
    );
  }
}

class _LineupHero extends StatelessWidget {
  final String awayTeamId;
  final String awayName;
  final String homeTeamId;
  final String homeName;

  const _LineupHero({
    required this.awayTeamId,
    required this.awayName,
    required this.homeTeamId,
    required this.homeName,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.divider),
        boxShadow: const [
          BoxShadow(
            color: Color(0x16000000),
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          const Text(
            '라인업',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _HeroTeamMark(
                  teamId: awayTeamId,
                  teamName: awayName,
                  alignEnd: true,
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  'VS',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textDisabled,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Expanded(
                child: _HeroTeamMark(teamId: homeTeamId, teamName: homeName),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroTeamMark extends StatelessWidget {
  final String teamId;
  final String teamName;
  final bool alignEnd;

  const _HeroTeamMark({
    required this.teamId,
    required this.teamName,
    this.alignEnd = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: alignEnd
          ? MainAxisAlignment.end
          : MainAxisAlignment.start,
      children: [
        if (alignEnd)
          Flexible(
            child: Text(
              teamName,
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
          ),
        if (alignEnd) const SizedBox(width: 10),
        _TeamLogo(teamId: teamId, fallback: teamName),
        if (!alignEnd) const SizedBox(width: 10),
        if (!alignEnd)
          Flexible(
            child: Text(
              teamName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
          ),
      ],
    );
  }
}

class _CompareSection extends StatelessWidget {
  final String title;
  final Widget left;
  final Widget right;

  const _CompareSection({
    required this.title,
    required this.left,
    required this.right,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked = constraints.maxWidth < 680;

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(0, 8, 0, 0),
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 14),
              if (stacked) ...[
                left,
                const SizedBox(height: 18),
                Container(height: 1, color: AppColors.divider),
                const SizedBox(height: 18),
                right,
              ] else
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: left),
                      Container(width: 1, color: AppColors.divider),
                      Expanded(child: right),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _LineupColumn extends StatelessWidget {
  final String teamId;
  final String teamName;
  final String sideLabel;
  final String? starterName;
  final List<LineupEntry> lineup;
  final List<BatterRecord> batterFallback;
  final List<PitcherRecord> pitchers;
  final RelayData? relayData;
  final Map<String, String> imageMap;
  final bool showBullpen;
  final bool isLive;
  final bool isAwayTeam;

  const _LineupColumn({
    required this.teamId,
    required this.teamName,
    required this.sideLabel,
    required this.starterName,
    required this.lineup,
    required this.batterFallback,
    required this.pitchers,
    required this.relayData,
    required this.imageMap,
    required this.showBullpen,
    required this.isLive,
    required this.isAwayTeam,
  });

  @override
  Widget build(BuildContext context) {
    final accent = KboTeams.byId(teamId)?.primaryColor ?? AppColors.accent;
    final baseLineup = lineup.isNotEmpty
        ? lineup.take(9).toList()
        : _lineupEntriesFromBatters(batterFallback);
    final displayedLineup = _mergeLineupWithRelaySubstitutions(
      baseLineup,
      relayData,
      isAwayTeam: isAwayTeam,
    );
    final starter = _starterPitcher(pitchers, starterName);
    final missingPitcherData = pitchers.isEmpty && displayedLineup.isNotEmpty;
    final bullpenPreview = pitchers
        .where((pitcher) => pitcher.name != (starterName ?? starter?.name))
        .toList();
    final relayBullpenNames = _relayBullpenNames(
      relayData,
      isAwayTeam: isAwayTeam,
      starterName: starterName ?? starter?.name,
      currentPitcherName: relayData?.currentAtBat?.pitcherName,
    );
    final bullpenNames = <String>[
      ...bullpenPreview.map((pitcher) => pitcher.name),
      ...relayBullpenNames.where(
        (name) => !bullpenPreview.any((pitcher) => pitcher.name == name),
      ),
    ];
    final starterDetail = starter == null
        ? '발표 대기'
        : starter.innings.isEmpty
        ? '실시간 경기 기준 투수'
        : '${starter.innings}이닝 · 삼진 ${starter.strikeouts} · 볼넷 ${starter.walks}';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _TeamLogo(teamId: teamId, fallback: teamName, size: 26),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  teamName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                sideLabel,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            '선발',
            style: TextStyle(
              fontSize: 12,
              color: accent,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          if (starterName != null || starter != null)
            _StarterRow(
              name: starterName ?? starter?.name ?? '선발 미발표',
              detail: starterDetail,
              accent: accent,
              imageUrl: _resolveImageUrl(
                imageMap,
                starterName ?? starter?.name ?? '',
              ),
            )
          else if (missingPitcherData)
            const _EmptyLabel(label: 'KBO 투수 데이터 미제공')
          else
            const _EmptyLabel(label: '선발 미발표'),
          if (showBullpen) ...[
            const SizedBox(height: 12),
            _BullpenSummary(
              accent: accent,
              count: bullpenNames.length,
              hasData: !missingPitcherData || bullpenNames.isNotEmpty,
              isLive: isLive,
            ),
            const SizedBox(height: 10),
            if (bullpenNames.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: _EmptyLabel(
                  label: isLive
                      ? '실시간 불펜 집계 중'
                      : missingPitcherData
                      ? '박스스코어 투수 기록 없음'
                      : '아직 불펜 등판 없음',
                ),
              )
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (int index = 0; index < bullpenNames.length; index++) ...[
                    _BullpenNameRow(
                      name: bullpenNames[index],
                      accent: accent,
                      orderLabel: '${index + 1}',
                      imageUrl: _resolveImageUrl(imageMap, bullpenNames[index]),
                    ),
                    if (index != bullpenNames.length - 1)
                      const Divider(color: AppColors.divider, height: 14),
                  ],
                ],
              ),
          ],
          if (displayedLineup.isEmpty) ...[
            const SizedBox(height: 12),
            _EmptyLabel(
              label: isLive ? '실시간 타자 라인업 집계 중' : '타자 라인업 데이터 없음',
            ),
          ],
          const SizedBox(height: 14),
          for (final entry in displayedLineup) ...[
            _LineupRow(
              entry: entry,
              accent: accent,
              imageUrl: _resolveImageUrl(imageMap, entry.name),
            ),
            if (entry != displayedLineup.last)
              const Divider(color: AppColors.divider, height: 14),
          ],
        ],
      ),
    );
  }

  List<LineupEntry> _lineupEntriesFromBatters(List<BatterRecord> batters) {
    return batters
        .where((batter) => batter.name.isNotEmpty)
        .take(9)
        .map(
          (batter) => LineupEntry(
            order: batter.order,
            position: batter.position,
            positionKo: batter.position,
            name: batter.name,
          ),
        )
        .toList();
  }
}

List<String> _relayBullpenNames(
  RelayData? relayData, {
  required bool isAwayTeam,
  required String? starterName,
  required String? currentPitcherName,
}) {
  if (relayData == null) {
    return const <String>[];
  }

  final targetHalf = isAwayTeam ? 'bottom' : 'top';
  final names = <String>[];
  for (final item in relayData.relayItems) {
    if (item.half != targetHalf) {
      continue;
    }
    final match = RegExp(
      r'투수\s+(.+?)\s*:\s*투수\s+(.+?)\s+\(으\)로\s+교체',
    ).firstMatch(item.text);
    final nextPitcher = match?.group(2)?.trim();
    if (nextPitcher == null || nextPitcher.isEmpty) {
      continue;
    }
    if (nextPitcher == starterName || names.contains(nextPitcher)) {
      continue;
    }
    names.add(nextPitcher);
  }

  final currentPitcher = currentPitcherName?.trim();
  if (currentPitcher != null &&
      currentPitcher.isNotEmpty &&
      currentPitcher != starterName &&
      !names.contains(currentPitcher)) {
    names.add(currentPitcher);
  }
  return names;
}

List<LineupEntry> _mergeLineupWithRelaySubstitutions(
  List<LineupEntry> lineup,
  RelayData? relayData, {
  required bool isAwayTeam,
}) {
  if (relayData == null || lineup.isEmpty) {
    return lineup;
  }

  final targetHalf = isAwayTeam ? 'top' : 'bottom';
  final merged = [...lineup];
  final items = [...relayData.relayItems]
    ..sort((a, b) => a.seqNo.compareTo(b.seqNo));

  for (final item in items) {
    if (item.half != targetHalf) {
      continue;
    }

    final pinchHit = RegExp(
      r'(?:(\d+)번타자\s+)?(.+?)\s*:\s*대타\s+(.+?)\s+\(으\)로\s+교체',
    ).firstMatch(item.text);
    final pinchRun = RegExp(
      r'(?:(\d+)루주자\s+)?(.+?)\s*:\s*대주자\s+(.+?)\s+\(으\)로\s+교체',
    ).firstMatch(item.text);
    final match = pinchHit ?? pinchRun;
    if (match == null) {
      continue;
    }

    final order = int.tryParse(match.group(1) ?? '');
    final outgoing = (match.group(2) ?? '').trim();
    final incoming = (match.group(3) ?? '').trim();
    final changeLabel = pinchHit != null ? '대타' : '대주자';
    if (incoming.isEmpty) {
      continue;
    }

    final index = order != null && order > 0
        ? merged.indexWhere((entry) => entry.order == order)
        : merged.indexWhere(
            (entry) => _normalizeName(entry.name) == _normalizeName(outgoing),
          );
    if (index == -1) {
      continue;
    }

    final current = merged[index];
    merged[index] = LineupEntry(
      order: current.order,
      position: current.position,
      positionKo: current.positionKo,
      name: incoming,
      changeLabel: changeLabel,
    );
  }

  return merged;
}

String? _resolveImageUrl(Map<String, String> imageMap, String rawName) {
  if (rawName.isEmpty) {
    return null;
  }
  if (imageMap.containsKey(rawName)) {
    return imageMap[rawName];
  }

  final normalized = _normalizeName(rawName);
  for (final entry in imageMap.entries) {
    final key = _normalizeName(entry.key);
    if (key == normalized ||
        key.contains(normalized) ||
        normalized.contains(key)) {
      return entry.value;
    }
  }
  return null;
}

String _normalizeName(String value) {
  return value
      .replaceAll(RegExp(r'\s+'), '')
      .replaceAll('·', '')
      .replaceAll('ㆍ', '')
      .replaceAll('.', '')
      .trim();
}

PitcherRecord? _starterPitcher(
  List<PitcherRecord> pitchers,
  String? starterName,
) {
  if (pitchers.isEmpty) {
    return null;
  }
  if (starterName == null || starterName.isEmpty) {
    return pitchers.first;
  }
  return pitchers.where((pitcher) => pitcher.name == starterName).firstOrNull ??
      pitchers.first;
}

class _BullpenSummary extends StatelessWidget {
  final Color accent;
  final int count;
  final bool hasData;
  final bool isLive;

  const _BullpenSummary({
    required this.accent,
    required this.count,
    required this.hasData,
    required this.isLive,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.22)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '$count명',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: accent,
              ),
            ),
          ),
          const SizedBox(width: 10),
          const Spacer(),
        ],
      ),
    );
  }
}

class _BullpenNameRow extends StatelessWidget {
  final String name;
  final Color accent;
  final String orderLabel;
  final String? imageUrl;

  const _BullpenNameRow({
    required this.name,
    required this.accent,
    required this.orderLabel,
    required this.imageUrl,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _LineupAvatar(
          imageUrl: imageUrl,
          fallbackLabel: name,
          accent: accent,
          badgeLabel: orderLabel,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            name,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

class _StarterRow extends StatelessWidget {
  final String name;
  final String detail;
  final Color accent;
  final String? imageUrl;

  const _StarterRow({
    required this.name,
    required this.detail,
    required this.accent,
    required this.imageUrl,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          _LineupAvatar(
            imageUrl: imageUrl,
            fallbackLabel: name,
            accent: accent,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 3),
                Text(
                  detail,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LineupRow extends StatelessWidget {
  final LineupEntry entry;
  final Color accent;
  final String? imageUrl;

  const _LineupRow({
    required this.entry,
    required this.accent,
    required this.imageUrl,
  });

  @override
  Widget build(BuildContext context) {
    final positionLabel = entry.positionKo.isNotEmpty
        ? entry.positionKo
        : entry.position;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 30,
          child: Text(
            '${entry.order}',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: accent,
            ),
          ),
        ),
        const SizedBox(width: 10),
        _LineupAvatar(
          imageUrl: imageUrl,
          fallbackLabel: entry.name,
          accent: accent,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      entry.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (entry.changeLabel != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        entry.changeLabel!,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: accent,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                '$positionLabel · ${entry.position}',
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LineupAvatar extends StatelessWidget {
  final String? imageUrl;
  final String fallbackLabel;
  final Color accent;
  final String? badgeLabel;

  const _LineupAvatar({
    required this.imageUrl,
    required this.fallbackLabel,
    required this.accent,
    this.badgeLabel,
  });

  @override
  Widget build(BuildContext context) {
    if (imageUrl != null && imageUrl!.isNotEmpty) {
      return Stack(
        clipBehavior: Clip.none,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: CachedNetworkImage(
              imageUrl: imageUrl!,
              httpHeaders: _kboImageHeaders,
              width: 42,
              height: 42,
              fit: BoxFit.cover,
              placeholder: (_, _) => _fallback(),
              errorWidget: (_, _, _) => _fallback(),
            ),
          ),
          if (badgeLabel != null) _orderBadge(),
        ],
      );
    }
    return Stack(
      clipBehavior: Clip.none,
      children: [
        _fallback(),
        if (badgeLabel != null) _orderBadge(),
      ],
    );
  }

  Widget _orderBadge() {
    return Positioned(
      right: -4,
      bottom: -4,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: accent,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: AppColors.background, width: 1.5),
        ),
        child: Text(
          badgeLabel!,
          style: const TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
      ),
    );
  }

  Widget _fallback() {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(10),
      ),
      alignment: Alignment.center,
      child: Text(
        fallbackLabel.isEmpty ? '?' : fallbackLabel.substring(0, 1),
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _EmptyLabel extends StatelessWidget {
  final String label;

  const _EmptyLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(fontSize: 12, color: AppColors.textDisabled),
    );
  }
}

class _TeamLogo extends StatelessWidget {
  final String teamId;
  final String fallback;
  final double size;

  const _TeamLogo({
    required this.teamId,
    required this.fallback,
    this.size = 34,
  });

  @override
  Widget build(BuildContext context) {
    final team = KboTeams.byId(teamId);
    return CachedNetworkImage(
      imageUrl: team?.logoUrl ?? '',
      httpHeaders: _kboImageHeaders,
      width: size,
      height: size,
      placeholder: (_, _) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: AppColors.cardSub,
          shape: BoxShape.circle,
        ),
      ),
      errorWidget: (_, _, _) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: AppColors.cardSub,
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Text(
          fallback.isEmpty ? '?' : fallback.substring(0, 1).toUpperCase(),
          style: const TextStyle(
            fontSize: 12,
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
