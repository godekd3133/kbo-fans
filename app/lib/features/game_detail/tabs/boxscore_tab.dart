import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/team_data.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/game.dart';
import '../../../data/models/boxscore.dart';
import '../../../data/models/player.dart';
import '../../../data/providers.dart';

class BoxscoreTab extends ConsumerStatefulWidget {
  final String gameId;
  final GameStatus gameStatus;
  final String awayName;
  final String homeName;
  final String awayTeamId;
  final String homeTeamId;

  const BoxscoreTab({
    super.key,
    required this.gameId,
    required this.gameStatus,
    this.awayName = '원정',
    this.homeName = '홈',
    this.awayTeamId = '',
    this.homeTeamId = '',
  });

  @override
  ConsumerState<BoxscoreTab> createState() => _BoxscoreTabState();
}

class _BoxscoreTabState extends ConsumerState<BoxscoreTab> {
  bool _showAway = true;

  String get _batterKey => '${widget.gameId}|$_showAway';
  String get _pitcherKey => '${widget.gameId}|$_showAway';
  String get _selectedTeamName => _showAway ? widget.awayName : widget.homeName;
  String get _selectedTeamId =>
      _showAway ? widget.awayTeamId : widget.homeTeamId;

  @override
  Widget build(BuildContext context) {
    if (widget.gameStatus == GameStatus.scheduled) {
      return _buildUnavailableState('경기 시작 후 박스스코어가 제공됩니다');
    }
    if (widget.gameStatus == GameStatus.cancelled) {
      return _buildUnavailableState('취소된 경기는 박스스코어가 없습니다');
    }

    final battersAsync = ref.watch(battersProvider(_batterKey));
    final pitchersAsync = ref.watch(pitchersProvider(_pitcherKey));
    final season = DateTime.now().year;
    final playersAsync = _selectedTeamId.isEmpty
        ? const AsyncValue<List<PlayerProfile>>.data(<PlayerProfile>[])
        : ref.watch(teamPlayersProvider('$_selectedTeamId|$season'));

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
                  battersAsync.when(
                    loading: () => const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: CircularProgressIndicator(color: AppColors.live),
                      ),
                    ),
                    error: (error, _) => Text(
                      '타자 데이터 로딩 실패: $error',
                      style: const TextStyle(color: AppColors.textDisabled),
                    ),
                    data: (batters) => pitchersAsync.when(
                      loading: () => const SizedBox.shrink(),
                      error: (error, _) => Text(
                        '투수 데이터 로딩 실패: $error',
                        style: const TextStyle(color: AppColors.textDisabled),
                      ),
                      data: (pitchers) => playersAsync.when(
                        loading: () => _buildContent(
                          batters.cast<BatterRecord>(),
                          pitchers.cast<PitcherRecord>(),
                          const {},
                        ),
                        error: (_, _) => _buildContent(
                          batters.cast<BatterRecord>(),
                          pitchers.cast<PitcherRecord>(),
                          const {},
                        ),
                        data: (players) => _buildContent(
                          batters.cast<BatterRecord>(),
                          pitchers.cast<PitcherRecord>(),
                          {
                            for (final player in players)
                              if (player.name.isNotEmpty && player.imageUrl != null && player.imageUrl!.isNotEmpty)
                                player.name: player.imageUrl!,
                          },
                        ),
                      ),
                    ),
                  ),
                ],
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
          Icon(Icons.sports_baseball, size: 48, color: AppColors.divider),
          const SizedBox(height: 12),
          Text(message, style: const TextStyle(color: AppColors.textDisabled)),
        ],
      ),
    );
  }

  Widget _buildTeamToggle() {
    return Row(
      children: [
        Expanded(
          child: _TeamToggleCard(
            sideLabel: 'AWAY',
            teamId: widget.awayTeamId,
            teamName: widget.awayName,
            active: _showAway,
            onTap: () => setState(() => _showAway = true),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _TeamToggleCard(
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

  Widget _buildContent(
    List<BatterRecord> batters,
    List<PitcherRecord> pitchers,
    Map<String, String> playerImages,
  ) {
    final team = KboTeams.byId(_selectedTeamId);
    final accent = team?.primaryColor ?? AppColors.accent;
    final totalAtBats = batters.fold<int>(
      0,
      (sum, batter) => sum + batter.atBats,
    );
    final totalRuns = batters.fold<int>(0, (sum, batter) => sum + batter.runs);
    final totalHits = batters.fold<int>(0, (sum, batter) => sum + batter.hits);
    final totalRbi = batters.fold<int>(0, (sum, batter) => sum + batter.rbi);
    final keyBatter = batters.isEmpty
        ? null
        : batters.reduce((a, b) {
            final aScore = (a.hits * 3) + (a.rbi * 2) + a.runs;
            final bScore = (b.hits * 3) + (b.rbi * 2) + b.runs;
            return aScore >= bScore ? a : b;
          });
    final keyPitcher = pitchers.isEmpty
        ? null
        : pitchers.reduce((a, b) {
            final aScore =
                (a.strikeouts * 2) - (a.walks * 2) - (a.earnedRuns * 3);
            final bScore =
                (b.strikeouts * 2) - (b.walks * 2) - (b.earnedRuns * 3);
            return aScore >= bScore ? a : b;
          });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.divider),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [accent.withValues(alpha: 0.16), AppColors.card],
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
                        const Text(
                          '타격 요약',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _StatTile(label: '타수', value: '$totalAtBats'),
                  _StatTile(label: '득점', value: '$totalRuns'),
                  _StatTile(label: '안타', value: '$totalHits'),
                  _StatTile(label: '타점', value: '$totalRbi'),
                ],
              ),
              if (keyBatter != null || keyPitcher != null) ...[
                const SizedBox(height: 16),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    if (keyBatter != null)
                      _HighlightCard(
                        title: '핵심 타자',
                        name: keyBatter.name,
                        accent: accent,
                        summary:
                            '안타 ${keyBatter.hits} · 타점 ${keyBatter.rbi} · 득점 ${keyBatter.runs}',
                      ),
                    if (keyPitcher != null)
                      _HighlightCard(
                        title: '핵심 투수',
                        name: keyPitcher.name,
                        accent: AppColors.live,
                        summary:
                            '이닝 ${keyPitcher.innings} · 삼진 ${keyPitcher.strikeouts} · 자책 ${keyPitcher.earnedRuns}',
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 18),
        const Text(
          '타자',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        ...batters.map((batter) => _buildBatterCard(batter, accent, playerImages)),
        const SizedBox(height: 18),
        const Text(
          '투수',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        ...pitchers.map((pitcher) => _buildPitcherCard(pitcher, accent)),
      ],
    );
  }

  Widget _buildBatterCard(
    BatterRecord batter,
    Color accent,
    Map<String, String> playerImages,
  ) {
    final imageUrl = playerImages[batter.name];
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: accent.withValues(alpha: 0.18)),
        ),
        child: Row(
          children: [
            _PlayerAvatar(
              imageUrl: imageUrl,
              fallbackLabel: batter.name,
              accent: accent,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          batter.name,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      _InfoPill(label: '${batter.order}번', accent: accent),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${batter.position} 포지션',
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _InfoPill(
                        label: '타수 ${batter.atBats}',
                        accent: AppColors.textDisabled,
                        subtle: true,
                      ),
                      _InfoPill(
                        label: '안타 ${batter.hits}',
                        accent: AppColors.positive,
                      ),
                      _InfoPill(
                        label: '타점 ${batter.rbi}',
                        accent: AppColors.live,
                      ),
                      _InfoPill(
                        label: '득점 ${batter.runs}',
                        accent: AppColors.ballYellow,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPitcherCard(PitcherRecord pitcher, Color accent) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: accent.withValues(alpha: 0.18)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    pitcher.name,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (pitcher.decision != null)
                  _InfoPill(
                    label: pitcher.decision!,
                    accent: AppColors.positive,
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _InfoPill(label: '이닝 ${pitcher.innings}', accent: accent),
                _InfoPill(
                  label: '안타 ${pitcher.hits}',
                  accent: AppColors.textDisabled,
                  subtle: true,
                ),
                _InfoPill(
                  label: '삼진 ${pitcher.strikeouts}',
                  accent: AppColors.live,
                ),
                _InfoPill(
                  label: '사사구 ${pitcher.walks}',
                  accent: AppColors.ballYellow,
                ),
                _InfoPill(
                  label: '자책 ${pitcher.earnedRuns}',
                  accent: AppColors.textDisabled,
                  subtle: true,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TeamToggleCard extends StatelessWidget {
  final String sideLabel;
  final String teamId;
  final String teamName;
  final bool active;
  final VoidCallback onTap;

  const _TeamToggleCard({
    required this.sideLabel,
    required this.teamId,
    required this.teamName,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final team = KboTeams.byId(teamId);

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
            border: Border.all(
              color: active
                  ? (team?.primaryColor ?? AppColors.textPrimary)
                  : AppColors.divider,
            ),
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
                        color: active
                            ? (team?.primaryColor ?? AppColors.textPrimary)
                            : AppColors.textDisabled,
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
      placeholder: (_, _) => _fallbackAvatar(team, fallback),
      errorWidget: (_, _, _) => _fallbackAvatar(team, fallback),
    );
  }

  Widget _fallbackAvatar(KboTeam? team, String fallback) {
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

class _PlayerAvatar extends StatelessWidget {
  final String? imageUrl;
  final String fallbackLabel;
  final Color accent;

  const _PlayerAvatar({
    required this.imageUrl,
    required this.fallbackLabel,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    if (imageUrl != null && imageUrl!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: CachedNetworkImage(
          imageUrl: imageUrl!,
          width: 52,
          height: 52,
          fit: BoxFit.cover,
          placeholder: (_, _) => _fallbackAvatar(),
          errorWidget: (_, _, _) => _fallbackAvatar(),
        ),
      );
    }
    return _fallbackAvatar();
  }

  Widget _fallbackAvatar() {
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(12),
      ),
      alignment: Alignment.center,
      child: Icon(
        Icons.person_rounded,
        color: accent,
        size: 28,
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final String value;

  const _StatTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 100,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.background.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: AppColors.textDisabled),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _HighlightCard extends StatelessWidget {
  final String title;
  final String name;
  final String summary;
  final Color accent;

  const _HighlightCard({
    required this.title,
    required this.name,
    required this.summary,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.background.withValues(alpha: 0.44),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: accent,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            name,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            summary,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  final String label;
  final Color accent;
  final bool subtle;

  const _InfoPill({
    required this.label,
    required this.accent,
    this.subtle = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: subtle ? AppColors.background : accent.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: subtle ? AppColors.divider : accent.withValues(alpha: 0.28),
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
