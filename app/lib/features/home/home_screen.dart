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
import '../../services/push_notification_service.dart';
import '../../services/widget_sync_service.dart';
import 'widgets/game_card.dart';
import 'widgets/my_team_game_card.dart';

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
  bool _followStateLoaded = false;
  bool _followActionInFlight = false;
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
        SliverToBoxAdapter(child: _buildHeader(context, false)),
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
    final others = _uniqueGamesById(
      myGame != null
          ? games.where((g) => g.gameId != myGame!.gameId).toList()
          : games,
    );
    final hasLive = games.any((g) => g.status == GameStatus.live);
    final todayBrief = _buildTodayBrief(
      games: games,
      myTeamId: myTeamId,
      myGame: myGame,
    );
    final selectedMyGame = myGame;

    return RefreshIndicator(
      onRefresh: () async => _invalidateTodayScoreboard(),
      color: AppColors.live,
      child: AppPageFrame(
        child: CustomScrollView(
          controller: _scrollController,
          slivers: [
            SliverToBoxAdapter(child: _buildHeader(context, hasLive)),
            if (selectedMyGame != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: MyTeamGameCard(
                    game: selectedMyGame,
                    isFollowing: _followedGameId == selectedMyGame.gameId,
                    isFollowLoading:
                        !_followStateLoaded || _followActionInFlight,
                    onOpenDetail: () => _openGameDetail(selectedMyGame),
                    onOpenRelay: () => _openGameDetail(
                      selectedMyGame,
                      tab: 'relay',
                      focusRelay: true,
                    ),
                    onFollowGame: () =>
                        unawaited(_followGameFromHome(selectedMyGame)),
                    onOpenAlert: () {
                      if (selectedMyGame.status == GameStatus.scheduled) {
                        context.go('/settings');
                        return;
                      }
                      _openGameDetail(selectedMyGame);
                    },
                  ),
                ),
              ),
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

                  _MyTeamBriefData? myTeamBrief;
                  List<_QuickContentItemData> baseQuickItems;
                  var useAggregate = false;

                  if (aggregate != null) {
                    myTeamBrief = aggregateBrief;
                    baseQuickItems = aggregateQuickItems;
                    useAggregate = true;
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
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
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
                      if (_secondarySectionsEnabled &&
                          kboBrief != null &&
                          kboBrief.items.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                          child: _KboBriefCard(brief: kboBrief),
                        ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                        child: _TodayBaseballCard(brief: todayBrief),
                      ),
                      if (_secondarySectionsEnabled &&
                          baseQuickItems.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                          child: _QuickContentSection(items: baseQuickItems),
                        ),
                      if (!_secondarySectionsEnabled && !useAggregate)
                        const SizedBox.shrink(),
                    ],
                  );
                },
              ),
            ),
            if (games.isEmpty || others.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: Text(
                    games.isEmpty
                        ? '오늘의 스코어보드'
                        : myGame != null
                        ? '다른 경기'
                        : '전체 경기',
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
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.divider),
                    ),
                    child: Column(
                      children: [
                        const AppArtworkCard(
                          assetName: VisualAssets.homeEmptyStadium,
                          height: 128,
                        ),
                        const SizedBox(height: 16),
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
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () => context.go('/schedule'),
                                icon: const Icon(
                                  Icons.calendar_month_rounded,
                                  size: 16,
                                ),
                                label: const Text('일정 보기'),
                                style: OutlinedButton.styleFrom(
                                  minimumSize: const Size.fromHeight(44),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () => context.go('/records'),
                                icon: const Icon(
                                  Icons.leaderboard_rounded,
                                  size: 16,
                                ),
                                label: const Text('기록실'),
                                style: ElevatedButton.styleFrom(
                                  minimumSize: const Size.fromHeight(44),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
              sliver: SliverList.separated(
                itemCount: others.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final game = others[index];
                  return AppMotionListItem(
                    key: ValueKey('home-game-motion-${game.gameId}-$index'),
                    index: index,
                    child: KeyedSubtree(
                      key: ValueKey('home-game-${game.gameId}'),
                      child: GameCard(
                        game: game,
                        onTap: () => _openGameDetail(game),
                      ),
                    ),
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
        _followStateLoaded = true;
      });
    } catch (error) {
      DevConsole.instance.warn('HOME follow state load failed: $error');
      if (!mounted) {
        return;
      }
      setState(() {
        _followStateLoaded = true;
      });
    }
  }

  Future<void> _followGameFromHome(Game game) async {
    if (_followActionInFlight || game.status != GameStatus.live) {
      return;
    }

    setState(() {
      _followActionInFlight = true;
    });

    try {
      await LiveActivityService.instance.followGame(game.gameId);
      if (!mounted) {
        return;
      }
      setState(() {
        _followedGameId = game.gameId;
        _followStateLoaded = true;
      });

      try {
        await LiveActivityService.instance.requestPermissions();
        await GameEventAlertService.instance.requestPermissions();
        await PushNotificationService.instance.requestPermissionAndSync(
          myTeam: ref.read(myTeamProvider),
        );
        await LiveActivityService.instance.syncFollowedGame(game);
      } catch (error) {
        DevConsole.instance.warn('HOME follow surface sync skipped: $error');
      }

      if (!mounted) {
        return;
      }
      setState(() {
        _followActionInFlight = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('마이팀 경기를 따라가는 중입니다')));
    } catch (error) {
      DevConsole.instance.warn('HOME follow game failed: $error');
      if (!mounted) {
        return;
      }
      setState(() {
        _followStateLoaded = true;
        _followActionInFlight = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('경기 따라가기 설정에 실패했습니다')));
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
        _followStateLoaded = true;
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
      if (!mounted) {
        return;
      }
      setState(() {
        _followStateLoaded = true;
      });
    }
  }

  bool _isMyTeamGame(Game game, String myTeamId) {
    return game.away.teamId == myTeamId || game.home.teamId == myTeamId;
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

  Widget _buildHeader(BuildContext context, bool hasLive) {
    final now = DateTime.now();
    final dateStr =
        '${(now.year % 100).toString().padLeft(2, '0')}.${now.month}.${now.day}';
    final myTeamId = ref.watch(myTeamProvider);
    final myTeam = myTeamId == null ? null : KboTeams.byId(myTeamId);
    final title = myTeam == null ? '오늘 경기' : '${myTeam.shortName} 오늘 경기';

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '마이팀',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textDisabled,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  title,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontSize: 23,
                    height: 1.05,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text(
                      '오늘 $dateStr',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (hasLive) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.live.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: AppColors.live.withValues(alpha: 0.45),
                          ),
                        ),
                        child: const Text(
                          '경기 중',
                          style: TextStyle(
                            fontSize: 10,
                            color: AppColors.live,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _HeaderTeamMark(team: myTeam),
        ],
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

class _HeaderTeamMark extends StatelessWidget {
  final KboTeam? team;

  const _HeaderTeamMark({required this.team});

  @override
  Widget build(BuildContext context) {
    final borderColor = team?.primaryColor ?? AppColors.divider;
    return Container(
      width: 44,
      height: 44,
      padding: const EdgeInsets.all(7),
      decoration: BoxDecoration(
        color: AppColors.surface,
        shape: BoxShape.circle,
        border: Border.all(color: borderColor.withValues(alpha: 0.58)),
      ),
      child: team == null
          ? const Icon(
              Icons.sports_baseball_rounded,
              size: 20,
              color: AppColors.textSecondary,
            )
          : CachedNetworkImage(
              imageUrl: team!.logoUrl,
              memCacheWidth: 90,
              memCacheHeight: 90,
              fit: BoxFit.contain,
              errorWidget: (_, _, _) => _teamMarkFallback(team!.shortName, 30),
              placeholder: (_, _) => _teamMarkFallback(team!.shortName, 30),
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
    final primaryLabel = todayGame == null
        ? '일정 보기'
        : switch (todayGame!.status) {
            GameStatus.live => '중계 보기',
            GameStatus.final_ => '경기 기록',
            _ => '경기 상세',
          };
    final secondaryLabel = todayGame?.status == GameStatus.scheduled
        ? '알림 설정'
        : '순위 보기';
    final accent = team?.primaryColor ?? AppColors.accent;
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
      if (todayGame?.status == GameStatus.scheduled) {
        context.go('/settings');
        return;
      }
      context.go('/standings');
    }

    return _sectionCard(
      padding: const EdgeInsets.all(14),
      accentColor: accent,
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
                _BriefStatusPill(
                  label: view.statusLabel,
                  color: view.statusColor,
                ),
                const Spacer(),
                if (standing != null)
                  Text(
                    _standingMeta(standing),
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _BriefTeamMark(
                  team: team,
                  fallbackLabel: team?.shortName ?? myTeamId!,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '마이팀 브리프',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textDisabled,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        view.headline,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 20,
                          height: 1.18,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        view.subline,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: view.statusColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: view.statusColor.withValues(alpha: 0.24),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(view.icon, size: 18, color: view.statusColor),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      view.situation,
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.35,
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _metricColumn(
                    '최근 3경기',
                    brief == null || brief!.recentGamesCount == 0
                        ? '최근 결과 없음'
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
                  child: _metricColumn(view.metricLabel, view.metricValue),
                ),
              ],
            ),
            if (brief != null && brief!.recentSummaries.isNotEmpty) ...[
              const SizedBox(height: 10),
              const Text(
                '최근 3경기',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              SizedBox(
                height: 44,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: brief!.recentSummaries.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, index) =>
                      _recentGameChip(context, brief!.recentSummaries[index]),
                ),
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: openPrimaryDestination,
                    icon: Icon(view.primaryIcon, size: 18),
                    label: Text(primaryLabel, overflow: TextOverflow.ellipsis),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size.fromHeight(44),
                      backgroundColor: accent,
                      foregroundColor: AppColors.textPrimary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: openSecondaryDestination,
                    icon: Icon(view.secondaryIcon, size: 17),
                    label: Text(
                      secondaryLabel,
                      overflow: TextOverflow.ellipsis,
                    ),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(44),
                      foregroundColor: AppColors.textPrimary,
                      side: const BorderSide(color: AppColors.divider),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
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
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }

  String _standingMeta(TeamStanding standing) {
    final gb = standing.gb.trim();
    final gapText = gb == '0' || gb == '0.0' ? '선두권' : '${standing.gb}G차';
    return '${standing.rank}위 · $gapText';
  }

  Widget _recentGameChip(BuildContext context, _RecentGameSummaryData summary) {
    final color = switch (summary.result) {
      '승' => AppColors.positive,
      '패' => AppColors.live,
      _ => AppColors.accent,
    };
    final team = KboTeams.resolve(
      id: null,
      name: summary.opponentName,
      shortName: summary.opponentName,
    );
    final symbol = switch (summary.result) {
      '승' => 'W',
      '패' => 'L',
      _ => 'D',
    };

    return AppPressable(
      onTap: () => context.push('/game/${summary.gameId}'),
      pressedScale: 0.96,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.cardSub,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.divider),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CachedNetworkImage(
              imageUrl: team?.logoUrl ?? '',
              width: 26,
              height: 26,
              memCacheWidth: 78,
              memCacheHeight: 78,
              fit: BoxFit.contain,
              errorWidget: (_, _, _) =>
                  _teamMarkFallback(summary.opponentName, 26),
              placeholder: (_, _) =>
                  _teamMarkFallback(summary.opponentName, 26),
            ),
            const SizedBox(width: 8),
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(999),
              ),
              alignment: Alignment.center,
              child: Text(
                symbol,
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

class _BriefStatusPill extends StatelessWidget {
  final String label;
  final Color color;

  const _BriefStatusPill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.36)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w900,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
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

  const _BriefTeamMark({required this.team, required this.fallbackLabel});

  @override
  Widget build(BuildContext context) {
    final color = team?.primaryColor ?? AppColors.accent;
    return Container(
      width: 50,
      height: 50,
      padding: const EdgeInsets.all(7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.36)),
      ),
      child: CachedNetworkImage(
        imageUrl: team?.logoUrl ?? '',
        fit: BoxFit.contain,
        memCacheWidth: 150,
        memCacheHeight: 150,
        errorWidget: (_, _, _) => _teamMarkFallback(fallbackLabel, 36),
        placeholder: (_, _) => _teamMarkFallback(fallbackLabel, 36),
      ),
    );
  }
}

class _TodayBaseballCard extends StatelessWidget {
  final _TodayBaseballBriefData brief;

  const _TodayBaseballCard({required this.brief});

  @override
  Widget build(BuildContext context) {
    final spotlight = brief.spotlight;
    final accentTeam = spotlight == null
        ? null
        : KboTeams.byId(spotlight.away.teamId) ??
              KboTeams.byId(spotlight.home.teamId);

    return _sectionCard(
      accentColor: accentTeam?.primaryColor ?? AppColors.live,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '오늘의 야구',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          if (spotlight != null) ...[
            _spotlightMatchupCard(context, spotlight),
            const SizedBox(height: 12),
          ],
          const SizedBox(height: 2),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              SizedBox(
                width: 140,
                child: OutlinedButton(
                  onPressed: () => context.go('/schedule'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(46),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text('일정 보기'),
                ),
              ),
              SizedBox(
                width: 140,
                child: ElevatedButton(
                  onPressed: () => context.go('/standings'),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size.fromHeight(46),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text('순위 보기'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _spotlightMatchupCard(BuildContext context, Game game) {
    return AppPressable(
      key: ValueKey('today-spotlight-game-${game.gameId}'),
      onTap: () => context.push(gameDetailLocationFor(game), extra: game),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.cardSub,
          borderRadius: BorderRadius.circular(8),
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
                  '마이팀',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                _gameStatusChip(game),
                _metaPill(game.stadium),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _todayTeamBlock(
                    game.away.teamId,
                    game.away.shortName,
                    score: game.away.score,
                    alignEnd: false,
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10),
                  child: Text(
                    ':',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textDisabled,
                    ),
                  ),
                ),
                Expanded(
                  child: _todayTeamBlock(
                    game.home.teamId,
                    game.home.shortName,
                    score: game.home.score,
                    alignEnd: true,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              secondaryTextForGameStatus(
                game.status,
                inning: game.inning,
                startTime: game.startTime,
                statusLabel: game.statusLabel,
              ),
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _todayTeamBlock(
    String teamId,
    String shortName, {
    required int score,
    required bool alignEnd,
  }) {
    final team = KboTeams.byId(teamId);
    final logo = CachedNetworkImage(
      imageUrl: team?.logoUrl ?? '',
      width: 34,
      height: 34,
      memCacheWidth: 102,
      memCacheHeight: 102,
      fit: BoxFit.contain,
      errorWidget: (_, _, _) => _teamMarkFallback(shortName, 34),
      placeholder: (_, _) => _teamMarkFallback(shortName, 34),
    );

    return Row(
      mainAxisAlignment: alignEnd
          ? MainAxisAlignment.end
          : MainAxisAlignment.start,
      children: [
        if (!alignEnd) ...[logo, const SizedBox(width: 8)],
        Column(
          crossAxisAlignment: alignEnd
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            Text(
              shortName,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
            ),
            Text(
              '$score',
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
            ),
          ],
        ),
        if (alignEnd) ...[const SizedBox(width: 8), logo],
      ],
    );
  }

  Widget _gameStatusChip(Game game) {
    return GameStatusBadge.forGame(
      game.status,
      statusLabel: game.statusLabel,
      fontSize: 10,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    );
  }

  Widget _metaPill(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.background.withValues(alpha: 0.34),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.divider),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 11,
          color: AppColors.textSecondary,
          fontWeight: FontWeight.w600,
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
