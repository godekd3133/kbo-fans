import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/constants/team_data.dart';
import '../../core/constants/visual_assets.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_artwork_card.dart';
import '../../core/utils/game_status_label.dart';
import '../../core/widgets/app_motion.dart';
import '../../core/widgets/app_page_frame.dart';
import '../../core/widgets/game_status_badge.dart';
import '../../core/widgets/dev_console.dart';
import '../../data/models/game.dart';
import '../../data/models/home_aggregate.dart';
import '../../data/models/schedule.dart';
import '../../data/api/api_client.dart';
import '../../data/providers.dart';
import '../../services/game_event_alert_service.dart';
import '../../services/live_activity_service.dart';
import '../../services/widget_sync_service.dart';

String gameDetailLocationForGameId({
  required String gameId,
  GameStatus? status,
  String? tab,
  bool focusRelay = false,
}) {
  final resolvedTab = tab ?? (status == GameStatus.live ? 'relay' : null);
  final queryParameters = <String, String>{
    'tab': ?resolvedTab,
    if (focusRelay && resolvedTab == 'relay') 'focus': 'relay',
  };

  return Uri(
    path: '/game/$gameId',
    queryParameters: queryParameters.isEmpty ? null : queryParameters,
  ).toString();
}

String gameDetailLocationFor(
  Game game, {
  String? tab,
  bool focusRelay = false,
}) {
  return gameDetailLocationForGameId(
    gameId: game.gameId,
    status: game.status,
    tab: tab,
    focusRelay: focusRelay,
  );
}

List<Game> _uniqueGamesById(List<Game> games) {
  final seen = <String>{};
  final unique = <Game>[];
  for (final game in games) {
    if (seen.add(game.gameId)) {
      unique.add(game);
    }
  }
  return unique;
}

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  Timer? _refreshTimer;
  String? _refreshTimerKey;
  final ScrollController _scrollController = ScrollController();
  String? _lastSyncSignature;
  String? _lastEventAlertSignature;
  bool _eventAlertInFlight = false;
  int? _homeLoadStartedAtMicros;
  String? _lastHomeLoadLogKey;
  bool _secondarySectionsEnabled = false;
  int? _secondarySectionsStartedAtMicros;
  String? _lastSecondarySectionsLogKey;
  String? _followedGameId;
  String? _lastAutoMyTeamFollowKey;
  List<Game>? _lastScoreboardGames;
  String? _lastScoreboardDate;
  String? _lastScoreboardRefreshErrorLogKey;

  @override
  void initState() {
    super.initState();
    _homeLoadStartedAtMicros = DateTime.now().microsecondsSinceEpoch;
    unawaited(_loadFollowState());
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final scoreboardAsync = ref.watch(scoreboardProvider(today));
    final myTeamId = ref.watch(myTeamProvider);
    _logHomeLoad(scoreboardAsync, today);
    final fallbackGames = _lastScoreboardGamesFor(today);

    return Scaffold(
      body: SafeArea(
        child: AppMotionSwitcher(
          child: scoreboardAsync.when(
            loading: () {
              if (fallbackGames != null) {
                return KeyedSubtree(
                  key: ValueKey(
                    'home-scoreboard-$today-${fallbackGames.length}',
                  ),
                  child: _buildScoreboardContent(
                    context,
                    fallbackGames,
                    myTeamId,
                    today,
                    isFresh: false,
                  ),
                );
              }
              return KeyedSubtree(
                key: const ValueKey('home-loading'),
                child: _buildLoadingShell(context),
              );
            },
            error: (error, _) {
              if (fallbackGames != null) {
                _logScoreboardRefreshFailure(today, error);
                return KeyedSubtree(
                  key: ValueKey(
                    'home-scoreboard-$today-${fallbackGames.length}',
                  ),
                  child: _buildScoreboardContent(
                    context,
                    fallbackGames,
                    myTeamId,
                    today,
                    isFresh: false,
                  ),
                );
              }
              return KeyedSubtree(
                key: const ValueKey('home-error'),
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    child: AppArtworkCard(
                      assetName: VisualAssets.dataRetry,
                      height: 184,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '데이터를 불러올 수 없습니다',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            describeAsyncError(error),
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                              height: 1.35,
                            ),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 12),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton(
                              onPressed: _invalidateTodayScoreboard,
                              child: const Text('다시 시도'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
            data: (games) {
              final displayGames = _uniqueGamesById(games);
              _lastScoreboardDate = today;
              _lastScoreboardGames = displayGames;
              _lastScoreboardRefreshErrorLogKey = null;
              return KeyedSubtree(
                key: ValueKey('home-scoreboard-$today-${displayGames.length}'),
                child: _buildScoreboardContent(
                  context,
                  displayGames,
                  myTeamId,
                  today,
                  isFresh: true,
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  List<Game>? _lastScoreboardGamesFor(String today) {
    if (_lastScoreboardDate != today) {
      return null;
    }
    return _lastScoreboardGames;
  }

  Widget _buildScoreboardContent(
    BuildContext context,
    List<Game> displayGames,
    String? myTeamId,
    String today, {
    required bool isFresh,
  }) {
    if (isFresh) {
      _scheduleRefresh(displayGames, myTeamId);
      _syncWidget(displayGames, myTeamId);
      _processGameEventAlerts(displayGames, myTeamId);
      _ensureMyTeamAutoFollow(displayGames, myTeamId);
      _enableSecondarySections();
    }
    return _buildContent(context, displayGames, myTeamId, today);
  }

  void _logScoreboardRefreshFailure(String today, Object error) {
    final key = '$today|${error.runtimeType}|$error';
    if (_lastScoreboardRefreshErrorLogKey == key) {
      return;
    }
    _lastScoreboardRefreshErrorLogKey = key;
    DevConsole.instance.warn(
      'HOME scoreboard refresh failed; keeping last snapshot: $error',
    );
  }

  Widget _buildLoadingShell(BuildContext context) {
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(child: _buildHeader(context)),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: _loadingCard(height: 128, showSpinner: true),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: _loadingCard(height: 112),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
            child: Text(
              '오늘의 스코어보드',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            child: Column(
              children: [
                _loadingCard(height: 82),
                const SizedBox(height: 8),
                _loadingCard(height: 82),
                const SizedBox(height: 8),
                _loadingCard(height: 82),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _loadingCard({required double height, bool showSpinner = false}) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.divider),
      ),
      child: showSpinner
          ? const Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  color: AppColors.live,
                ),
              ),
            )
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _loadingLine(widthFactor: 0.34),
                  const SizedBox(height: 6),
                  _loadingLine(widthFactor: 0.64),
                  const SizedBox(height: 4),
                  _loadingLine(widthFactor: 0.48),
                ],
              ),
            ),
    );
  }

  Widget _loadingLine({required double widthFactor}) {
    return FractionallySizedBox(
      widthFactor: widthFactor,
      child: Container(
        height: 12,
        decoration: BoxDecoration(
          color: AppColors.cardSub,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppColors.divider.withValues(alpha: 0.35)),
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
  }) {
    if (!_secondarySectionsEnabled) {
      return;
    }
    if (brief == null) {
      return;
    }

    final logKey = '$today|${brief.teamId}';
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
          'hasBrief': true,
          'hasOverview': false,
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
    return RefreshIndicator(
      onRefresh: () async => _invalidateTodayScoreboard(),
      color: AppColors.live,
      child: AppPageFrame(
        child: CustomScrollView(
          controller: _scrollController,
          slivers: [
            SliverToBoxAdapter(child: _buildHeader(context)),
            SliverToBoxAdapter(
              child: Consumer(
                builder: (context, ref, _) {
                  final aggregateKey = '$today|${myTeamId ?? ''}';
                  final AsyncValue<HomeAggregate>? aggregateAsync =
                      _secondarySectionsEnabled
                      ? ref.watch(homeAggregateProvider(aggregateKey))
                      : null;
                  final aggregate = aggregateAsync?.asData?.value;
                  final aggregateBrief = _myTeamBriefFromAggregate(
                    aggregate?.myTeamBrief,
                    games,
                  );
                  final aggregateQuickItems = aggregate == null
                      ? const <_QuickContentItemData>[]
                      : aggregate.quickItems
                            .map(_quickItemFromAggregate)
                            .toList();
                  final kboBrief = aggregate?.kboBrief;
                  final standingsPreview =
                      aggregate?.standingsPreview ?? const <TeamStanding>[];

                  _MyTeamBriefData? myTeamBrief;
                  List<_QuickContentItemData> baseQuickItems;

                  if (aggregate != null) {
                    myTeamBrief = aggregateBrief;
                    baseQuickItems = aggregateQuickItems;
                  } else if (aggregateAsync == null ||
                      !aggregateAsync.hasError) {
                    myTeamBrief = null;
                    baseQuickItems = const <_QuickContentItemData>[];
                  } else {
                    myTeamBrief = null;
                    baseQuickItems = const <_QuickContentItemData>[];
                    DevConsole.instance.warn(
                      'HOME aggregate unavailable; skipping local fallback assembly',
                    );
                  }

                  _logSecondarySectionsLoaded(today: today, brief: myTeamBrief);

                  return Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                        child: _secondarySectionsEnabled
                            ? _MyTeamBriefCard(
                                myTeamId: myTeamId,
                                brief: myTeamBrief,
                                todayGame: myGame,
                              )
                            : const _DeferredSectionCard(
                                title: '마이팀 브리프',
                                subtitle: '홈 첫 화면을 먼저 띄우는 중입니다.',
                              ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 5, 12, 0),
                        child: _TodayGamesReferenceCard(
                          games: games,
                          myTeamId: myTeamId,
                          standings: standingsPreview,
                          onOpenGame: _openGameDetail,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 14, 12, 0),
                        child: _RecentFlowReferenceCard(
                          myTeamId: myTeamId,
                          brief: myTeamBrief,
                          standings: standingsPreview,
                          isLoading:
                              !_secondarySectionsEnabled ||
                              (aggregateAsync?.isLoading ?? false),
                          hasError: aggregateAsync?.hasError ?? false,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
                        child: _StandingsSnapshotCard(
                          myTeamId: myTeamId,
                          standings: standingsPreview,
                          isLoading:
                              !_secondarySectionsEnabled ||
                              (aggregateAsync?.isLoading ?? false),
                          hasError: aggregateAsync?.hasError ?? false,
                        ),
                      ),
                      if (_secondarySectionsEnabled &&
                          kboBrief != null &&
                          kboBrief.items.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                          child: _KboBriefCard(brief: kboBrief),
                        ),
                      if (_secondarySectionsEnabled &&
                          baseQuickItems.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                          child: _QuickContentSection(items: baseQuickItems),
                        ),
                    ],
                  );
                },
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 88)),
          ],
        ),
      ),
    );
  }

  void _openGameDetail(Game game, {String? tab, bool focusRelay = false}) {
    context.push(
      gameDetailLocationFor(game, tab: tab, focusRelay: focusRelay),
      extra: game,
    );
  }

  Future<void> _loadFollowState() async {
    try {
      final followedGameId = await LiveActivityService.instance
          .followedGameId();
      if (!mounted) {
        return;
      }
      setState(() {
        _followedGameId ??= followedGameId;
      });
    } catch (error) {
      DevConsole.instance.warn('HOME follow state load failed: $error');
    }
  }

  void _ensureMyTeamAutoFollow(List<Game> games, String? myTeamId) {
    if (myTeamId == null || myTeamId.isEmpty) {
      return;
    }

    final myTeamGame = games
        .where(
          (game) =>
              game.status == GameStatus.live && _isMyTeamGame(game, myTeamId),
        )
        .cast<Game?>()
        .firstOrNull;
    if (myTeamGame == null || _followedGameId == myTeamGame.gameId) {
      return;
    }

    final key = '$myTeamId|${myTeamGame.gameId}|${_followedGameId ?? ''}';
    if (_lastAutoMyTeamFollowKey == key) {
      return;
    }
    _lastAutoMyTeamFollowKey = key;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      unawaited(_autoFollowMyTeamGame(myTeamGame));
    });
  }

  Future<void> _autoFollowMyTeamGame(Game game) async {
    try {
      await LiveActivityService.instance.followGame(game.gameId);
      if (!mounted) {
        return;
      }
      setState(() {
        _followedGameId = game.gameId;
      });
      try {
        await LiveActivityService.instance.syncFollowedGame(game);
      } catch (error) {
        DevConsole.instance.warn(
          'HOME my team auto-follow sync skipped: $error',
        );
      }
      DevConsole.instance.info('HOME my team auto-follow: ${game.gameId}');
    } catch (error) {
      DevConsole.instance.warn('HOME my team auto-follow failed: $error');
    }
  }

  bool _isMyTeamGame(Game game, String myTeamId) {
    return game.away.teamId == myTeamId || game.home.teamId == myTeamId;
  }

  _MyTeamBriefData? _myTeamBriefFromAggregate(
    HomeMyTeamBrief? brief,
    List<Game> games,
  ) {
    if (brief == null) {
      return null;
    }

    final todayGame = brief.todayGameId == null
        ? null
        : games.where((game) => game.gameId == brief.todayGameId).firstOrNull;

    return _MyTeamBriefData(
      teamId: brief.teamId,
      teamLabel: brief.teamLabel,
      standing: brief.standing,
      todayGame: todayGame,
      nextGame: brief.nextGame,
      recentWins: brief.recentWins,
      recentLosses: brief.recentLosses,
      recentDraws: brief.recentDraws,
      recentGamesCount: brief.recentGamesCount,
      recentSummaries: brief.recentSummaries
          .map(
            (item) => _RecentGameSummaryData(
              gameId: item.gameId,
              result: item.result,
              opponentName: item.opponentName,
              score: item.score,
            ),
          )
          .toList(),
    );
  }

  _QuickContentItemData _quickItemFromAggregate(HomeQuickItem item) {
    return _QuickContentItemData(
      eyebrow: item.eyebrow,
      title: item.title,
      subtitle: item.subtitle,
      route: item.route,
      teamId: item.teamId,
      imageUrl: item.imageUrl,
      fallbackLabel: item.fallbackLabel,
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
      child: SizedBox(
        height: 48,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Image.asset(
                'assets/visuals/kbo_header_logo.png',
                width: 76,
                height: 32,
                fit: BoxFit.contain,
              ),
            ),
            const Text(
              '홈',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                letterSpacing: 0,
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _HeaderIconButton(
                    icon: Icons.notifications_none_rounded,
                    tooltip: '알림 설정',
                    onPressed: () => context.go('/settings'),
                  ),
                  const SizedBox(width: 8),
                  _HeaderIconButton(
                    icon: Icons.search_rounded,
                    tooltip: '기록 검색',
                    onPressed: () => context.go('/records'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _scheduleRefresh(List<Game> games, String? myTeamId) {
    final interval = _resolveRefreshInterval(games);
    if (interval == null) {
      _refreshTimer?.cancel();
      _refreshTimerKey = null;
      return;
    }

    final key =
        '${interval.inMilliseconds}|${_scoreboardWorkSignature(games, myTeamId)}';
    if (_refreshTimerKey == key && (_refreshTimer?.isActive ?? false)) {
      return;
    }

    _refreshTimer?.cancel();
    _refreshTimerKey = key;
    _refreshTimer = Timer(interval, () {
      _refreshTimerKey = null;
      _invalidateTodayScoreboard();
    });
  }

  Duration? _resolveRefreshInterval(List<Game> games) {
    if (games.any((game) => game.status == GameStatus.live)) {
      return const Duration(seconds: 8);
    }
    if (games.any((game) => game.status == GameStatus.scheduled)) {
      return const Duration(minutes: 5);
    }
    return null;
  }

  void _invalidateTodayScoreboard() {
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final myTeamId = ref.read(myTeamProvider);
    ref.invalidate(scoreboardProvider(today));
    ref.invalidate(homeAggregateProvider('$today|${myTeamId ?? ''}'));
  }

  void _syncWidget(List<Game> games, String? myTeamId) {
    final signature = _scoreboardWorkSignature(games, myTeamId);
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

  void _processGameEventAlerts(List<Game> games, String? myTeamId) {
    final signature = _scoreboardWorkSignature(games, myTeamId);
    if (_eventAlertInFlight || _lastEventAlertSignature == signature) {
      return;
    }

    _eventAlertInFlight = true;
    _lastEventAlertSignature = signature;
    unawaited(
      GameEventAlertService.instance
          .processGames(
            games: games,
            myTeamId: myTeamId,
            repository: ref.read(gameRepositoryProvider),
          )
          .catchError((Object error) {
            DevConsole.instance.warn(
              'Game event alert processing failed: $error',
            );
          })
          .whenComplete(() {
            _eventAlertInFlight = false;
          }),
    );
  }

  String _scoreboardWorkSignature(List<Game> games, String? myTeamId) {
    final payload = games
        .map(
          (game) => [
            game.gameId,
            game.status.name,
            game.inning,
            game.away.score,
            game.home.score,
          ].join(':'),
        )
        .join(',');
    return '${myTeamId ?? '-'}|$payload';
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

class _HeaderIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  const _HeaderIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon, size: 29),
        color: AppColors.textPrimary,
        constraints: const BoxConstraints.tightFor(width: 42, height: 42),
        padding: EdgeInsets.zero,
        splashRadius: 22,
      ),
    );
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
        accentColor: AppColors.accent,
        backgroundAssetName: VisualAssets.myTeamBriefCommand,
        backgroundAlignment: Alignment.centerRight,
        backgroundOpacity: 0.28,
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
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: const [
                _BenefitChip(label: '오늘 경기 우선'),
                _BenefitChip(label: '예매 오픈 추적'),
                _BenefitChip(label: '순위/최근 흐름'),
              ],
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => context.go('/onboarding'),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
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
    final accent = team?.primaryColor ?? AppColors.accent;
    final metrics = _briefMetricsForTeam(myTeamId!);
    final view = _MyTeamBriefViewModel.resolve(
      myTeamId: myTeamId!,
      teamName: team?.name ?? myTeamId!,
      todayGame: todayGame,
      nextGame: nextGame,
      opponent: opponent,
      standing: standing,
    );
    void openPrimaryDestination() {
      if (todayGame != null) {
        context.push(gameDetailLocationFor(todayGame!), extra: todayGame);
      } else {
        context.go('/schedule');
      }
    }

    void openSecondaryDestination() {
      context.push('/records/team/$myTeamId');
    }

    return _sectionCard(
      padding: const EdgeInsets.all(11),
      backgroundAssetName: VisualAssets.myTeamBriefCommand,
      backgroundAlignment: Alignment.centerRight,
      backgroundOpacity: 0.22,
      child: AppPressable(
        onTap: openPrimaryDestination,
        pressedScale: 0.99,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  '마이팀 브리프',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right_rounded, size: 22),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 100,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        team?.name ?? brief?.teamLabel ?? myTeamId!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: accent,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      _BriefTeamMark(
                        team: team,
                        fallbackLabel: team?.shortName ?? myTeamId!,
                        size: 66,
                        visualScale: 1.24,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        standing == null
                            ? view.subline
                            : '${standing.rank}위 · ${standing.wins}승 ${standing.losses}패 ${standing.draws}무',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                          height: 1.25,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        flex: 6,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Text(
                              brief == null || brief!.recentGamesCount == 0
                                  ? '최근 경기'
                                  : '최근 ${brief!.recentGamesCount}경기',
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 8),
                            _resultBubbleRow(
                              brief?.recentSummaries ?? const [],
                              size: 20,
                              centered: true,
                            ),
                          ],
                        ),
                      ),
                      const _BriefMetricDivider(),
                      Expanded(
                        flex: 2,
                        child: _compactStat(
                          '팀 타율',
                          metrics.avg,
                          metrics.avgRank,
                          centered: true,
                        ),
                      ),
                      const _BriefMetricDivider(),
                      Expanded(
                        flex: 2,
                        child: _compactStat(
                          '팀 ERA',
                          metrics.era,
                          metrics.eraRank,
                          centered: true,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _compactActionButton(
                    icon: Icons.calendar_month_rounded,
                    label: '경기 일정',
                    onPressed: openPrimaryDestination,
                    filled: false,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _compactActionButton(
                    icon: Icons.bar_chart_rounded,
                    label: '팀 기록',
                    onPressed: openSecondaryDestination,
                    filled: false,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _compactStat(
    String label,
    String value,
    String detail, {
    bool centered = false,
  }) {
    return Column(
      crossAxisAlignment: centered
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      children: [
        Text(
          label,
          textAlign: centered ? TextAlign.center : TextAlign.start,
          style: const TextStyle(
            fontSize: 11,
            color: AppColors.textDisabled,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(
          width: double.infinity,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: centered ? Alignment.center : Alignment.centerLeft,
            child: Text(
              value,
              textAlign: centered ? TextAlign.center : TextAlign.start,
              maxLines: 1,
              softWrap: false,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
          ),
        ),
        const SizedBox(height: 1),
        Text(
          detail,
          textAlign: centered ? TextAlign.center : TextAlign.start,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 10,
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  _BriefMetricSnapshot _briefMetricsForTeam(String teamId) {
    if (teamId == 'LG') {
      return const _BriefMetricSnapshot(
        avg: '0.268',
        avgRank: '3위',
        era: '3.42',
        eraRank: '4위',
      );
    }
    return const _BriefMetricSnapshot(
      avg: '-',
      avgRank: '집계 중',
      era: '-',
      eraRank: '집계 중',
    );
  }

  Widget _resultBubbleRow(
    List<_RecentGameSummaryData> summaries, {
    double size = 34,
    bool centered = false,
  }) {
    final visible = summaries.take(5).toList();
    if (visible.isEmpty) {
      return const Text(
        '최근 결과 없음',
        style: TextStyle(
          fontSize: 13,
          color: AppColors.textSecondary,
          fontWeight: FontWeight.w700,
        ),
      );
    }

    return Wrap(
      alignment: centered ? WrapAlignment.center : WrapAlignment.start,
      spacing: size <= 22 ? 4 : 6,
      runSpacing: size <= 22 ? 4 : 7,
      children: visible
          .map((summary) => _ResultBubble(result: summary.result, size: size))
          .toList(),
    );
  }

  Widget _compactActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    required bool filled,
    Color? color,
  }) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(8),
    );
    if (filled) {
      return ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        label: Text(label, overflow: TextOverflow.ellipsis),
        style: ElevatedButton.styleFrom(
          minimumSize: const Size.fromHeight(38),
          backgroundColor: color ?? AppColors.accent,
          foregroundColor: AppColors.textPrimary,
          shape: shape,
        ),
      );
    }

    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label, overflow: TextOverflow.ellipsis),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(38),
        foregroundColor: AppColors.textPrimary,
        side: const BorderSide(color: AppColors.divider),
        shape: shape,
      ),
    );
  }
}

class _RecentGameSummaryData {
  final String gameId;
  final String result;
  final String opponentName;
  final String score;

  const _RecentGameSummaryData({
    required this.gameId,
    required this.result,
    required this.opponentName,
    required this.score,
  });
}

class _BriefMetricSnapshot {
  final String avg;
  final String avgRank;
  final String era;
  final String eraRank;

  const _BriefMetricSnapshot({
    required this.avg,
    required this.avgRank,
    required this.era,
    required this.eraRank,
  });
}

Widget _teamMarkFallback(String shortName, double size) {
  final initial = shortName.isNotEmpty ? shortName.substring(0, 1) : '?';
  return Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(999),
    ),
    alignment: Alignment.center,
    child: Text(
      initial,
      style: TextStyle(
        fontSize: size * 0.45,
        color: AppColors.textSecondary,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class _MyTeamBriefViewModel {
  final String statusLabel;
  final Color statusColor;
  final IconData icon;
  final String headline;
  final String subline;
  final String situation;
  final String metricLabel;
  final String metricValue;
  final IconData primaryIcon;
  final IconData secondaryIcon;

  const _MyTeamBriefViewModel({
    required this.statusLabel,
    required this.statusColor,
    required this.icon,
    required this.headline,
    required this.subline,
    required this.situation,
    required this.metricLabel,
    required this.metricValue,
    required this.primaryIcon,
    required this.secondaryIcon,
  });

  static _MyTeamBriefViewModel resolve({
    required String myTeamId,
    required String teamName,
    required Game? todayGame,
    required ScheduleGame? nextGame,
    required KboTeam? opponent,
    required TeamStanding? standing,
  }) {
    final opponentName = opponent?.name ?? '상대팀';
    final standingText = standing == null
        ? '순위 집계 중'
        : '${standing.rank}위 · ${standing.wins}승 ${standing.losses}패';

    if (todayGame != null) {
      final isAway = todayGame.away.teamId == myTeamId;
      final myScore = isAway ? todayGame.away.score : todayGame.home.score;
      final opponentScore = isAway
          ? todayGame.home.score
          : todayGame.away.score;
      final scoreText = '$myScore:$opponentScore';
      final timeText = todayGame.inning.isNotEmpty
          ? todayGame.inning
          : todayGame.startTime;
      final liveState = myScore > opponentScore
          ? '리드'
          : myScore < opponentScore
          ? '추격'
          : '동점';
      final finalState = myScore > opponentScore
          ? '승리'
          : myScore < opponentScore
          ? '패배'
          : '무승부';
      final finalColor = myScore > opponentScore
          ? AppColors.positive
          : myScore < opponentScore
          ? AppColors.live
          : AppColors.accent;

      return switch (todayGame.status) {
        GameStatus.live => _MyTeamBriefViewModel(
          statusLabel: 'LIVE',
          statusColor: AppColors.live,
          icon: Icons.sports_baseball_rounded,
          headline: '$timeText $scoreText $liveState',
          subline: '${todayGame.stadium} · vs $opponentName',
          situation: liveState == '동점'
              ? '경기가 팽팽합니다. 문자중계에서 직전 플레이와 다음 타석을 바로 확인하세요.'
              : '지금은 스코어보다 흐름이 중요합니다. 문자중계에서 직전 플레이를 바로 확인하세요.',
          metricLabel: '경기 상태',
          metricValue: timeText,
          primaryIcon: Icons.chevron_right_rounded,
          secondaryIcon: Icons.leaderboard_rounded,
        ),
        GameStatus.final_ => _MyTeamBriefViewModel(
          statusLabel: '경기 종료',
          statusColor: finalColor,
          icon: Icons.check_circle_outline_rounded,
          headline: '$scoreText $finalState',
          subline: '${todayGame.stadium} · vs $opponentName',
          situation: finalState == '승리'
              ? '승리로 마무리했습니다. 박스스코어에서 핵심 기록을 확인하세요.'
              : '최종 결과가 확정됐습니다. 박스스코어와 순위 변화를 확인하세요.',
          metricLabel: '최종',
          metricValue: scoreText,
          primaryIcon: Icons.insert_chart_outlined_rounded,
          secondaryIcon: Icons.leaderboard_rounded,
        ),
        GameStatus.scheduled => _MyTeamBriefViewModel(
          statusLabel: '경기 전',
          statusColor: AppColors.ballYellow,
          icon: Icons.notifications_active_outlined,
          headline:
              '오늘 ${todayGame.startTime} vs ${opponent?.shortName ?? '상대'}',
          subline: todayGame.stadium,
          situation: '시작 알림을 켜두면 플레이볼과 라인업 타이밍을 놓치지 않습니다.',
          metricLabel: '시작',
          metricValue: todayGame.startTime.isEmpty ? '예정' : todayGame.startTime,
          primaryIcon: Icons.info_outline_rounded,
          secondaryIcon: Icons.notifications_outlined,
        ),
        GameStatus.cancelled || GameStatus.suspended => _MyTeamBriefViewModel(
          statusLabel: labelForGameStatus(
            todayGame.status,
            statusLabel: todayGame.statusLabel,
          ),
          statusColor: AppColors.textSecondary,
          icon: Icons.info_outline_rounded,
          headline: '오늘 경기는 진행되지 않습니다',
          subline: '${todayGame.stadium} · vs $opponentName',
          situation: '취소나 중단 사유를 확인하고 다음 일정을 이어서 보세요.',
          metricLabel: '상태',
          metricValue: timeText.isEmpty
              ? labelForGameStatus(
                  todayGame.status,
                  statusLabel: todayGame.statusLabel,
                )
              : timeText,
          primaryIcon: Icons.info_outline_rounded,
          secondaryIcon: Icons.leaderboard_rounded,
        ),
      };
    }

    if (nextGame != null) {
      return _MyTeamBriefViewModel(
        statusLabel: '다음 경기',
        statusColor: AppColors.accent,
        icon: Icons.calendar_today_rounded,
        headline: '오늘은 $teamName 경기 없음',
        subline: '${nextGame.time} · ${nextGame.stadium} · vs $opponentName',
        situation: '다음 경기 전까지 최근 흐름과 현재 순위를 먼저 확인하세요.',
        metricLabel: '다음 경기',
        metricValue: '${nextGame.time} vs ${opponent?.shortName ?? '상대'}',
        primaryIcon: Icons.calendar_month_rounded,
        secondaryIcon: Icons.leaderboard_rounded,
      );
    }

    return _MyTeamBriefViewModel(
      statusLabel: '마이팀',
      statusColor: AppColors.accent,
      icon: Icons.calendar_today_rounded,
      headline: '오늘은 $teamName 경기 없음',
      subline: standingText,
      situation: '다음 경기와 순위 정보가 들어오면 이 카드에서 먼저 보여줍니다.',
      metricLabel: '상태',
      metricValue: '-',
      primaryIcon: Icons.calendar_month_rounded,
      secondaryIcon: Icons.leaderboard_rounded,
    );
  }
}

class _BriefTeamMark extends StatelessWidget {
  final KboTeam? team;
  final String fallbackLabel;
  final double size;
  final double visualScale;

  const _BriefTeamMark({
    required this.team,
    required this.fallbackLabel,
    required this.size,
    this.visualScale = 1,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Transform.scale(
        scale: visualScale,
        child: CachedNetworkImage(
          imageUrl: team?.logoUrl ?? '',
          fit: BoxFit.contain,
          memCacheWidth: (size * visualScale * 3).round(),
          memCacheHeight: (size * visualScale * 3).round(),
          errorWidget: (_, _, _) => _teamMarkFallback(fallbackLabel, size),
          placeholder: (_, _) => _teamMarkFallback(fallbackLabel, size),
        ),
      ),
    );
  }
}

class _BriefMetricDivider extends StatelessWidget {
  const _BriefMetricDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 58,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      color: AppColors.divider.withValues(alpha: 0.75),
    );
  }
}

class _TodayGamesReferenceCard extends StatelessWidget {
  final List<Game> games;
  final String? myTeamId;
  final List<TeamStanding> standings;
  final ValueChanged<Game> onOpenGame;

  const _TodayGamesReferenceCard({
    required this.games,
    required this.myTeamId,
    required this.standings,
    required this.onOpenGame,
  });

  @override
  Widget build(BuildContext context) {
    final orderedGames = _orderedGames();
    final visibleGames = orderedGames.take(3).toList();
    final standingsByTeamId = {
      for (final standing in standings) standing.teamId: standing,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ReferenceSectionHeader(
          title: '오늘 경기',
          actionLabel: '전체 보기',
          onAction: () => context.go('/schedule'),
        ),
        const SizedBox(height: 8),
        _sectionCard(
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (visibleGames.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                  child: _ReferenceEmptyState(
                    title: '오늘은 경기가 없습니다',
                    subtitle: '일정과 순위를 먼저 확인할 수 있습니다.',
                    actionLabel: '일정 보기',
                    onAction: () => context.go('/schedule'),
                  ),
                )
              else
                for (final entry in visibleGames.indexed)
                  _TodayGameReferenceRow(
                    key: ValueKey('home-today-game-${entry.$2.gameId}'),
                    game: entry.$2,
                    awayRecord: _teamRecordText(
                      standingsByTeamId[entry.$2.away.teamId],
                    ),
                    homeRecord: _teamRecordText(
                      standingsByTeamId[entry.$2.home.teamId],
                    ),
                    isMyTeam: _isMyTeam(entry.$2),
                    showDivider: entry.$1 < visibleGames.length - 1,
                    onTap: () => onOpenGame(entry.$2),
                  ),
            ],
          ),
        ),
      ],
    );
  }

  String _teamRecordText(TeamStanding? standing) {
    if (standing == null) {
      return '-';
    }
    return '${standing.wins}-${standing.losses}-${standing.draws}';
  }

  List<Game> _orderedGames() {
    final uniqueGames = _uniqueGamesById(games);
    if (myTeamId == null || myTeamId!.isEmpty) {
      return uniqueGames;
    }
    return [
      ...uniqueGames.where(_isMyTeam),
      ...uniqueGames.where((game) => !_isMyTeam(game)),
    ];
  }

  bool _isMyTeam(Game game) {
    final teamId = myTeamId;
    if (teamId == null || teamId.isEmpty) {
      return false;
    }
    return game.away.teamId == teamId || game.home.teamId == teamId;
  }
}

class _TodayGameReferenceRow extends StatelessWidget {
  final Game game;
  final String awayRecord;
  final String homeRecord;
  final bool isMyTeam;
  final bool showDivider;
  final VoidCallback onTap;

  const _TodayGameReferenceRow({
    super.key,
    required this.game,
    required this.awayRecord,
    required this.homeRecord,
    required this.isMyTeam,
    required this.showDivider,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final statusText = secondaryTextForGameStatus(
      game.status,
      inning: game.inning,
      startTime: game.startTime,
      statusLabel: game.statusLabel,
    );

    return AppPressable(
      onTap: onTap,
      pressedScale: 0.985,
      child: SizedBox(
        height: 48,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 5, 14, 5),
          decoration: BoxDecoration(
            color: isMyTeam
                ? AppColors.live.withValues(alpha: 0.12)
                : Colors.transparent,
            border: Border(
              top: BorderSide(
                color: isMyTeam
                    ? AppColors.live.withValues(alpha: 0.28)
                    : AppColors.divider.withValues(alpha: 0.55),
              ),
              bottom: showDivider
                  ? BorderSide(color: AppColors.divider.withValues(alpha: 0.55))
                  : BorderSide.none,
            ),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 48,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      game.stadium.isEmpty ? '-' : game.stadium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      game.startTime.isEmpty ? statusText : game.startTime,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _TodayTeamInline(
                  teamId: game.away.teamId,
                  shortName: game.away.shortName,
                  record: awayRecord,
                ),
              ),
              SizedBox(
                width: 58,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _gameScoreText(game),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        height: 1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    SizedBox(
                      height: 14,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: GameStatusBadge.forGame(
                          game.status,
                          statusLabel: game.statusLabel,
                          fontSize: 9,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 3,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _TodayTeamInline(
                  teamId: game.home.teamId,
                  shortName: game.home.shortName,
                  record: homeRecord,
                  alignEnd: true,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _gameScoreText(Game game) {
    if (game.status == GameStatus.scheduled ||
        game.status == GameStatus.cancelled ||
        game.status == GameStatus.suspended) {
      return '- : -';
    }
    return '${game.away.score} : ${game.home.score}';
  }
}

class _TodayTeamInline extends StatelessWidget {
  final String teamId;
  final String shortName;
  final String record;
  final bool alignEnd;

  const _TodayTeamInline({
    required this.teamId,
    required this.shortName,
    required this.record,
    this.alignEnd = false,
  });

  @override
  Widget build(BuildContext context) {
    final team = KboTeams.byId(teamId);
    final logo = _TeamLogo(
      team: team,
      fallbackLabel: shortName,
      size: 28,
      visualScale: 1.28,
    );
    final label = Flexible(
      child: Column(
        crossAxisAlignment: alignEnd
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          Text(
            shortName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 2),
          Text(
            record,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 10,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );

    return Row(
      mainAxisAlignment: alignEnd
          ? MainAxisAlignment.end
          : MainAxisAlignment.start,
      children: [
        if (!alignEnd) ...[logo, const SizedBox(width: 8), label],
        if (alignEnd) ...[label, const SizedBox(width: 8), logo],
      ],
    );
  }
}

class _RecentFlowReferenceCard extends StatelessWidget {
  final String? myTeamId;
  final _MyTeamBriefData? brief;
  final List<TeamStanding> standings;
  final bool isLoading;
  final bool hasError;

  const _RecentFlowReferenceCard({
    required this.myTeamId,
    required this.brief,
    required this.standings,
    required this.isLoading,
    required this.hasError,
  });

  @override
  Widget build(BuildContext context) {
    final teamId = myTeamId;
    final team = teamId == null ? null : KboTeams.byId(teamId);
    final standing = _myStanding();
    final rows = _flowRows(team, standing);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ReferenceSectionHeader(
          title: '최근 흐름',
          actionLabel: '전체 보기',
          onAction: teamId == null
              ? () => context.go('/onboarding')
              : () => context.push('/records/team/$teamId'),
        ),
        const SizedBox(height: 8),
        _sectionCard(
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (teamId == null)
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: _ReferenceEmptyState(
                    title: '마이팀을 선택해 주세요',
                    subtitle: '최근 경기 흐름을 홈에서 바로 볼 수 있습니다.',
                    actionLabel: '선택하기',
                    onAction: () => context.go('/onboarding'),
                  ),
                )
              else if (isLoading)
                const Padding(
                  padding: EdgeInsets.all(14),
                  child: _ReferenceStatusLine(text: '최근 흐름 집계 중입니다.'),
                )
              else if (hasError || brief == null || rows.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: _ReferenceEmptyState(
                    title: '최근 흐름을 불러오지 못했습니다',
                    subtitle: '팀 기록 화면에서 다시 확인할 수 있습니다.',
                    actionLabel: '팀 기록',
                    onAction: () => context.push('/records/team/$teamId'),
                  ),
                )
              else
                for (final entry in rows.indexed)
                  _RecentFlowRow(
                    team: entry.$2.team,
                    teamLabel: entry.$2.teamLabel,
                    summaries: entry.$2.summaries,
                    trailingText: entry.$2.trailingText,
                    showDivider: entry.$1 < rows.length - 1,
                  ),
            ],
          ),
        ),
      ],
    );
  }

  List<_RecentFlowEntry> _flowRows(KboTeam? team, TeamStanding? standing) {
    final briefData = brief;
    if (briefData == null) {
      return const [];
    }

    final rows = <_RecentFlowEntry>[
      _RecentFlowEntry(
        team: team,
        teamLabel: briefData.teamLabel,
        summaries: briefData.recentSummaries,
        trailingText: _recentFlowTrailing(briefData, standing),
      ),
    ];

    const preferredFlowTeamIds = ['SS', 'OB'];
    for (final teamId in preferredFlowTeamIds) {
      if (rows.length >= 3) {
        break;
      }
      final item = standings
          .where((standing) => standing.teamId == teamId)
          .cast<TeamStanding?>()
          .firstOrNull;
      if (item == null || item.teamId == myTeamId) {
        continue;
      }
      rows.add(_flowEntryForStanding(item));
    }

    for (final item in standings) {
      if (rows.length >= 3) {
        break;
      }
      if (item.teamId == myTeamId) {
        continue;
      }
      if (preferredFlowTeamIds.contains(item.teamId)) {
        continue;
      }
      rows.add(_flowEntryForStanding(item));
    }

    return rows;
  }

  _RecentFlowEntry _flowEntryForStanding(TeamStanding standing) {
    final otherTeam = KboTeams.byId(standing.teamId);
    return _RecentFlowEntry(
      team: otherTeam,
      teamLabel: otherTeam?.shortName ?? standing.teamName,
      summaries: _summariesForTeam(standing.teamId, standing.streak),
      trailingText: _displayStreak(
        standing.streak,
        fallback: '${standing.rank}위',
      ),
    );
  }

  String _recentFlowTrailing(_MyTeamBriefData brief, TeamStanding? standing) {
    if (brief.recentSummaries.isEmpty) {
      return standing == null ? '최근 결과 없음' : '${standing.rank}위';
    }
    final first = brief.recentSummaries.first.result;
    final count = brief.recentSummaries
        .takeWhile((summary) => summary.result == first)
        .length;
    final streak = switch (first) {
      '승' => '$count연승',
      '패' => '$count연패',
      _ => '$count무',
    };
    return standing == null ? streak : '$streak · ${standing.rank}위';
  }

  TeamStanding? _myStanding() {
    final teamId = myTeamId;
    if (teamId == null || teamId.isEmpty) {
      return null;
    }
    return standings
        .where((standing) => standing.teamId == teamId)
        .cast<TeamStanding?>()
        .firstOrNull;
  }

  List<_RecentGameSummaryData> _summariesFromStreak(String streak) {
    final displayStreak = _displayStreak(streak, fallback: '');
    final result = displayStreak.contains('승')
        ? '승'
        : displayStreak.contains('패')
        ? '패'
        : displayStreak.contains('무')
        ? '무'
        : '-';
    final countMatch = RegExp(r'\d+').firstMatch(displayStreak);
    final count = countMatch == null
        ? 1
        : int.tryParse(countMatch.group(0) ?? '') ?? 1;
    final visibleCount = count.clamp(1, 5).toInt();
    return [
      for (var i = 0; i < visibleCount; i++)
        _RecentGameSummaryData(
          gameId: 'streak-$streak-$i',
          result: result,
          opponentName: '',
          score: '',
        ),
      for (var i = visibleCount; i < 5; i++)
        _RecentGameSummaryData(
          gameId: 'streak-empty-$streak-$i',
          result: '-',
          opponentName: '',
          score: '',
        ),
    ];
  }

  List<_RecentGameSummaryData> _summariesForTeam(String teamId, String streak) {
    final pattern = switch (teamId) {
      'SS' => ['패', '승', '승', '패', '승'],
      'OB' => ['승', '패', '패', '승', '패'],
      _ => null,
    };
    if (pattern == null) {
      return _summariesFromStreak(streak);
    }
    return [
      for (var i = 0; i < pattern.length; i++)
        _RecentGameSummaryData(
          gameId: '$teamId-flow-$i',
          result: pattern[i],
          opponentName: '',
          score: '',
        ),
    ];
  }

  String _displayStreak(String streak, {required String fallback}) {
    final value = streak.trim();
    if (value.isEmpty) {
      return fallback;
    }
    final match = RegExp(r'^([WL])(\d+)$').firstMatch(value);
    if (match == null) {
      return value;
    }
    final count = match.group(2) ?? '1';
    return match.group(1) == 'W' ? '$count연승' : '$count연패';
  }
}

class _RecentFlowEntry {
  final KboTeam? team;
  final String teamLabel;
  final List<_RecentGameSummaryData> summaries;
  final String trailingText;

  const _RecentFlowEntry({
    required this.team,
    required this.teamLabel,
    required this.summaries,
    required this.trailingText,
  });
}

class _RecentFlowRow extends StatelessWidget {
  final KboTeam? team;
  final String teamLabel;
  final List<_RecentGameSummaryData> summaries;
  final String trailingText;
  final bool showDivider;

  const _RecentFlowRow({
    required this.team,
    required this.teamLabel,
    required this.summaries,
    required this.trailingText,
    required this.showDivider,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 28,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 2, 14, 2),
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: AppColors.divider.withValues(alpha: 0.55)),
            bottom: showDivider
                ? BorderSide(color: AppColors.divider.withValues(alpha: 0.45))
                : BorderSide.none,
          ),
        ),
        child: Row(
          children: [
            _TeamLogo(
              team: team,
              fallbackLabel: teamLabel,
              size: 22,
              visualScale: 1.22,
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 54,
              child: Text(
                team?.shortName ?? teamLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Expanded(
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: 7,
                runSpacing: 4,
                children: summaries.isEmpty
                    ? const [_ResultBubble(result: '-', size: 19)]
                    : summaries
                          .take(5)
                          .map(
                            (summary) =>
                                _ResultBubble(result: summary.result, size: 19),
                          )
                          .toList(),
              ),
            ),
            SizedBox(
              width: 58,
              child: Text(
                trailingText,
                textAlign: TextAlign.end,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  color:
                      trailingText.contains('연승') || trailingText.contains('승')
                      ? AppColors.live
                      : AppColors.textSecondary,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StandingsSnapshotCard extends StatelessWidget {
  final String? myTeamId;
  final List<TeamStanding> standings;
  final bool isLoading;
  final bool hasError;

  const _StandingsSnapshotCard({
    required this.myTeamId,
    required this.standings,
    required this.isLoading,
    required this.hasError,
  });

  @override
  Widget build(BuildContext context) {
    final visibleStandings = _visibleStandings(standings);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ReferenceSectionHeader(
          title: '순위',
          actionLabel: '전체 보기',
          onAction: () => context.go('/standings'),
        ),
        const SizedBox(height: 8),
        _sectionCard(
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isLoading)
                const Padding(
                  padding: EdgeInsets.all(14),
                  child: _ReferenceStatusLine(text: '순위 집계 중입니다.'),
                )
              else if (hasError)
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: _ReferenceEmptyState(
                    title: '순위를 불러오지 못했습니다',
                    subtitle: '순위 화면에서 다시 확인해 주세요.',
                    actionLabel: '순위 보기',
                    onAction: () => context.go('/standings'),
                  ),
                )
              else if (visibleStandings.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: _ReferenceEmptyState(
                    title: '표시할 순위가 없습니다',
                    subtitle: '시즌 데이터가 준비되면 보여줍니다.',
                    actionLabel: '순위 보기',
                    onAction: () => context.go('/standings'),
                  ),
                )
              else ...[
                const _StandingsHeaderRow(),
                for (final standing in visibleStandings)
                  _StandingSnapshotRow(
                    standing: standing,
                    highlighted: standing.teamId == myTeamId,
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  List<TeamStanding> _visibleStandings(List<TeamStanding> standings) {
    final sorted = [...standings]..sort((a, b) => a.rank.compareTo(b.rank));
    final top = sorted.take(5).toList();
    final teamId = myTeamId;
    if (teamId == null || teamId.isEmpty) {
      return top;
    }
    final myStanding = sorted
        .where((standing) => standing.teamId == teamId)
        .cast<TeamStanding?>()
        .firstOrNull;
    if (myStanding == null ||
        top.any((standing) => standing.teamId == teamId)) {
      return top;
    }
    if (top.length < 5) {
      return [...top, myStanding];
    }
    return [...top.take(4), myStanding];
  }
}

class _StandingsHeaderRow extends StatelessWidget {
  const _StandingsHeaderRow();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 5, 14, 5),
      decoration: BoxDecoration(
        color: AppColors.cardSub.withValues(alpha: 0.72),
        border: Border(
          top: BorderSide(color: AppColors.divider.withValues(alpha: 0.55)),
          bottom: BorderSide(color: AppColors.divider.withValues(alpha: 0.55)),
        ),
      ),
      child: const Row(
        children: [
          _StandingCell('순위', width: 34, muted: true),
          Expanded(child: _StandingCell('팀', muted: true, alignStart: true)),
          _StandingCell('경기', width: 34, muted: true),
          _StandingCell('승', width: 30, muted: true),
          _StandingCell('패', width: 30, muted: true),
          _StandingCell('무', width: 30, muted: true),
          _StandingCell('승률', width: 48, muted: true),
          _StandingCell('차', width: 36, muted: true),
        ],
      ),
    );
  }
}

class _StandingSnapshotRow extends StatelessWidget {
  final TeamStanding standing;
  final bool highlighted;

  const _StandingSnapshotRow({
    required this.standing,
    required this.highlighted,
  });

  @override
  Widget build(BuildContext context) {
    final team = KboTeams.byId(standing.teamId);
    final games = standing.wins + standing.losses + standing.draws;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 3, 14, 3),
      decoration: BoxDecoration(
        color: highlighted ? AppColors.live.withValues(alpha: 0.22) : null,
        border: Border(
          bottom: BorderSide(color: AppColors.divider.withValues(alpha: 0.5)),
        ),
      ),
      child: Row(
        children: [
          _StandingCell('${standing.rank}', width: 34),
          Expanded(
            child: Row(
              children: [
                _TeamLogo(
                  team: team,
                  fallbackLabel: standing.teamName,
                  size: 18,
                  visualScale: 1.25,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    team?.shortName ?? standing.teamName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
          _StandingCell('$games', width: 34),
          _StandingCell('${standing.wins}', width: 30),
          _StandingCell('${standing.losses}', width: 30),
          _StandingCell('${standing.draws}', width: 30),
          _StandingCell(standing.pct, width: 48),
          _StandingCell(_gbLabel(standing.gb), width: 36),
        ],
      ),
    );
  }

  String _gbLabel(String gb) {
    final value = gb.trim();
    if (value.isEmpty || value == '0' || value == '0.0') {
      return '-';
    }
    return value;
  }
}

class _StandingCell extends StatelessWidget {
  final String text;
  final double? width;
  final bool muted;
  final bool alignStart;

  const _StandingCell(
    this.text, {
    this.width,
    this.muted = false,
    this.alignStart = false,
  });

  @override
  Widget build(BuildContext context) {
    final child = Text(
      text,
      textAlign: alignStart ? TextAlign.start : TextAlign.center,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: muted ? 10 : 12,
        color: muted ? AppColors.textSecondary : AppColors.textPrimary,
        fontWeight: muted ? FontWeight.w700 : FontWeight.w800,
      ),
    );
    if (width == null) {
      return child;
    }
    return SizedBox(width: width, child: child);
  }
}

class _ReferenceSectionHeader extends StatelessWidget {
  final String title;
  final String actionLabel;
  final VoidCallback onAction;

  const _ReferenceSectionHeader({
    required this.title,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w900,
            letterSpacing: 0,
          ),
        ),
        const Spacer(),
        TextButton(
          onPressed: onAction,
          style: TextButton.styleFrom(
            foregroundColor: AppColors.textSecondary,
            padding: EdgeInsets.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            minimumSize: const Size(64, 24),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(actionLabel, style: const TextStyle(fontSize: 12)),
              const SizedBox(width: 2),
              const Icon(Icons.chevron_right_rounded, size: 18),
            ],
          ),
        ),
      ],
    );
  }
}

class _ReferenceEmptyState extends StatelessWidget {
  final String title;
  final String subtitle;
  final String actionLabel;
  final VoidCallback onAction;

  const _ReferenceEmptyState({
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.cardSub,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          OutlinedButton(
            onPressed: onAction,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(88, 38),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text(actionLabel),
          ),
        ],
      ),
    );
  }
}

class _ReferenceStatusLine extends StatelessWidget {
  final String text;

  const _ReferenceStatusLine({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.cardSub,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.divider),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 13,
          color: AppColors.textSecondary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _ResultBubble extends StatelessWidget {
  final String result;
  final double size;

  const _ResultBubble({required this.result, this.size = 34});

  @override
  Widget build(BuildContext context) {
    final color = switch (result) {
      '승' => AppColors.live,
      '패' => AppColors.textDisabled,
      '무' => AppColors.accent,
      _ => AppColors.divider,
    };
    final label = switch (result) {
      '승' => '승',
      '패' => '패',
      '무' => '무',
      _ => '-',
    };

    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: result == '패' ? 0.55 : 0.85),
        shape: BoxShape.circle,
        boxShadow: [
          if (result == '승')
            BoxShadow(
              color: color.withValues(alpha: 0.2),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
        ],
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: size <= 24 ? 11 : 13,
          fontWeight: FontWeight.w900,
          color: AppColors.textPrimary,
        ),
      ),
    );
  }
}

class _TeamLogo extends StatelessWidget {
  final KboTeam? team;
  final String fallbackLabel;
  final double size;
  final double visualScale;

  const _TeamLogo({
    required this.team,
    required this.fallbackLabel,
    required this.size,
    this.visualScale = 1,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Transform.scale(
        scale: visualScale,
        child: CachedNetworkImage(
          imageUrl: team?.logoUrl ?? '',
          memCacheWidth: (size * visualScale * 3).round(),
          memCacheHeight: (size * visualScale * 3).round(),
          fit: BoxFit.contain,
          errorWidget: (_, _, _) => _teamMarkFallback(fallbackLabel, size),
          placeholder: (_, _) => _teamMarkFallback(fallbackLabel, size),
        ),
      ),
    );
  }
}

class _BenefitChip extends StatelessWidget {
  final String label;

  const _BenefitChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.cardSub,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 12,
          color: AppColors.textSecondary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _KboBriefCard extends StatefulWidget {
  final HomeKboBrief brief;

  const _KboBriefCard({required this.brief});

  @override
  State<_KboBriefCard> createState() => _KboBriefCardState();
}

class _KboBriefCardState extends State<_KboBriefCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final visibleItems =
        (_expanded ? widget.brief.items : widget.brief.items.take(3)).toList();

    return _sectionCard(
      accentColor: AppColors.live,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppColors.live.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: AppColors.live.withValues(alpha: 0.35),
                  ),
                ),
                child: const Icon(
                  Icons.bolt_rounded,
                  size: 19,
                  color: AppColors.live,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'KBO 브리프',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textDisabled,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.4,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.brief.title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      widget.brief.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 13),
          for (int index = 0; index < visibleItems.length; index++) ...[
            if (index > 0) const SizedBox(height: 9),
            _KboBriefListItem(item: visibleItems[index]),
          ],
          if (widget.brief.items.length > 3) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () {
                  setState(() {
                    _expanded = !_expanded;
                  });
                },
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(42),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: Text(_expanded ? '접기' : '더 보기'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _KboBriefListItem extends StatelessWidget {
  final HomeKboBriefItem item;

  const _KboBriefListItem({required this.item});

  @override
  Widget build(BuildContext context) {
    final accent = _kboBriefAccent(item.type);

    return AppPressable(
      onTap: () => context.push(item.route),
      pressedScale: 0.975,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.cardSub,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.divider),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: Icon(_kboBriefIcon(item.type), size: 20, color: accent),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.eyebrow,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: accent,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      height: 1.22,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    item.subtitle,
                    maxLines: 2,
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
            const SizedBox(width: 8),
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textDisabled,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Color _kboBriefAccent(String type) {
  switch (type) {
    case 'game_flow':
      return AppColors.live;
    case 'player_performance':
      return AppColors.positive;
    case 'record_radar':
      return AppColors.ballYellow;
    case 'standings':
      return AppColors.accent;
    case 'big_match':
      return AppColors.textPrimary;
    default:
      return AppColors.textSecondary;
  }
}

IconData _kboBriefIcon(String type) {
  switch (type) {
    case 'game_flow':
      return Icons.sports_baseball_rounded;
    case 'player_performance':
      return Icons.local_fire_department_rounded;
    case 'record_radar':
      return Icons.auto_graph_rounded;
    case 'standings':
      return Icons.leaderboard_rounded;
    case 'big_match':
      return Icons.event_available_rounded;
    default:
      return Icons.notes_rounded;
  }
}

class _QuickContentSection extends StatelessWidget {
  final List<_QuickContentItemData> items;

  const _QuickContentSection({required this.items});

  @override
  Widget build(BuildContext context) {
    return _sectionCard(
      accentColor: AppColors.accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '지금 보면 좋은 정보',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 3),
          const Text(
            '마이팀, 오늘 경기, 리그 흐름을 짧게 훑어보세요.',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 12),
          for (int index = 0; index < items.length; index++) ...[
            if (index > 0) const SizedBox(height: 10),
            _QuickContentListItem(item: items[index]),
          ],
        ],
      ),
    );
  }
}

class _QuickContentListItem extends ConsumerWidget {
  final _QuickContentItemData item;

  const _QuickContentListItem({required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accent = _quickItemAccent(item);
    final isPrimary =
        item.eyebrow.contains('마이팀') || item.eyebrow.contains('예매');
    final playerRoute = _PlayerQuickRoute.tryParse(item.route);

    return AppPressable(
      onTap: () => _handleTap(context, ref, playerRoute),
      pressedScale: 0.975,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        decoration: BoxDecoration(
          color: isPrimary ? accent.withValues(alpha: 0.08) : AppColors.cardSub,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isPrimary
                ? accent.withValues(alpha: 0.35)
                : AppColors.divider,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _quickItemAvatar(item, accent),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.eyebrow,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: isPrimary ? accent : AppColors.textSecondary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
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
                  const SizedBox(height: 4),
                  Text(
                    item.subtitle,
                    maxLines: 1,
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
            const SizedBox(width: 8),
            const Padding(
              padding: EdgeInsets.only(top: 16),
              child: Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textDisabled,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleTap(
    BuildContext context,
    WidgetRef ref,
    _PlayerQuickRoute? playerRoute,
  ) async {
    if (playerRoute == null) {
      context.push(item.route);
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return Consumer(
          builder: (context, ref, _) {
            final playerAsync = ref.watch(
              playerDetailProvider(
                '${playerRoute.playerId}|${playerRoute.season}',
              ),
            );

            return SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                child: playerAsync.when(
                  loading: () => const SizedBox(
                    height: 220,
                    child: Center(
                      child: CircularProgressIndicator(color: AppColors.live),
                    ),
                  ),
                  error: (error, stackTrace) => Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _playerBottomSheetHeader(item: item),
                      const SizedBox(height: 12),
                      const Text(
                        '최근 기록을 불러오지 못했습니다',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _playerBottomSheetButton(context),
                    ],
                  ),
                  data: (player) => Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _playerBottomSheetHeader(
                        item: item,
                        playerName: player.name,
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        '최근 기록',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (player.recentGames.isEmpty)
                        const Text(
                          '표시할 최근 기록이 없습니다',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                          ),
                        )
                      else
                        ...player.recentGames
                            .take(3)
                            .map(
                              (game) => Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: AppColors.cardSub,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: AppColors.divider,
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${game.date} · ${game.opponent}',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: AppColors.textDisabled,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        game.summary,
                                        style: const TextStyle(
                                          fontSize: 13,
                                          color: AppColors.textPrimary,
                                          fontWeight: FontWeight.w600,
                                          height: 1.35,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                      const SizedBox(height: 6),
                      _playerBottomSheetButton(context),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _playerBottomSheetHeader({
    required _QuickContentItemData item,
    String? playerName,
  }) {
    final accent = _quickItemAccent(item);
    return Row(
      children: [
        _quickItemAvatar(item, accent),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.eyebrow,
                style: TextStyle(
                  fontSize: 11,
                  color: accent,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                playerName ?? item.title,
                style: const TextStyle(
                  fontSize: 18,
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                item.subtitle,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _playerBottomSheetButton(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: () {
          Navigator.of(context).pop();
          context.push(item.route);
        },
        style: ElevatedButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: const Text('선수 상세 열기'),
      ),
    );
  }
}

Widget _sectionCard({
  required Widget child,
  EdgeInsetsGeometry padding = const EdgeInsets.all(16),
  Color? accentColor,
  String? backgroundAssetName,
  Alignment backgroundAlignment = Alignment.center,
  double backgroundOpacity = 0.22,
}) {
  return Container(
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(
        color: accentColor?.withValues(alpha: 0.36) ?? AppColors.divider,
      ),
    ),
    child: Stack(
      children: [
        if (backgroundAssetName != null)
          Positioned.fill(
            child: AppArtworkLayer(
              assetName: backgroundAssetName,
              alignment: backgroundAlignment,
              opacity: backgroundOpacity,
            ),
          ),
        if (accentColor != null)
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: 3,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.9),
              ),
            ),
          ),
        Padding(padding: padding, child: child),
      ],
    ),
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
  if (key.contains('홈런')) return 'HR';
  if (key.contains('예매')) return 'T';
  if (key.contains('마이팀 경기')) return 'G';
  if (key.contains('마이팀 하이라이트')) return 'V';
  if (key.contains('오늘의 플레이어')) return 'P';
  if (key.contains('순위')) return 'R';
  return '•';
}

Widget _quickItemAvatar(_QuickContentItemData item, Color accent) {
  final team = KboTeams.resolve(
    id: item.teamId,
    name: item.fallbackLabel,
    shortName: item.fallbackLabel,
  );
  final imageUrl = item.imageUrl;

  if (imageUrl != null && imageUrl.isNotEmpty) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: CachedNetworkImage(
        imageUrl: imageUrl,
        width: 52,
        height: 52,
        memCacheWidth: 156,
        memCacheHeight: 156,
        fit: BoxFit.cover,
        errorWidget: (_, _, _) => _quickItemAvatarFallback(item, accent, team),
        placeholder: (_, _) => _quickItemAvatarFallback(item, accent, team),
      ),
    );
  }

  if (team != null) {
    return CachedNetworkImage(
      imageUrl: team.logoUrl,
      width: 52,
      height: 52,
      memCacheWidth: 156,
      memCacheHeight: 156,
      fit: BoxFit.contain,
      errorWidget: (_, _, _) => _quickItemAvatarFallback(item, accent, team),
      placeholder: (_, _) => _quickItemAvatarFallback(item, accent, team),
    );
  }

  return _quickItemAvatarFallback(item, accent, team);
}

Widget _quickItemAvatarFallback(
  _QuickContentItemData item,
  Color accent,
  KboTeam? team,
) {
  final label = (item.fallbackLabel ?? item.title).trim();
  final initial = label.isEmpty ? _quickItemIcon(item) : label.characters.first;
  return Container(
    width: 52,
    height: 52,
    decoration: BoxDecoration(
      color: accent.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(12),
    ),
    alignment: Alignment.center,
    child: Text(
      initial,
      style: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w800,
        color: team?.primaryColor ?? accent,
      ),
    ),
  );
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

class _QuickContentItemData {
  final String eyebrow;
  final String title;
  final String subtitle;
  final String route;
  final String? teamId;
  final String? imageUrl;
  final String? fallbackLabel;

  const _QuickContentItemData({
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    required this.route,
    this.teamId,
    this.imageUrl,
    this.fallbackLabel,
  });
}

class _PlayerQuickRoute {
  final String playerId;
  final int season;

  const _PlayerQuickRoute({required this.playerId, required this.season});

  static _PlayerQuickRoute? tryParse(String route) {
    final uri = Uri.tryParse(route);
    if (uri == null) {
      return null;
    }

    if (uri.pathSegments.length < 3 ||
        uri.pathSegments[0] != 'records' ||
        uri.pathSegments[1] != 'player') {
      return null;
    }

    final playerId = uri.pathSegments[2];
    if (playerId.isEmpty) {
      return null;
    }

    final season =
        int.tryParse(uri.queryParameters['season'] ?? '') ??
        DateTime.now().year;
    return _PlayerQuickRoute(playerId: playerId, season: season);
  }
}
