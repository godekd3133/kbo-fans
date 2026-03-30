import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models/game.dart';
import '../../data/providers.dart';
import '../../services/widget_sync_service.dart';
import 'widgets/game_card.dart';
import 'widgets/my_team_game_card.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> with WidgetsBindingObserver {
  Timer? _refreshTimer;
  String? _lastSyncSignature;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _invalidateTodayScoreboard();
    }
  }

  @override
  Widget build(BuildContext context) {
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final scoreboardAsync = ref.watch(scoreboardProvider(today));
    final myTeamId = ref.watch(myTeamProvider);

    return Scaffold(
      body: SafeArea(
        child: scoreboardAsync.when(
          loading: () => const Center(child: CircularProgressIndicator(color: AppColors.live)),
          error: (error, _) => Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 48, color: AppColors.live),
                const SizedBox(height: 12),
                Text('데이터를 불러올 수 없습니다', style: TextStyle(color: AppColors.textDisabled)),
                const SizedBox(height: 4),
                Text('$error', style: TextStyle(fontSize: 12, color: AppColors.textDisabled)),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: _invalidateTodayScoreboard,
                  child: const Text('다시 시도'),
                ),
              ],
            ),
          ),
          data: (games) {
            _scheduleRefresh(games, myTeamId);
            _syncWidget(games, myTeamId);
            return _buildContent(context, games, myTeamId, today);
          },
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, List<Game> games, String? myTeamId, String today) {
    Game? myGame;
    if (myTeamId != null) {
      for (final game in games) {
        if (game.away.teamId == myTeamId || game.home.teamId == myTeamId) {
          myGame = game;
          break;
        }
      }
    }
    final others = myGame != null ? games.where((g) => g.gameId != myGame!.gameId).toList() : games;
    final hasLive = games.any((g) => g.status == GameStatus.live);

    return RefreshIndicator(
      onRefresh: () async => _invalidateTodayScoreboard(),
      color: AppColors.live,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _buildHeader(context, hasLive)),
          if (games.isEmpty)
            SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.sports_baseball, size: 64, color: AppColors.divider),
                    const SizedBox(height: 16),
                    Text('오늘은 경기가 없습니다', style: TextStyle(fontSize: 16, color: AppColors.textDisabled)),
                  ],
                ),
              ),
            ),
          if (myGame != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: MyTeamGameCard(
                  game: myGame,
                  onTap: () => context.push('/game/${myGame!.gameId}', extra: myGame),
                ),
              ),
            ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            sliver: SliverList.separated(
              itemCount: others.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final game = others[index];
                return GameCard(game: game, onTap: () => context.push('/game/${game.gameId}', extra: game));
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, bool hasLive) {
    final now = DateTime.now();
    final dayNames = ['', '월', '화', '수', '목', '금', '토', '일'];
    final dateStr = '${now.month}.${now.day} ${dayNames[now.weekday]}';

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('KBO Fans', style: Theme.of(context).textTheme.headlineMedium),
          Row(
            children: [
              Text(dateStr, style: TextStyle(fontSize: 14, color: AppColors.textSecondary)),
              if (hasLive) ...[
                const SizedBox(width: 8),
                Container(width: 8, height: 8, decoration: const BoxDecoration(color: AppColors.live, shape: BoxShape.circle)),
              ],
            ],
          ),
        ],
      ),
    );
  }

  void _scheduleRefresh(List<Game> games, String? myTeamId) {
    final interval = _resolveRefreshInterval(games);
    _refreshTimer?.cancel();
    _refreshTimer = Timer(interval, _invalidateTodayScoreboard);
  }

  Duration _resolveRefreshInterval(List<Game> games) {
    if (games.any((game) => game.status == GameStatus.live)) {
      return const Duration(seconds: 30);
    }
    if (games.any((game) => game.status == GameStatus.scheduled)) {
      return const Duration(minutes: 5);
    }
    return const Duration(minutes: 15);
  }

  void _invalidateTodayScoreboard() {
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    ref.invalidate(scoreboardProvider(today));
  }

  void _syncWidget(List<Game> games, String? myTeamId) {
    final signature = '${games.length}|${games.map((g) => '${g.gameId}:${g.inning}:${g.away.score}:${g.home.score}').join(',')}|$myTeamId';
    if (_lastSyncSignature == signature) {
      return;
    }
    _lastSyncSignature = signature;
    unawaited(WidgetSyncService.instance.syncScoreboard(games: games, myTeamId: myTeamId));
  }
}
