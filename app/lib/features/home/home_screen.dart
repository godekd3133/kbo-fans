import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/constants/team_data.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/game_status_badge.dart';
import '../../core/widgets/dev_console.dart';
import '../../data/models/game.dart';
import '../../data/models/records_overview.dart';
import '../../data/models/schedule.dart';
import '../../data/api/api_client.dart';
import '../../data/providers.dart';
import '../../services/widget_sync_service.dart';
import 'widgets/game_card.dart';
import 'widgets/my_team_game_card.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with WidgetsBindingObserver {
  Timer? _refreshTimer;
  String? _lastSyncSignature;
  int? _homeLoadStartedAtMicros;
  String? _lastHomeLoadLogKey;
  bool _secondarySectionsEnabled = false;
  int? _secondarySectionsStartedAtMicros;
  String? _lastSecondarySectionsLogKey;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _homeLoadStartedAtMicros = DateTime.now().microsecondsSinceEpoch;
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
    _logHomeLoad(scoreboardAsync, today);

    return Scaffold(
      body: SafeArea(
        child: scoreboardAsync.when(
          loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.live),
          ),
          error: (error, _) => Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.error_outline,
                  size: 48,
                  color: AppColors.live,
                ),
                const SizedBox(height: 12),
                Text(
                  '데이터를 불러올 수 없습니다',
                  style: TextStyle(color: AppColors.textDisabled),
                ),
                const SizedBox(height: 4),
                Text(
                  describeAsyncError(error),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textDisabled,
                  ),
                ),
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
            _enableSecondarySections();
            return _buildContent(context, games, myTeamId, today);
          },
        ),
      ),
    );
  }

  void _logHomeLoad(AsyncValue<List<Game>> scoreboardAsync, String today) {
    if (!scoreboardAsync.hasValue) {
      _homeLoadStartedAtMicros ??= DateTime.now().microsecondsSinceEpoch;
      return;
    }

    final games = scoreboardAsync.value ?? const <Game>[];
    final logKey = '$today|${games.length}';
    if (_lastHomeLoadLogKey == logKey) {
      return;
    }

    final startedAt = _homeLoadStartedAtMicros;
    if (startedAt != null) {
      final elapsedMs =
          (DateTime.now().microsecondsSinceEpoch - startedAt) / 1000;
      DevConsole.instance.info(
        'HOME loaded ${elapsedMs.toStringAsFixed(0)}ms (${games.length} games)',
      );
      unawaited(
        ref.read(apiClientProvider).postClientMetric({
          'screen': 'home',
          'event': 'loaded',
          'elapsedMs': elapsedMs.round(),
          'gameCount': games.length,
          'date': today,
        }),
      );
    }
    _lastHomeLoadLogKey = logKey;
    _homeLoadStartedAtMicros = null;
  }

  void _logSecondarySectionsLoaded({
    required String today,
    required _MyTeamBriefData? brief,
    required RecordsOverview? overview,
  }) {
    if (!_secondarySectionsEnabled) {
      return;
    }
    if (brief == null && overview == null) {
      return;
    }

    final logKey = '$today|${brief?.teamId ?? '-'}|${overview?.season ?? 0}';
    if (_lastSecondarySectionsLogKey == logKey) {
      return;
    }

    final startedAt = _secondarySectionsStartedAtMicros;
    if (startedAt != null) {
      final elapsedMs =
          (DateTime.now().microsecondsSinceEpoch - startedAt) / 1000;
      DevConsole.instance.info(
        'HOME secondary ${elapsedMs.toStringAsFixed(0)}ms',
      );
      unawaited(
        ref.read(apiClientProvider).postClientMetric({
          'screen': 'home',
          'event': 'secondary_loaded',
          'elapsedMs': elapsedMs.round(),
          'date': today,
          'hasBrief': brief != null,
          'hasOverview': overview != null,
        }),
      );
    }

    _lastSecondarySectionsLogKey = logKey;
    _secondarySectionsStartedAtMicros = null;
  }

  Widget _buildContent(
    BuildContext context,
    List<Game> games,
    String? myTeamId,
    String today,
  ) {
    Game? myGame;
    if (myTeamId != null) {
      for (final game in games) {
        if (game.away.teamId == myTeamId || game.home.teamId == myTeamId) {
          myGame = game;
          break;
        }
      }
    }
    final others = myGame != null
        ? games.where((g) => g.gameId != myGame!.gameId).toList()
        : games;
    final hasLive = games.any((g) => g.status == GameStatus.live);
    final todayBrief = _buildTodayBrief(
      games: games,
      myTeamId: myTeamId,
      myGame: myGame,
    );

    return RefreshIndicator(
      onRefresh: () async => _invalidateTodayScoreboard(),
      color: AppColors.live,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _buildHeader(context, hasLive)),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: _secondarySectionsEnabled
                  ? Consumer(
                      builder: (context, ref, _) {
                        final yearMonth = DateFormat(
                          'yyyy-MM',
                        ).format(DateTime.now());
                        final season = DateTime.now().year;
                        final scheduleAsync = ref.watch(
                          scheduleProvider(yearMonth),
                        );
                        final standingsAsync = ref.watch(
                          standingsProvider(season),
                        );
                        final myTeamBrief = _buildMyTeamBrief(
                          myTeamId: myTeamId,
                          myGame: myGame,
                          scheduleDays: scheduleAsync.asData?.value ?? const [],
                          standings: standingsAsync.asData?.value ?? const [],
                          today: today,
                        );
                        _logSecondarySectionsLoaded(
                          today: today,
                          brief: myTeamBrief,
                          overview: null,
                        );
                        return _MyTeamBriefCard(
                          myTeamId: myTeamId,
                          brief: myTeamBrief,
                          todayGame: myGame,
                        );
                      },
                    )
                  : const _DeferredSectionCard(
                      title: '마이팀 브리프',
                      subtitle: '홈 첫 화면을 먼저 띄우는 중입니다.',
                    ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: _TodayBaseballCard(brief: todayBrief),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: _secondarySectionsEnabled
                  ? Consumer(
                      builder: (context, ref, _) {
                        final yearMonth = DateFormat(
                          'yyyy-MM',
                        ).format(DateTime.now());
                        final season = DateTime.now().year;
                        final scheduleAsync = ref.watch(
                          scheduleProvider(yearMonth),
                        );
                        final standingsAsync = ref.watch(
                          standingsProvider(season),
                        );
                        final recordsOverviewAsync = ref.watch(
                          recordsOverviewProvider(season),
                        );
                        final myTeamBrief = _buildMyTeamBrief(
                          myTeamId: myTeamId,
                          myGame: myGame,
                          scheduleDays: scheduleAsync.asData?.value ?? const [],
                          standings: standingsAsync.asData?.value ?? const [],
                          today: today,
                        );
                        final quickItems = _buildQuickItems(
                          myTeamBrief: myTeamBrief,
                          overview: recordsOverviewAsync.asData?.value,
                          season: season,
                        );
                        _logSecondarySectionsLoaded(
                          today: today,
                          brief: myTeamBrief,
                          overview: recordsOverviewAsync.asData?.value,
                        );
                        if (quickItems.isEmpty) {
                          return const SizedBox.shrink();
                        }
                        return _QuickContentSection(items: quickItems);
                      },
                    )
                  : const SizedBox.shrink(),
            ),
          ),
          if (myGame != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: MyTeamGameCard(
                  game: myGame,
                  onTap: () =>
                      context.push('/game/${myGame!.gameId}', extra: myGame),
                ),
              ),
            ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
              child: Text(
                games.isEmpty ? '오늘의 스코어보드' : '전체 경기',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          if (games.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    vertical: 32,
                    horizontal: 20,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.divider),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        Icons.sports_baseball,
                        size: 52,
                        color: AppColors.divider,
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        '오늘은 경기가 없습니다',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '대신 리그 리더보드와 마이팀 브리프를 먼저 확인할 수 있습니다.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
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
                return GameCard(
                  game: game,
                  onTap: () =>
                      context.push('/game/${game.gameId}', extra: game),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  _MyTeamBriefData? _buildMyTeamBrief({
    required String? myTeamId,
    required Game? myGame,
    required List<ScheduleDay> scheduleDays,
    required List<TeamStanding> standings,
    required String today,
  }) {
    if (myTeamId == null || myTeamId.isEmpty) {
      return null;
    }

    final standing = standings
        .where((item) => item.teamId == myTeamId)
        .cast<TeamStanding?>()
        .firstOrNull;
    final flatGames = [
      for (final day in scheduleDays)
        for (final game in day.games)
          _ScheduleGameEntry(date: day.date, game: game),
    ]..sort((a, b) => a.date.compareTo(b.date));

    final recentGames =
        flatGames
            .where((entry) => entry.date.compareTo(today) <= 0)
            .where((entry) => _isMyTeamGame(entry.game, myTeamId))
            .where(
              (entry) =>
                  entry.game.awayScore != null && entry.game.homeScore != null,
            )
            .toList()
          ..sort((a, b) => b.date.compareTo(a.date));

    final recentSlice = recentGames.take(3).toList();
    final recentSummaries = <_RecentGameSummaryData>[];
    var wins = 0;
    var losses = 0;
    var draws = 0;
    for (final entry in recentSlice) {
      final isAway = entry.game.awayId == myTeamId;
      final myScore = isAway ? entry.game.awayScore! : entry.game.homeScore!;
      final opponentScore = isAway
          ? entry.game.homeScore!
          : entry.game.awayScore!;
      final opponentName = isAway ? entry.game.homeName : entry.game.awayName;
      late final String resultLabel;
      if (myScore > opponentScore) {
        wins += 1;
        resultLabel = '승';
      } else if (myScore < opponentScore) {
        losses += 1;
        resultLabel = '패';
      } else {
        draws += 1;
        resultLabel = '무';
      }
      recentSummaries.add(
        _RecentGameSummaryData(
          result: resultLabel,
          opponentName: opponentName,
          score: '$myScore:$opponentScore',
        ),
      );
    }

    final nextGame = flatGames
        .where((entry) => entry.date.compareTo(today) >= 0)
        .where((entry) => _isMyTeamGame(entry.game, myTeamId))
        .where((entry) => entry.game.gameId != myGame?.gameId)
        .map((entry) => entry.game)
        .firstOrNull;

    return _MyTeamBriefData(
      teamId: myTeamId,
      teamLabel: KboTeams.byId(myTeamId)?.name ?? myTeamId,
      standing: standing,
      todayGame: myGame,
      nextGame: nextGame,
      recentWins: wins,
      recentLosses: losses,
      recentDraws: draws,
      recentGamesCount: recentSlice.length,
      recentSummaries: recentSummaries,
    );
  }

  _TodayBaseballBriefData _buildTodayBrief({
    required List<Game> games,
    required String? myTeamId,
    required Game? myGame,
  }) {
    final liveGames = games
        .where((game) => game.status == GameStatus.live)
        .length;
    final scheduledGames = games
        .where((game) => game.status == GameStatus.scheduled)
        .length;
    final finalGames = games
        .where((game) => game.status == GameStatus.final_)
        .length;

    final spotlight =
        myGame ??
        games
            .where((game) => game.status == GameStatus.live)
            .cast<Game?>()
            .firstOrNull ??
        games
            .where((game) => game.status == GameStatus.scheduled)
            .cast<Game?>()
            .firstOrNull ??
        games.cast<Game?>().firstOrNull;

    final headline = liveGames > 0
        ? '지금 $liveGames경기 진행 중'
        : games.isEmpty
        ? '오늘은 경기가 없습니다'
        : '오늘 $scheduledGames경기 예정';

    final detail = spotlight == null
        ? '리그 리더보드와 마이팀 브리프로 오늘의 흐름을 확인할 수 있습니다.'
        : myTeamId != null && myGame != null
        ? '마이팀 ${myGame.away.teamId == myTeamId ? myGame.away.shortName : myGame.home.shortName} 경기부터 확인하세요.'
        : '${spotlight.away.shortName} vs ${spotlight.home.shortName} · ${spotlight.stadium}';

    return _TodayBaseballBriefData(
      headline: headline,
      detail: detail,
      totalGames: games.length,
      liveGames: liveGames,
      scheduledGames: scheduledGames,
      finalGames: finalGames,
      spotlight: spotlight,
    );
  }

  List<_QuickContentItemData> _buildQuickItems({
    required _MyTeamBriefData? myTeamBrief,
    required RecordsOverview? overview,
    required int season,
  }) {
    final items = <_QuickContentItemData>[];

    final myTeamGame = myTeamBrief?.todayGame;
    if (myTeamGame != null) {
      items.add(
        _QuickContentItemData(
          eyebrow: '마이팀 경기',
          title:
              '${myTeamGame.away.shortName} ${myTeamGame.away.score} : ${myTeamGame.home.score} ${myTeamGame.home.shortName}',
          subtitle: '${myTeamGame.inning} · ${myTeamGame.stadium}',
          route: '/game/${myTeamGame.gameId}',
        ),
      );
    }

    final ticketGame = myTeamBrief?.nextGame;
    final ticketInfo = ticketGame?.ticketInfo;
    if (ticketGame != null && ticketInfo?.openAt != null) {
      final openAt = ticketInfo!.openAt!;
      final formatted = DateFormat('M.d HH:mm').format(openAt);
      items.add(
        _QuickContentItemData(
          eyebrow: '예매 오픈 임박',
          title: '${ticketGame.awayName} vs ${ticketGame.homeName}',
          subtitle: '${ticketInfo.vendorName} · $formatted',
          route: '/schedule',
        ),
      );
    }

    if (myTeamBrief?.standing != null) {
      final standing = myTeamBrief!.standing!;
      items.add(
        _QuickContentItemData(
          eyebrow: '마이팀 순위',
          title: '${standing.rank}위 · ${standing.teamName}',
          subtitle:
              '${standing.wins}승 ${standing.losses}패 ${standing.draws}무'
              '${standing.gb == '0' ? ' · 공동 선두권' : ' · ${standing.gb}G차'}',
          route: '/standings',
        ),
      );
    }

    final myTeamHighlight = myTeamGame?.highlightInfo;
    if (myTeamBrief != null && myTeamHighlight != null) {
      final firstVideo = myTeamHighlight.youtubeVideos.firstOrNull;
      if (firstVideo != null) {
        items.add(
          _QuickContentItemData(
            eyebrow: '마이팀 하이라이트',
            title: myTeamBrief.teamLabel,
            subtitle: firstVideo.title,
            route: '/game/${myTeamGame!.gameId}',
          ),
        );
      }
    }

    if (overview?.hrLeaders.isNotEmpty == true) {
      final leader = overview!.hrLeaders.first;
      items.add(
        _QuickContentItemData(
          eyebrow: '홈런 리더',
          title: '${leader.name} ${leader.value}개',
          subtitle:
              '${KboTeams.byId(leader.teamId)?.name ?? leader.teamId} · 시즌 홈런 선두',
          route: '/records',
        ),
      );
    }

    if (overview?.todayPlayer.name != null) {
      final player = overview!.todayPlayer;
      final route = player.playerId != null
          ? '/records/player/${player.playerId}?season=$season'
          : '/records';
      items.add(
        _QuickContentItemData(
          eyebrow: player.label,
          title: player.name!,
          subtitle: [
            player.headline,
            player.summary,
          ].whereType<String>().where((value) => value.isNotEmpty).join(' · '),
          route: route,
        ),
      );
    } else if (overview?.avgLeaders.isNotEmpty == true) {
      final leader = overview!.avgLeaders.first;
      items.add(
        _QuickContentItemData(
          eyebrow: '타율 리더',
          title: '${leader.name} ${leader.value}',
          subtitle:
              '${KboTeams.byId(leader.teamId)?.name ?? leader.teamId} · 컨디션 체크',
          route: '/records',
        ),
      );
    }

    return items.take(4).toList();
  }

  bool _isMyTeamGame(ScheduleGame game, String teamId) {
    return game.awayId == teamId || game.homeId == teamId;
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
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'KBO Fans',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 2),
              const Text(
                '마이팀과 오늘 경기 흐름을 한 번에',
                style: TextStyle(fontSize: 12, color: AppColors.textDisabled),
              ),
            ],
          ),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: AppColors.divider),
                ),
                child: Row(
                  children: [
                    Text(
                      dateStr,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    if (hasLive) ...[
                      const SizedBox(width: 8),
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: AppColors.live,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Text(
                        'LIVE',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.live,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
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
    final signature =
        '${games.length}|${games.map((g) => '${g.gameId}:${g.inning}:${g.away.score}:${g.home.score}').join(',')}|$myTeamId';
    if (_lastSyncSignature == signature) {
      return;
    }
    _lastSyncSignature = signature;
    unawaited(
      WidgetSyncService.instance.syncScoreboard(
        games: games,
        myTeamId: myTeamId,
      ),
    );
  }

  void _enableSecondarySections() {
    if (_secondarySectionsEnabled) {
      return;
    }
    _secondarySectionsStartedAtMicros ??= DateTime.now().microsecondsSinceEpoch;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _secondarySectionsEnabled) {
        return;
      }
      setState(() {
        _secondarySectionsEnabled = true;
      });
    });
  }
}

class _DeferredSectionCard extends StatelessWidget {
  final String title;
  final String subtitle;

  const _DeferredSectionCard({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return _sectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _MyTeamBriefCard extends StatelessWidget {
  final String? myTeamId;
  final _MyTeamBriefData? brief;
  final Game? todayGame;

  const _MyTeamBriefCard({
    required this.myTeamId,
    required this.brief,
    required this.todayGame,
  });

  @override
  Widget build(BuildContext context) {
    if (myTeamId == null || myTeamId!.isEmpty) {
      return _sectionCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '마이팀 브리프',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            const Text(
              '응원팀을 선택하면 오늘 경기, 최근 흐름, 순위를 홈에서 바로 보여줍니다.',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => context.go('/onboarding'),
                child: const Text('마이팀 선택하기'),
              ),
            ),
          ],
        ),
      );
    }

    final team = KboTeams.byId(myTeamId!);
    final standing = brief?.standing;
    final nextGame = brief?.nextGame;
    final opponentId = todayGame != null
        ? (todayGame!.away.teamId == myTeamId
              ? todayGame!.home.teamId
              : todayGame!.away.teamId)
        : nextGame != null
        ? (nextGame.awayId == myTeamId ? nextGame.homeId : nextGame.awayId)
        : null;
    final opponent = opponentId != null ? KboTeams.byId(opponentId) : null;

    return _sectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: (team?.primaryColor ?? AppColors.live).withValues(
                    alpha: 0.14,
                  ),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '마이팀 브리프',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: team?.primaryColor ?? AppColors.live,
                  ),
                ),
              ),
              const Spacer(),
              if (standing != null)
                Text(
                  '${standing.rank}위 · ${standing.gb == '0' ? '선두권' : '${standing.gb}G차'}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            team?.name ?? myTeamId!,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            todayGame == null && nextGame == null
                ? '다음 경기 정보가 아직 없습니다.'
                : todayGame != null
                ? '${todayGame!.startTime} · ${todayGame!.stadium} · ${opponent?.name ?? ''}전'
                : '다음 경기 ${nextGame!.time} · ${nextGame.stadium} · ${opponent?.name ?? ''}전',
            style: const TextStyle(
              fontSize: 14,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _metricColumn(
                  '최근 흐름',
                  brief == null || brief!.recentGamesCount == 0
                      ? '최근 경기 없음'
                      : '${brief!.recentWins}승 ${brief!.recentLosses}패 ${brief!.recentDraws}무',
                ),
              ),
              Expanded(
                child: _metricColumn(
                  '현재 순위',
                  standing == null
                      ? '집계 중'
                      : '${standing.rank}위 (${standing.wins}-${standing.losses})',
                ),
              ),
              Expanded(
                child: _metricColumn(
                  todayGame != null ? '오늘 상태' : '다음 일정',
                  todayGame != null
                      ? todayGame!.inning
                      : nextGame == null
                      ? '-'
                      : '${nextGame.time} ${opponent?.shortName ?? ''}전',
                ),
              ),
            ],
          ),
          if (brief != null && brief!.recentSummaries.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Text(
              '최근 3경기',
              style: TextStyle(fontSize: 12, color: AppColors.textDisabled),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final summary in brief!.recentSummaries)
                  _recentGameChip(summary),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    if (todayGame != null) {
                      context.push(
                        '/game/${todayGame!.gameId}',
                        extra: todayGame,
                      );
                    } else {
                      context.go('/schedule');
                    }
                  },
                  child: Text(todayGame != null ? '경기 상세' : '일정 보기'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => context.go('/standings'),
                  child: const Text('순위 보기'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _metricColumn(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: AppColors.textDisabled),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }

  Widget _recentGameChip(_RecentGameSummaryData summary) {
    final color = switch (summary.result) {
      '승' => AppColors.positive,
      '패' => AppColors.live,
      _ => AppColors.accent,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.cardSub,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(999),
            ),
            alignment: Alignment.center,
            child: Text(
              summary.result,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                summary.opponentName,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                summary.score,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TodayBaseballCard extends StatelessWidget {
  final _TodayBaseballBriefData brief;

  const _TodayBaseballCard({required this.brief});

  @override
  Widget build(BuildContext context) {
    return _sectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '오늘의 야구',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          Text(
            brief.headline,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            brief.detail,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
          if (brief.spotlight != null) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.cardSub,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.divider),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      const Text(
                        '주목 경기',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textDisabled,
                        ),
                      ),
                      _gameStatusChip(brief.spotlight!),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${brief.spotlight!.away.shortName} vs ${brief.spotlight!.home.shortName}',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${brief.spotlight!.inning} · ${brief.spotlight!.stadium}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${brief.spotlight!.away.score} : ${brief.spotlight!.home.score}',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerRight,
                    child: OutlinedButton(
                      onPressed: () => context.push(
                        '/game/${brief.spotlight!.gameId}',
                        extra: brief.spotlight,
                      ),
                      child: const Text('바로 보기'),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: _summaryPill('전체', '${brief.totalGames}경기')),
              const SizedBox(width: 8),
              Expanded(child: _summaryPill('LIVE', '${brief.liveGames}경기')),
              const SizedBox(width: 8),
              Expanded(child: _summaryPill('종료', '${brief.finalGames}경기')),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              SizedBox(
                width: 140,
                child: OutlinedButton(
                  onPressed: () => context.go('/schedule'),
                  child: const Text('일정 보기'),
                ),
              ),
              SizedBox(
                width: 140,
                child: ElevatedButton(
                  onPressed: () => context.go('/standings'),
                  child: const Text('순위 보기'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _summaryPill(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.cardSub,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: AppColors.textDisabled),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  Widget _gameStatusChip(Game game) {
    return GameStatusBadge.forGame(
      game.status,
      fontSize: 10,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    );
  }
}

class _QuickContentSection extends StatelessWidget {
  final List<_QuickContentItemData> items;

  const _QuickContentSection({required this.items});

  @override
  Widget build(BuildContext context) {
    return _sectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '빠른 콘텐츠',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final isVeryNarrow = constraints.maxWidth < 340;
              final isCompact = constraints.maxWidth < 420;
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: items.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: isVeryNarrow ? 1 : 2,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  mainAxisExtent: isVeryNarrow
                      ? 176
                      : isCompact
                          ? 220
                          : 204,
                ),
                itemBuilder: (context, index) {
                  final item = items[index];
                  return GestureDetector(
                    onTap: () => context.push(item.route),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.cardSub,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: _quickItemAccent(item).withValues(alpha: 0.32),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 28,
                                height: 28,
                                decoration: BoxDecoration(
                                  color: _quickItemAccent(
                                    item,
                                  ).withValues(alpha: 0.14),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  _quickItemIcon(item),
                                  style: const TextStyle(fontSize: 14),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _quickItemAccent(
                                      item,
                                    ).withValues(alpha: 0.14),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    item.eyebrow,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: _quickItemAccent(item),
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  item.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    height: 1.2,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  item.subtitle,
                                  maxLines: isVeryNarrow ? 2 : 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textSecondary,
                                    height: 1.35,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Text(
                                '바로 확인',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: _quickItemAccent(item),
                                ),
                              ),
                              const Spacer(),
                              const Icon(
                                Icons.chevron_right_rounded,
                                color: AppColors.textDisabled,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }
}

Widget _sectionCard({required Widget child}) {
  return Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppColors.divider),
    ),
    child: child,
  );
}

Color _quickItemAccent(_QuickContentItemData item) {
  final key = item.eyebrow;
  if (key.contains('홈런')) return AppColors.live;
  if (key.contains('예매')) return AppColors.ballYellow;
  if (key.contains('마이팀')) return AppColors.accent;
  if (key.contains('오늘의 플레이어')) return AppColors.positive;
  return AppColors.textSecondary;
}

String _quickItemIcon(_QuickContentItemData item) {
  final key = item.eyebrow;
  if (key.contains('홈런')) return '💥';
  if (key.contains('예매')) return '🎟️';
  if (key.contains('마이팀 경기')) return '⚾';
  if (key.contains('마이팀 하이라이트')) return '🎬';
  if (key.contains('오늘의 플레이어')) return '🔥';
  if (key.contains('순위')) return '📊';
  return '•';
}

class _ScheduleGameEntry {
  final String date;
  final ScheduleGame game;

  const _ScheduleGameEntry({required this.date, required this.game});
}

class _MyTeamBriefData {
  final String teamId;
  final String teamLabel;
  final TeamStanding? standing;
  final Game? todayGame;
  final ScheduleGame? nextGame;
  final int recentWins;
  final int recentLosses;
  final int recentDraws;
  final int recentGamesCount;
  final List<_RecentGameSummaryData> recentSummaries;

  const _MyTeamBriefData({
    required this.teamId,
    required this.teamLabel,
    required this.standing,
    required this.todayGame,
    required this.nextGame,
    required this.recentWins,
    required this.recentLosses,
    required this.recentDraws,
    required this.recentGamesCount,
    required this.recentSummaries,
  });
}

class _RecentGameSummaryData {
  final String result;
  final String opponentName;
  final String score;

  const _RecentGameSummaryData({
    required this.result,
    required this.opponentName,
    required this.score,
  });
}

class _TodayBaseballBriefData {
  final String headline;
  final String detail;
  final int totalGames;
  final int liveGames;
  final int scheduledGames;
  final int finalGames;
  final Game? spotlight;

  const _TodayBaseballBriefData({
    required this.headline,
    required this.detail,
    required this.totalGames,
    required this.liveGames,
    required this.scheduledGames,
    required this.finalGames,
    required this.spotlight,
  });
}

class _QuickContentItemData {
  final String eyebrow;
  final String title;
  final String subtitle;
  final String route;

  const _QuickContentItemData({
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    required this.route,
  });
}
