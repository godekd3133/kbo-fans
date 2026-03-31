import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/team_data.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/boxscore.dart';
import '../../../data/providers.dart';

class LineupTab extends ConsumerWidget {
  final String gameId;
  final String awayName;
  final String homeName;
  final String awayTeamId;
  final String homeTeamId;

  const LineupTab({
    super.key,
    required this.gameId,
    this.awayName = '원정',
    this.homeName = '홈',
    this.awayTeamId = '',
    this.homeTeamId = '',
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gameLineupAsync = ref.watch(gameLineupProvider(gameId));
    final awayPitchersAsync = ref.watch(pitchersProvider('$gameId|true'));
    final homePitchersAsync = ref.watch(pitchersProvider('$gameId|false'));

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth > 760
            ? 720.0
            : constraints.maxWidth;

        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: SingleChildScrollView(
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
                  final awayPitchers = awayPitchersAsync.asData?.value.cast<PitcherRecord>() ?? const <PitcherRecord>[];
                  final homePitchers = homePitchersAsync.asData?.value.cast<PitcherRecord>() ?? const <PitcherRecord>[];

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
                          pitchers: awayPitchers,
                          showBullpen: false,
                        ),
                        right: _LineupColumn(
                          teamId: homeTeamId,
                          teamName: homeName,
                          sideLabel: 'HOME',
                          starterName: gameLineup.home.starterName,
                          lineup: gameLineup.home.lineup,
                          pitchers: homePitchers,
                          showBullpen: false,
                        ),
                      ),
                      const SizedBox(height: 18),
                      _CompareSection(
                        title: '불펜투수',
                        left: _BullpenColumn(
                          teamId: awayTeamId,
                          pitchers: awayPitchers,
                          starterName: gameLineup.away.starterName,
                        ),
                        right: _BullpenColumn(
                          teamId: homeTeamId,
                          pitchers: homePitchers,
                          starterName: gameLineup.home.starterName,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        );
      },
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
          const SizedBox(height: 6),
          const Text(
            '양팀 선발과 불펜 구성을 한 화면에서 비교합니다.',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
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
                child: _HeroTeamMark(
                  teamId: homeTeamId,
                  teamName: homeName,
                ),
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
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 14),
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
  }
}

class _LineupColumn extends StatelessWidget {
  final String teamId;
  final String teamName;
  final String sideLabel;
  final String? starterName;
  final List<LineupEntry> lineup;
  final List<PitcherRecord> pitchers;
  final bool showBullpen;

  const _LineupColumn({
    required this.teamId,
    required this.teamName,
    required this.sideLabel,
    required this.starterName,
    required this.lineup,
    required this.pitchers,
    required this.showBullpen,
  });

  @override
  Widget build(BuildContext context) {
    final accent = KboTeams.byId(teamId)?.primaryColor ?? AppColors.accent;
    final displayedLineup = lineup.take(9).toList();
    final starter = _starterPitcher(pitchers, starterName);

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
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
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
            style: TextStyle(fontSize: 12, color: accent, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          if (starterName != null || starter != null)
            _StarterRow(
              name: starterName ?? starter?.name ?? '선발 미발표',
              detail: starter == null
                  ? '발표 대기'
                  : '${starter.innings}이닝 · 삼진 ${starter.strikeouts} · 볼넷 ${starter.walks}',
              accent: accent,
            )
          else
            const _EmptyLabel(label: '선발 미발표'),
          const SizedBox(height: 14),
          for (final entry in displayedLineup) ...[
            _LineupRow(entry: entry, accent: accent),
            if (entry != displayedLineup.last) const Divider(color: AppColors.divider, height: 14),
          ],
        ],
      ),
    );
  }
}

PitcherRecord? _starterPitcher(List<PitcherRecord> pitchers, String? starterName) {
  if (pitchers.isEmpty) {
    return null;
  }
  if (starterName == null || starterName.isEmpty) {
    return pitchers.first;
  }
  return pitchers.where((pitcher) => pitcher.name == starterName).firstOrNull ??
      pitchers.first;
}

class _BullpenColumn extends StatelessWidget {
  final String teamId;
  final List<PitcherRecord> pitchers;
  final String? starterName;

  const _BullpenColumn({
    required this.teamId,
    required this.pitchers,
    required this.starterName,
  });

  @override
  Widget build(BuildContext context) {
    final team = KboTeams.byId(teamId);
    final accent = team?.primaryColor ?? AppColors.accent;
    final bullpen = pitchers
        .where((pitcher) => pitcher.name != starterName)
        .toList();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: bullpen.isEmpty
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: _EmptyLabel(label: '불펜 데이터 없음'),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final pitcher in bullpen.take(8)) ...[
                  _PitcherRow(pitcher: pitcher, accent: accent),
                  if (pitcher != bullpen.take(8).last) const Divider(color: AppColors.divider, height: 14),
                ],
              ],
            ),
    );
  }
}

class _StarterRow extends StatelessWidget {
  final String name;
  final String detail;
  final Color accent;

  const _StarterRow({
    required this.name,
    required this.detail,
    required this.accent,
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
            style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _LineupRow extends StatelessWidget {
  final LineupEntry entry;
  final Color accent;

  const _LineupRow({required this.entry, required this.accent});

  @override
  Widget build(BuildContext context) {
    final positionLabel = entry.positionKo.isNotEmpty ? entry.positionKo : entry.position;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 24,
          child: Text(
            '${entry.order}',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: accent),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                entry.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 2),
              Text(
                '$positionLabel · ${entry.position}',
                style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PitcherRow extends StatelessWidget {
  final PitcherRecord pitcher;
  final Color accent;

  const _PitcherRow({required this.pitcher, required this.accent});

  @override
  Widget build(BuildContext context) {
    final detail = <String>[
      '투수',
      pitcher.innings.isNotEmpty ? '${pitcher.innings}이닝' : '',
      pitcher.decision != null ? pitcher.decision! : '',
    ].where((element) => element.isNotEmpty).join(' · ');

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 6,
          height: 6,
          margin: const EdgeInsets.only(top: 6),
          decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                pitcher.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 2),
              Text(
                detail,
                style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      ],
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
