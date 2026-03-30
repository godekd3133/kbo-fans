import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../core/constants/team_data.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/game.dart';
import 'tabs/score_tab.dart';
import 'tabs/relay_tab.dart';
import 'tabs/boxscore_tab.dart';
import 'tabs/lineup_tab.dart';

class GameDetailScreen extends StatelessWidget {
  final String gameId;
  final Game? game;

  const GameDetailScreen({super.key, required this.gameId, this.game});

  @override
  Widget build(BuildContext context) {
    if (game == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('경기 상세')),
        body: const Center(child: Text('경기를 찾을 수 없습니다')),
      );
    }

    final g = game!;
    final isLive = g.status == GameStatus.live;

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              // 네비게이션 바
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back, size: 24),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    Expanded(
                      child: Text(
                        '${g.stadium} · ${g.crowd != null ? "${_formatNumber(g.crowd!)}명" : ""}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 14, color: AppColors.textSecondary),
                      ),
                    ),
                    const SizedBox(width: 48),
                  ],
                ),
              ),
              // 스코어 영역
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                child: Row(
                  children: [
                    Expanded(child: _teamSection(g.away.teamId, g.away.shortName)),
                    const SizedBox(width: 16),
                    Column(
                      children: [
                        Text(
                          '${g.away.score} : ${g.home.score}',
                          style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w700, letterSpacing: 4),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          g.inning,
                          style: TextStyle(
                            fontSize: 14,
                            color: isLive ? AppColors.live : AppColors.textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 16),
                    Expanded(child: _teamSection(g.home.teamId, g.home.shortName)),
                  ],
                ),
              ),
              // 탭 바
              const TabBar(
                indicatorColor: AppColors.textPrimary,
                indicatorWeight: 2,
                labelColor: AppColors.textPrimary,
                labelStyle: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                unselectedLabelColor: AppColors.textDisabled,
                unselectedLabelStyle: TextStyle(fontSize: 14),
                tabs: [
                  Tab(text: '스코어'),
                  Tab(text: '문자중계'),
                  Tab(text: '박스스코어'),
                  Tab(text: '라인업'),
                ],
              ),
              const Divider(height: 1, color: AppColors.divider),
              // 탭 콘텐츠
              Expanded(
                child: TabBarView(
                  children: [
                    ScoreTab(game: g),
                    RelayTab(gameId: gameId),
                    BoxscoreTab(gameId: gameId),
                    LineupTab(gameId: gameId),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _teamSection(String teamId, String shortName) {
    final team = KboTeams.byId(teamId);
    return Column(
      children: [
        CachedNetworkImage(
          imageUrl: team?.logoUrl ?? '',
          width: 40, height: 40,
          placeholder: (_, _) => Container(width: 40, height: 40, decoration: BoxDecoration(color: AppColors.cardSub, shape: BoxShape.circle)),
          errorWidget: (_, _, _) => Container(
            width: 40, height: 40,
            decoration: BoxDecoration(color: AppColors.cardSub, shape: BoxShape.circle),
            child: Center(child: Text(shortName, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary))),
          ),
        ),
        const SizedBox(height: 4),
        Text(shortName, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
      ],
    );
  }

  String _formatNumber(int n) {
    if (n >= 1000) {
      return '${(n / 1000).toStringAsFixed(0)},${(n % 1000).toString().padLeft(3, '0')}';
    }
    return '$n';
  }
}
