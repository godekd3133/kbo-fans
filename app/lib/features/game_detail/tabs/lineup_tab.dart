import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/team_data.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/boxscore.dart';
import '../../../data/providers.dart';

class LineupTab extends ConsumerStatefulWidget {
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
  ConsumerState<LineupTab> createState() => _LineupTabState();
}

class _LineupTabState extends ConsumerState<LineupTab> {
  bool _showAway = true;

  String get _lineupKey => '${widget.gameId}|$_showAway';
  String get _selectedTeamName => _showAway ? widget.awayName : widget.homeName;
  String get _selectedTeamId =>
      _showAway ? widget.awayTeamId : widget.homeTeamId;

  @override
  Widget build(BuildContext context) {
    final gameLineupAsync = ref.watch(gameLineupProvider(widget.gameId));
    final pitchersAsync = ref.watch(pitchersProvider(_lineupKey));

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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildTeamToggle(),
                  const SizedBox(height: 16),
                  gameLineupAsync.when(
                    loading: () => const Center(
                      child: Padding(
                        padding: EdgeInsets.all(28),
                        child: CircularProgressIndicator(color: AppColors.live),
                      ),
                    ),
                    error: (error, _) => Text(
                      '라인업 데이터 로딩 실패: $error',
                      style: const TextStyle(color: AppColors.textDisabled),
                    ),
                    data: (gameLineup) {
                      final teamLineup = _showAway ? gameLineup.away : gameLineup.home;
                      return pitchersAsync.when(
                      loading: () => _buildContent(teamLineup, const []),
                      error: (_, _) => _buildContent(teamLineup, const []),
                      data: (pitchers) =>
                          _buildContent(teamLineup, pitchers.cast<PitcherRecord>()),
                    );
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTeamToggle() {
    return Row(
      children: [
        Expanded(
          child: _TeamToggleChip(
            sideLabel: 'AWAY',
            teamId: widget.awayTeamId,
            teamName: widget.awayName,
            active: _showAway,
            onTap: () => setState(() => _showAway = true),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _TeamToggleChip(
            sideLabel: 'HOME',
            teamId: widget.homeTeamId,
            teamName: widget.homeName,
            active: !_showAway,
            onTap: () => setState(() => _showAway = false),
          ),
        ),
      ],
    );
  }

  Widget _buildContent(TeamLineupData teamLineup, List<PitcherRecord> pitchers) {
    final lineup = teamLineup.lineup;
    if (lineup.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text(
            '라인업 정보가 아직 없습니다',
            style: TextStyle(color: AppColors.textDisabled),
          ),
        ),
      );
    }

    final team = KboTeams.byId(_selectedTeamId);
    final starter = lineup
        .where(
          (entry) => entry.position == 'P' || entry.positionKo.contains('투수'),
        )
        .cast<LineupEntry?>()
        .firstWhere((entry) => entry != null, orElse: () => null);
    final starterStats = pitchers.isNotEmpty ? pitchers.first : null;
    final starterName = (teamLineup.starterName != null && teamLineup.starterName!.isNotEmpty)
        ? teamLineup.starterName
        : starter?.name;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: _teamAccent(team).withValues(alpha: 0.45),
            ),
            boxShadow: [
              BoxShadow(
                color: _teamAccent(team).withValues(alpha: 0.12),
                blurRadius: 22,
                offset: const Offset(0, 10),
              ),
            ],
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                _teamAccent(team).withValues(alpha: 0.22),
                AppColors.card,
              ],
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _TeamLogo(
                    teamId: _selectedTeamId,
                    fallback: _selectedTeamName,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _selectedTeamName,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${lineup.length}명 라인업',
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.background.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      _showAway ? 'AWAY' : 'HOME',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
              if (starterName != null) ...[
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.background.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: _teamAccent(team).withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          'SP',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: _teamAccent(team),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '선발투수',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textDisabled,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              starterName,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                if (starterStats != null) ...[
                                  _Pill(
                                    label: '이닝 ${starterStats.innings}',
                                    color: _teamAccent(team),
                                  ),
                                  _Pill(
                                    label: '삼진 ${starterStats.strikeouts}',
                                    color: AppColors.live,
                                  ),
                                  _Pill(
                                    label: '사사구 ${starterStats.walks}',
                                    color: AppColors.ballYellow,
                                  ),
                                  _Pill(
                                    label: '자책 ${starterStats.earnedRuns}',
                                    color: AppColors.textSecondary,
                                    subtle: true,
                                  ),
                                ] else
                                  const _Pill(
                                    label: '시즌 기록 연동 예정',
                                    color: AppColors.textSecondary,
                                    subtle: true,
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.background.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '선발투수',
                        style: TextStyle(fontSize: 12, color: AppColors.textDisabled),
                      ),
                      SizedBox(height: 2),
                      Text(
                        '선발투수 미발표',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        ...lineup.map(
          (entry) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _LineupCard(entry: entry, accent: _teamAccent(team)),
          ),
        ),
      ],
    );
  }

  Color _teamAccent(KboTeam? team) => team?.primaryColor ?? AppColors.accent;
}

class _TeamToggleChip extends StatelessWidget {
  final String sideLabel;
  final String teamId;
  final String teamName;
  final bool active;
  final VoidCallback onTap;

  const _TeamToggleChip({
    required this.sideLabel,
    required this.teamId,
    required this.teamName,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final team = KboTeams.byId(teamId);
    final accent = team?.primaryColor ?? AppColors.textPrimary;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: active ? AppColors.card : AppColors.background,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: active ? accent : AppColors.divider),
          ),
          child: Row(
            children: [
              _TeamLogo(teamId: teamId, fallback: teamName),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      sideLabel,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: active ? accent : AppColors.textDisabled,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      teamName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: active
                            ? AppColors.textPrimary
                            : AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LineupCard extends StatelessWidget {
  final LineupEntry entry;
  final Color accent;

  const _LineupCard({required this.entry, required this.accent});

  @override
  Widget build(BuildContext context) {
    final positionLabel = entry.positionKo.isNotEmpty
        ? entry.positionKo
        : entry.position;
    final battingOrderLabel = '${entry.order}번 타자';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider.withValues(alpha: 0.6)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: Text(
              '${entry.order}',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: accent,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '$battingOrderLabel · $positionLabel',
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _Pill(label: battingOrderLabel, color: accent),
                    _Pill(label: positionLabel, color: accent),
                    _Pill(
                      label: entry.position,
                      color: AppColors.textSecondary,
                      subtle: true,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TeamLogo extends StatelessWidget {
  final String teamId;
  final String fallback;

  const _TeamLogo({required this.teamId, required this.fallback});

  @override
  Widget build(BuildContext context) {
    final team = KboTeams.byId(teamId);
    return CachedNetworkImage(
      imageUrl: team?.logoUrl ?? '',
      width: 38,
      height: 38,
      placeholder: (_, _) => _fallback(team),
      errorWidget: (_, _, _) => _fallback(team),
    );
  }

  Widget _fallback(KboTeam? team) {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: (team?.primaryColor ?? AppColors.cardSub).withValues(
          alpha: 0.18,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      alignment: Alignment.center,
      child: Text(
        fallback.isNotEmpty ? fallback.substring(0, 1) : '?',
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final Color color;
  final bool subtle;

  const _Pill({required this.label, required this.color, this.subtle = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: subtle ? AppColors.background : color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: subtle ? AppColors.divider : color.withValues(alpha: 0.28),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: subtle ? AppColors.textSecondary : AppColors.textPrimary,
        ),
      ),
    );
  }
}
