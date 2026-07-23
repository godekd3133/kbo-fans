import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import '../../core/constants/team_data.dart';
import '../../core/constants/visual_assets.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/game_status_label.dart';
import '../../core/widgets/app_artwork_card.dart';
import '../../core/widgets/app_motion.dart';
import '../../core/widgets/app_page_frame.dart';
import '../../core/widgets/dev_console.dart';
import '../../core/widgets/kbo_team_logo_image.dart';
import '../../data/models/game.dart';
import '../../data/models/highlight_info.dart';
import '../../data/models/highlight_video.dart';
import '../../data/providers.dart';
import '../../data/repositories/game_repository.dart';
import '../../services/game_event_alert_service.dart';
import '../../services/live_activity_service.dart';
import '../../services/push_notification_service.dart';
import '../../services/ticket_alert_service.dart';
import 'tabs/boxscore_tab.dart';
import 'tabs/lineup_tab.dart';
import 'tabs/relay_tab.dart';
import 'tabs/score_tab.dart';

const gameDetailLiveRelayRefreshInterval = Duration(seconds: 5);
const gameDetailLiveDefaultRefreshInterval = Duration(seconds: 8);
const gameDetailScheduledRefreshInterval = Duration(minutes: 5);
const _relayTabIndex = 1;

@visibleForTesting
double gameDetailRelayFocusScrollTarget(double maxScrollExtent) {
  if (maxScrollExtent <= kTextTabBarHeight) {
    return 0;
  }
  return maxScrollExtent - kTextTabBarHeight;
}

@visibleForTesting
Duration? gameDetailRefreshIntervalFor(
  GameStatus status, {
  required int selectedTabIndex,
}) {
  return switch (status) {
    GameStatus.live =>
      selectedTabIndex == _relayTabIndex
          ? gameDetailLiveRelayRefreshInterval
          : gameDetailLiveDefaultRefreshInterval,
    GameStatus.scheduled => gameDetailScheduledRefreshInterval,
    GameStatus.final_ => null,
    GameStatus.cancelled => null,
    GameStatus.suspended => null,
  };
}

const _stadiumFullNameMap = {
  '잠실': '서울종합운동장 야구장',
  '문학': '인천 SSG랜더스필드',
  '대구': '대구삼성 라이온즈파크',
  '창원': '창원NC파크',
  '대전': '대전 한화생명 볼파크',
  '광주': '광주-기아 챔피언스 필드',
  '수원': '수원KT위즈파크',
  '사직': '사직야구장',
  '고척': '고척스카이돔',
};

String _displayStadiumName(String stadium) {
  return _stadiumFullNameMap[stadium] ?? stadium;
}

class GameDetailScreen extends ConsumerStatefulWidget {
  final String gameId;
  final Game? game;
  final String? initialTab;
  final bool focusRelay;

  const GameDetailScreen({
    super.key,
    required this.gameId,
    this.game,
    this.initialTab,
    this.focusRelay = false,
  });

  @override
  ConsumerState<GameDetailScreen> createState() => _GameDetailScreenState();
}

class _GameDetailScreenState extends ConsumerState<GameDetailScreen> {
  Game? _lastResolvedGame;
  bool _refreshDelayed = false;

  @override
  void initState() {
    super.initState();
    _lastResolvedGame = widget.game;
  }

  @override
  void didUpdateWidget(covariant GameDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.gameId != widget.gameId) {
      _lastResolvedGame = widget.game;
      _refreshDelayed = false;
      return;
    }
    _lastResolvedGame ??= widget.game;
  }

  void _handleRefreshSucceeded() {
    if (!mounted || !_refreshDelayed) {
      return;
    }
    setState(() {
      _refreshDelayed = false;
    });
  }

  void _handleRefreshFailed() {
    if (!mounted || _refreshDelayed) {
      return;
    }
    setState(() {
      _refreshDelayed = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final gameAsync = ref.watch(gameProvider(widget.gameId));
    final fallbackGame =
        gameAsync.asData?.value ?? _lastResolvedGame ?? widget.game;

    return AppMotionSwitcher(
      child: gameAsync.when(
        loading: () {
          if (fallbackGame != null) {
            return KeyedSubtree(
              key: ValueKey('game-detail-preview-${widget.gameId}'),
              child: _GameDetailBody(
                game: fallbackGame,
                gameId: widget.gameId,
                initialTabIndex: _tabIndexFromName(widget.initialTab),
                focusInitialRelay: widget.focusRelay,
                refreshDelayed: _refreshDelayed,
                onRefreshSucceeded: _handleRefreshSucceeded,
                onRefreshFailed: _handleRefreshFailed,
              ),
            );
          }
          return KeyedSubtree(
            key: ValueKey('game-detail-loading'),
            child: Scaffold(
              body: SafeArea(
                child: Center(
                  child: CircularProgressIndicator(color: AppColors.live),
                ),
              ),
            ),
          );
        },
        error: (_, _) => KeyedSubtree(
          key: ValueKey('game-detail-error-${widget.gameId}'),
          child: fallbackGame != null
              ? _GameDetailBody(
                  game: fallbackGame,
                  gameId: widget.gameId,
                  initialTabIndex: _tabIndexFromName(widget.initialTab),
                  focusInitialRelay: widget.focusRelay,
                  refreshDelayed: true,
                  onRefreshSucceeded: _handleRefreshSucceeded,
                  onRefreshFailed: _handleRefreshFailed,
                )
              : Scaffold(
                  appBar: AppBar(title: const Text('경기 상세')),
                  body: const Center(child: Text('경기를 불러올 수 없습니다')),
                ),
        ),
        data: (loadedGame) {
          final resolvedGame = loadedGame ?? fallbackGame;
          if (resolvedGame != null) {
            _lastResolvedGame = resolvedGame;
          }
          if (resolvedGame == null) {
            return KeyedSubtree(
              key: ValueKey('game-detail-missing-${widget.gameId}'),
              child: Scaffold(
                appBar: AppBar(title: const Text('경기 상세')),
                body: const Center(child: Text('경기를 찾을 수 없습니다')),
              ),
            );
          }

          return KeyedSubtree(
            key: ValueKey(
              'game-detail-data-${widget.gameId}-${resolvedGame.status}',
            ),
            child: _GameDetailBody(
              game: resolvedGame,
              gameId: widget.gameId,
              initialTabIndex: _tabIndexFromName(widget.initialTab),
              focusInitialRelay: widget.focusRelay,
              refreshDelayed: _refreshDelayed,
              onRefreshSucceeded: _handleRefreshSucceeded,
              onRefreshFailed: _handleRefreshFailed,
            ),
          );
        },
      ),
    );
  }
}

class _GameDetailBody extends ConsumerStatefulWidget {
  final String gameId;
  final Game game;
  final int initialTabIndex;
  final bool focusInitialRelay;
  final bool refreshDelayed;
  final VoidCallback onRefreshSucceeded;
  final VoidCallback onRefreshFailed;

  const _GameDetailBody({
    required this.gameId,
    required this.game,
    this.initialTabIndex = 0,
    this.focusInitialRelay = false,
    required this.refreshDelayed,
    required this.onRefreshSucceeded,
    required this.onRefreshFailed,
  });

  @override
  ConsumerState<_GameDetailBody> createState() => _GameDetailBodyState();
}

class _GameDetailBodyState extends ConsumerState<_GameDetailBody>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  Timer? _refreshTimer;
  Duration? _refreshTimerInterval;
  bool _refreshInFlight = false;
  bool _refreshPending = false;
  bool _refreshPendingForceNetwork = false;
  Completer<void>? _refreshCompleter;
  bool _followStateLoaded = false;
  bool _isFollowingGame = false;
  String? _highlightWarmupGameId;
  late final TabController _tabController;
  final ScrollController _outerScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tabController = TabController(
      length: 4,
      initialIndex: widget.initialTabIndex.clamp(0, 3),
      vsync: this,
    );
    _tabController.addListener(_handleTabChanged);
    if (widget.focusInitialRelay && _tabController.index == _relayTabIndex) {
      _scheduleRelayFocusScroll();
    }
    unawaited(_loadFollowState());
    _startRefreshTimer();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _warmHighlightInfoForFinalGame();
  }

  @override
  void didUpdateWidget(covariant _GameDetailBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.gameId != widget.gameId ||
        oldWidget.game.status != widget.game.status) {
      _refreshTimer?.cancel();
      _startRefreshTimer();
      unawaited(_loadFollowState());
    }
    _warmHighlightInfoForFinalGame();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startRefreshTimer();
      unawaited(_refreshGameDetail(queueIfBusy: true));
      return;
    }

    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      _refreshTimer?.cancel();
    }
  }

  void _startRefreshTimer() {
    final interval = gameDetailRefreshIntervalFor(
      widget.game.status,
      selectedTabIndex: _tabController.index,
    );
    if (_refreshTimerInterval == interval &&
        (_refreshTimer?.isActive ?? false)) {
      return;
    }

    _refreshTimer?.cancel();
    _refreshTimerInterval = interval;
    if (interval == null) {
      return;
    }
    _refreshTimer = Timer(interval, () {
      unawaited(_runScheduledRefresh());
    });
  }

  Future<void> _runScheduledRefresh() async {
    if (!mounted) {
      return;
    }
    if (ModalRoute.of(context)?.isCurrent == true) {
      await _refreshGameDetail(queueIfBusy: false);
    }
    if (!mounted) {
      return;
    }
    _refreshTimer = null;
    _startRefreshTimer();
  }

  void _handleTabChanged() {
    if (_tabController.indexIsChanging) {
      return;
    }
    _startRefreshTimer();
    if (widget.game.status == GameStatus.live) {
      unawaited(_refreshGameDetail(queueIfBusy: true));
    }
  }

  Future<void> _refreshGameDetail({
    bool userInitiated = false,
    bool queueIfBusy = true,
  }) async {
    return _refreshGameDetailProviders(
      refreshVisibleTab: true,
      userInitiated: userInitiated,
      queueIfBusy: queueIfBusy,
    );
  }

  void _warmHighlightInfoForFinalGame() {
    if (widget.game.status != GameStatus.final_) {
      _highlightWarmupGameId = null;
      return;
    }
    if (_highlightWarmupGameId == widget.gameId) {
      return;
    }
    if (widget.game.highlightInfo?.youtubeVideos.isNotEmpty == true) {
      _highlightWarmupGameId = widget.gameId;
      return;
    }

    _highlightWarmupGameId = widget.gameId;
    final gameId = widget.gameId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _highlightWarmupGameId != gameId) {
        return;
      }
      unawaited(
        ref.read(highlightInfoProvider(gameId).future).catchError((
          Object error,
          StackTrace stackTrace,
        ) {
          DevConsole.instance.warn(
            'GAME DETAIL highlight warmup skipped: $error',
          );
          return null;
        }),
      );
    });
  }

  Future<void> _refreshGameDetailProviders({
    required bool refreshVisibleTab,
    required bool userInitiated,
    required bool queueIfBusy,
  }) {
    if (_refreshInFlight) {
      if (queueIfBusy) {
        _refreshPending = true;
        _refreshPendingForceNetwork =
            _refreshPendingForceNetwork || userInitiated;
      }
      return _refreshCompleter?.future ?? Future<void>.value();
    }

    if (!userInitiated &&
        _hasActiveRefreshProvider(
          widget.gameId,
          refreshVisibleTab: refreshVisibleTab,
        )) {
      return _awaitActiveRefreshProviders(
        widget.gameId,
        refreshVisibleTab: refreshVisibleTab,
      );
    }

    _refreshInFlight = true;
    final completer = Completer<void>();
    _refreshCompleter = completer;
    unawaited(
      _drainGameDetailRefreshes(
        refreshVisibleTab: refreshVisibleTab,
        waitForActiveProviders: userInitiated,
        forceNetwork: userInitiated,
        completer: completer,
      ),
    );
    return completer.future;
  }

  Future<void> _drainGameDetailRefreshes({
    required bool refreshVisibleTab,
    required bool waitForActiveProviders,
    required bool forceNetwork,
    required Completer<void> completer,
  }) async {
    try {
      if (waitForActiveProviders) {
        await _awaitActiveRefreshProviders(
          widget.gameId,
          refreshVisibleTab: refreshVisibleTab,
        );
      }

      var forceNextRefresh = forceNetwork;
      do {
        _refreshPending = false;
        await _performGameDetailRefresh(
          refreshVisibleTab: refreshVisibleTab,
          forceNetwork: forceNextRefresh,
        );
        forceNextRefresh = _refreshPendingForceNetwork;
        _refreshPendingForceNetwork = false;
      } while (_refreshPending && mounted);
    } finally {
      _refreshInFlight = false;
      _refreshPending = false;
      _refreshPendingForceNetwork = false;
      if (identical(_refreshCompleter, completer)) {
        _refreshCompleter = null;
      }
      if (!completer.isCompleted) {
        completer.complete();
      }
    }
  }

  Future<void> _performGameDetailRefresh({
    required bool refreshVisibleTab,
    required bool forceNetwork,
  }) async {
    final gameId = widget.gameId;

    try {
      final repository = ref.read(gameRepositoryProvider);
      if (forceNetwork && repository is GameRepositoryRefreshControl) {
        final refreshControl = repository as GameRepositoryRefreshControl;
        refreshControl.requestGameRefresh(gameId);
        if (refreshVisibleTab && _tabController.index == _relayTabIndex) {
          refreshControl.requestRelayRefresh(gameId);
        }
      }
      ref.invalidate(gameProvider(gameId));
      final futures = <Future<Object?>>[ref.read(gameProvider(gameId).future)];

      if (refreshVisibleTab) {
        switch (_tabController.index) {
          case 0:
            if (widget.game.status == GameStatus.final_) {
              ref.invalidate(highlightInfoProvider(gameId));
              futures.add(ref.read(highlightInfoProvider(gameId).future));
            }
            break;
          case 1:
            ref.invalidate(relayDataProvider(gameId));
            futures.add(ref.read(relayDataProvider(gameId).future));
            break;
          case 2:
            ref.invalidate(gameBoxscoreProvider(gameId));
            futures.add(ref.read(gameBoxscoreProvider(gameId).future));
            break;
          case 3:
            ref.invalidate(gameLineupProvider(gameId));
            futures.add(ref.read(gameLineupProvider(gameId).future));
            break;
        }
      }

      await Future.wait(futures).timeout(const Duration(seconds: 25));
      widget.onRefreshSucceeded();
    } catch (error) {
      widget.onRefreshFailed();
      DevConsole.instance.warn('GAME DETAIL refresh skipped: $error');
    }
  }

  bool _hasActiveRefreshProvider(
    String gameId, {
    required bool refreshVisibleTab,
  }) {
    if (ref.read(gameProvider(gameId)).isLoading) {
      return true;
    }
    if (!refreshVisibleTab) {
      return false;
    }
    return switch (_tabController.index) {
      1 => ref.read(relayDataProvider(gameId)).isLoading,
      2 => ref.read(gameBoxscoreProvider(gameId)).isLoading,
      3 => ref.read(gameLineupProvider(gameId)).isLoading,
      _ => false,
    };
  }

  Future<void> _awaitActiveRefreshProviders(
    String gameId, {
    required bool refreshVisibleTab,
  }) async {
    final futures = <Future<Object?>>[];
    if (ref.read(gameProvider(gameId)).isLoading) {
      futures.add(ref.read(gameProvider(gameId).future));
    }
    if (refreshVisibleTab) {
      switch (_tabController.index) {
        case 1:
          if (ref.read(relayDataProvider(gameId)).isLoading) {
            futures.add(ref.read(relayDataProvider(gameId).future));
          }
          break;
        case 2:
          if (ref.read(gameBoxscoreProvider(gameId)).isLoading) {
            futures.add(ref.read(gameBoxscoreProvider(gameId).future));
          }
          break;
        case 3:
          if (ref.read(gameLineupProvider(gameId)).isLoading) {
            futures.add(ref.read(gameLineupProvider(gameId).future));
          }
          break;
      }
    }
    if (futures.isEmpty) {
      return;
    }
    try {
      await Future.wait(futures).timeout(const Duration(seconds: 25));
    } catch (error) {
      DevConsole.instance.warn(
        'GAME DETAIL active refresh wait skipped: $error',
      );
    }
  }

  Future<void> _loadFollowState() async {
    final isFollowing = await LiveActivityService.instance.isFollowing(
      widget.gameId,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _isFollowingGame = isFollowing;
      _followStateLoaded = true;
    });
  }

  Future<void> _toggleFollowGame(Game game) async {
    if (!_followStateLoaded) {
      return;
    }

    setState(() {
      _followStateLoaded = false;
    });

    try {
      if (_isFollowingGame) {
        await LiveActivityService.instance.stopFollowing();
      } else {
        await LiveActivityService.instance.followGame(game.gameId);
        await LiveActivityService.instance.requestPermissions();
        await GameEventAlertService.instance.requestPermissions();
        await PushNotificationService.instance.requestPermissionAndSync(
          myTeam: ref.read(myTeamProvider),
        );
        await LiveActivityService.instance.syncFollowedGame(
          game,
          repository: ref.read(gameRepositoryProvider),
        );
      }

      if (!mounted) {
        return;
      }
      setState(() {
        _isFollowingGame = !_isFollowingGame;
        _followStateLoaded = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_isFollowingGame ? '푸쉬 중계를 시작했습니다' : '푸쉬 중계를 종료했습니다'),
        ),
      );
    } catch (error) {
      DevConsole.instance.warn('Follow game toggle failed: $error');
      if (!mounted) {
        return;
      }
      setState(() {
        _followStateLoaded = true;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('푸쉬 중계 설정에 실패했습니다')));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();
    _outerScrollController.dispose();
    _tabController.removeListener(_handleTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final game = widget.game;
    final gameId = widget.gameId;
    final isLive = game.status == GameStatus.live;
    final showTicketInfo = shouldShowTicketInfoForGameDetail(game);
    final tabBar = TabBar(
      controller: _tabController,
      indicatorSize: TabBarIndicatorSize.tab,
      indicator: UnderlineTabIndicator(
        borderSide: BorderSide(color: AppColors.accent, width: 3),
        insets: EdgeInsets.symmetric(horizontal: 18),
      ),
      labelColor: AppColors.accent,
      labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
      unselectedLabelColor: AppColors.textDisabled,
      unselectedLabelStyle: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w800,
      ),
      labelPadding: EdgeInsets.zero,
      dividerColor: AppColors.divider,
      overlayColor: WidgetStateProperty.all(
        AppColors.accent.withValues(alpha: 0.08),
      ),
      tabs: const [
        Tab(text: '스코어'),
        Tab(text: '문자중계'),
        Tab(text: '박스스코어'),
        Tab(text: '라인업'),
      ],
    );

    return PopScope(
      canPop: GoRouter.of(context).canPop(),
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          return;
        }
        context.go('/home');
      },
      child: Scaffold(
        body: SafeArea(
          child: AppPageFrame(
            child: NestedScrollView(
              controller: _outerScrollController,
              headerSliverBuilder: (context, innerBoxIsScrolled) => [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back, size: 24),
                          onPressed: _goBackOrHome,
                        ),
                        Expanded(
                          child: Text(
                            _displayStadiumName(game.stadium),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 14,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 48),
                      ],
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: _GameScorebug(
                    game: game,
                    isLive: isLive,
                    refreshDelayed: widget.refreshDelayed,
                  ),
                ),
                if (widget.refreshDelayed)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 2, 16, 12),
                      child: _RefreshDelayCard(
                        onRetry: () =>
                            unawaited(_refreshGameDetail(userInitiated: true)),
                      ),
                    ),
                  ),
                if (isLive)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 2, 16, 12),
                      child: _FollowGameCard(
                        isFollowing: _isFollowingGame,
                        isLoading: !_followStateLoaded,
                        onPressed: () => unawaited(_toggleFollowGame(game)),
                      ),
                    ),
                  ),
                if (showTicketInfo)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: _TicketInfoCard(game: game),
                    ),
                  ),
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _TabBarHeaderDelegate(tabBar),
                ),
              ],
              body: TabBarView(
                controller: _tabController,
                children: [
                  ScoreTab(
                    gameId: gameId,
                    game: game,
                    onRefresh: () => _refreshGameDetail(userInitiated: true),
                    footer: game.status == GameStatus.final_
                        ? _HighlightSection(game: game, gameId: gameId)
                        : null,
                  ),
                  RelayTab(
                    gameId: gameId,
                    gameStatus: game.status,
                    game: game,
                    onRefresh: () => _refreshGameDetail(userInitiated: true),
                  ),
                  BoxscoreTab(
                    gameId: gameId,
                    game: game,
                    gameStatus: game.status,
                    awayName: game.away.shortName,
                    homeName: game.home.shortName,
                    awayTeamId: game.away.teamId,
                    homeTeamId: game.home.teamId,
                    onRefresh: () => _refreshGameDetail(userInitiated: true),
                  ),
                  LineupTab(
                    gameId: gameId,
                    gameStatus: game.status,
                    awayName: game.away.shortName,
                    homeName: game.home.shortName,
                    awayTeamId: game.away.teamId,
                    homeTeamId: game.home.teamId,
                    onRefresh: () => _refreshGameDetail(userInitiated: true),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _goBackOrHome() {
    final router = GoRouter.of(context);
    if (router.canPop()) {
      router.pop();
      return;
    }
    context.go('/home');
  }

  void _scheduleRelayFocusScroll() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_outerScrollController.hasClients) {
        return;
      }
      final target = gameDetailRelayFocusScrollTarget(
        _outerScrollController.position.maxScrollExtent,
      );
      if (target <= 0) {
        return;
      }
      unawaited(
        _outerScrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
        ),
      );
    });
  }
}

class _GameScorebug extends StatelessWidget {
  final Game game;
  final bool isLive;
  final bool refreshDelayed;

  const _GameScorebug({
    required this.game,
    required this.isLive,
    required this.refreshDelayed,
  });

  @override
  Widget build(BuildContext context) {
    final inningLabel = _scorebugInningLabel(game);
    final stadium = _displayStadiumName(game.stadium);

    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.background,
        border: Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      child: Stack(
        children: [
          const Positioned.fill(
            child: AppArtworkLayer(
              assetName: VisualAssets.gameDetailScoreboard,
              alignment: Alignment.center,
              opacity: 0.22,
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AppColors.background.withValues(alpha: 0.18),
                    AppColors.background.withValues(alpha: 0.92),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
            child: Column(
              children: [
                Row(
                  children: [
                    if (isLive) ...[
                      const _LiveBadge(label: 'LIVE', active: true),
                      const SizedBox(width: 10),
                    ],
                    Expanded(
                      child: Text(
                        refreshDelayed ? 'KBO 리그 | 갱신 지연' : 'KBO 리그',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w800,
                          height: 1.2,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: _ScorebugTeam(
                        teamId: game.away.teamId,
                        shortName: game.away.shortName,
                        alignEnd: false,
                      ),
                    ),
                    const SizedBox(width: 6),
                    _ScorebugScore(
                      score: game.away.score,
                      scoreKey: const ValueKey(
                        'game-detail-scorebug-away-score',
                      ),
                    ),
                    SizedBox(
                      width: 76,
                      child: Column(
                        children: [
                          Text(
                            inningLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              color: isLive
                                  ? AppColors.live
                                  : AppColors.textSecondary,
                              fontWeight: FontWeight.w900,
                              height: 1.2,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const _BaseDiamondMini(),
                        ],
                      ),
                    ),
                    _ScorebugScore(
                      score: game.home.score,
                      scoreKey: const ValueKey(
                        'game-detail-scorebug-home-score',
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: _ScorebugTeam(
                        teamId: game.home.teamId,
                        shortName: game.home.shortName,
                        alignEnd: true,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (stadium.isNotEmpty)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [_ScorebugInfoPill(label: stadium)],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RefreshDelayCard extends StatelessWidget {
  final VoidCallback onRetry;

  const _RefreshDelayCard({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      label: '경기 정보 갱신 지연',
      child: Container(
        key: const ValueKey('game-detail-refresh-delay'),
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: AppColors.ballYellow.withValues(alpha: 0.45),
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.sync_problem_outlined,
              size: 20,
              color: AppColors.ballYellow,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '갱신 지연',
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '기존 경기 정보를 유지하고 있습니다',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            TextButton(onPressed: onRetry, child: const Text('다시 시도')),
          ],
        ),
      ),
    );
  }
}

String _scorebugInningLabel(Game game) {
  if (game.status == GameStatus.final_) {
    return labelForGameStatus(game.status, statusLabel: game.statusLabel);
  }

  final inning = _normalizedInningLabel(game.inning);
  if (inning != null) {
    return inning;
  }

  return switch (game.status) {
    GameStatus.live => labelForGameStatus(
      game.status,
      statusLabel: game.statusLabel,
    ),
    GameStatus.final_ => labelForGameStatus(
      game.status,
      statusLabel: game.statusLabel,
    ),
    GameStatus.scheduled => '경기 전',
    GameStatus.cancelled => labelForGameStatus(
      game.status,
      statusLabel: game.statusLabel,
    ),
    GameStatus.suspended => labelForGameStatus(
      game.status,
      statusLabel: game.statusLabel,
    ),
  };
}

String? _normalizedInningLabel(String raw) {
  final label = raw.trim();
  if (label.isEmpty) {
    return null;
  }
  final match = RegExp(r'(연장\s*)?(\d+)\s*회\s*([초말]?)').firstMatch(label);
  if (match == null) {
    return null;
  }
  final prefix = match.group(1) == null ? '' : '연장 ';
  final inning = match.group(2)!;
  final half = match.group(3) ?? '';
  return '$prefix$inning회$half';
}

class _LiveBadge extends StatelessWidget {
  final String label;
  final bool active;

  const _LiveBadge({required this.label, required this.active});

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.live : AppColors.textSecondary;
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: active ? 0.18 : 0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: color.withValues(alpha: active ? 0.75 : 0.28),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          color: color,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _ScorebugScore extends StatelessWidget {
  final int score;
  final Key scoreKey;

  const _ScorebugScore({required this.score, required this.scoreKey});

  @override
  Widget build(BuildContext context) {
    final scoreText = '$score';
    return SizedBox(
      width: 56,
      height: 58,
      child: AppMotionValue(
        value: scoreText,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.center,
          child: Text(
            scoreText,
            key: scoreKey,
            maxLines: 1,
            softWrap: false,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 48,
              height: 0.96,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
        ),
      ),
    );
  }
}

class _ScorebugTeam extends StatelessWidget {
  final String teamId;
  final String shortName;
  final bool alignEnd;

  const _ScorebugTeam({
    required this.teamId,
    required this.shortName,
    required this.alignEnd,
  });

  @override
  Widget build(BuildContext context) {
    final team = KboTeams.byId(teamId);
    final colors = AppTheme.colorsOf(context);
    final accent = colors.readableAccent(
      team?.primaryColor ?? colors.textSecondary,
    );
    return Column(
      crossAxisAlignment: alignEnd
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        _ScorebugLogo(team: team, fallback: shortName),
        const SizedBox(height: 8),
        Container(
          width: 40,
          height: 3,
          decoration: BoxDecoration(
            color: accent,
            borderRadius: BorderRadius.circular(999),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          shortName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: alignEnd ? TextAlign.right : TextAlign.left,
          style: TextStyle(
            fontSize: 18,
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w900,
            height: 1.08,
          ),
        ),
      ],
    );
  }
}

class _ScorebugLogo extends StatelessWidget {
  final KboTeam? team;
  final String fallback;

  const _ScorebugLogo({required this.team, required this.fallback});

  @override
  Widget build(BuildContext context) {
    return KboTeamLogoImage(
      teamId: team?.id,
      fallback: fallback,
      size: 54,
      padding: 3,
    );
  }
}

class _BaseDiamondMini extends StatelessWidget {
  const _BaseDiamondMini();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 34,
      height: 28,
      child: Stack(
        alignment: Alignment.center,
        children: const [
          Positioned(top: 0, child: _BaseDot(active: false)),
          Positioned(left: 2, top: 11, child: _BaseDot(active: false)),
          Positioned(right: 2, top: 11, child: _BaseDot(active: false)),
          Positioned(bottom: 0, child: _BaseDot(active: false)),
        ],
      ),
    );
  }
}

class _BaseDot extends StatelessWidget {
  final bool active;

  const _BaseDot({required this.active});

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: 0.785398,
      child: Container(
        width: 13,
        height: 13,
        decoration: BoxDecoration(
          color: active ? AppColors.ballYellow : Colors.transparent,
          border: Border.all(
            color: active ? AppColors.ballYellow : AppColors.textDisabled,
            width: 1.5,
          ),
        ),
      ),
    );
  }
}

class _ScorebugInfoPill extends StatelessWidget {
  final String label;

  const _ScorebugInfoPill({required this.label});

  @override
  Widget build(BuildContext context) {
    if (label.isEmpty) {
      return const SizedBox.shrink();
    }
    return Flexible(
      child: Container(
        height: 24,
        padding: const EdgeInsets.symmetric(horizontal: 9),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.surface.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: AppColors.divider),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 11,
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _FollowGameCard extends StatelessWidget {
  final bool isFollowing;
  final bool isLoading;
  final VoidCallback onPressed;

  const _FollowGameCard({
    required this.isFollowing,
    required this.isLoading,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final backgroundColor = isFollowing ? AppColors.cardSub : AppColors.accent;
    final icon = isFollowing
        ? Icons.notifications_off_outlined
        : Icons.notifications_active_outlined;
    final label = isLoading
        ? '푸쉬 중계 확인 중'
        : isFollowing
        ? '푸쉬 중계 끄기'
        : '푸쉬 중계 받기';

    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton.icon(
        onPressed: isLoading ? null : onPressed,
        icon: isLoading
            ? SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    AppColors.textSecondary,
                  ),
                ),
              )
            : Icon(icon, size: 18),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          backgroundColor: backgroundColor,
          disabledBackgroundColor: AppColors.cardSub,
          foregroundColor: AppColors.textPrimary,
          disabledForegroundColor: AppColors.textSecondary,
          minimumSize: const Size.fromHeight(48),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    );
  }
}

int _tabIndexFromName(String? tab) {
  switch ((tab ?? '').toLowerCase()) {
    case 'relay':
    case 'middle':
      return 1;
    case 'box':
    case 'boxscore':
      return 2;
    case 'lineup':
      return 3;
    default:
      return 0;
  }
}

class _TicketInfoCard extends ConsumerWidget {
  final Game game;

  const _TicketInfoCard({required this.game});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ticket = game.ticketInfo!;
    final alertEnabledAsync = ref.watch(
      ticketAlertEnabledProvider(game.gameId),
    );

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                '예매 정보',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _infoRow('예매처', ticket.vendorName),
          _infoRow('예매 시작', _formatTicketTime(ticket.openAt)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: ticket.vendorUrl == null
                      ? null
                      : () async {
                          final uri = Uri.parse(ticket.vendorUrl!);
                          final mode = kIsWeb
                              ? LaunchMode.platformDefault
                              : LaunchMode.externalApplication;
                          await launchUrl(uri, mode: mode);
                        },
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: AppColors.divider),
                    foregroundColor: AppColors.textPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text('예매처 열기'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: alertEnabledAsync.when(
                  loading: () => ElevatedButton(
                    onPressed: null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.cardSub,
                      foregroundColor: AppColors.textDisabled,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text('알림 확인 중'),
                  ),
                  error: (_, _) =>
                      _alertButton(context: context, ref: ref, enabled: false),
                  data: (enabled) => _alertButton(
                    context: context,
                    ref: ref,
                    enabled: enabled,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _alertButton({
    required BuildContext context,
    required WidgetRef ref,
    required bool enabled,
  }) {
    return ElevatedButton(
      onPressed: () async {
        final result = await TicketAlertService.instance.setAlert(
          game: game,
          enabled: !enabled,
        );
        ref.invalidate(ticketAlertEnabledProvider(game.gameId));

        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(result.message)));
        }
      },
      style: ElevatedButton.styleFrom(
        backgroundColor: enabled ? AppColors.accent : AppColors.textPrimary,
        foregroundColor: enabled ? AppColors.textPrimary : AppColors.background,
        padding: const EdgeInsets.symmetric(vertical: 12),
      ),
      child: Text(enabled ? '알림 해제' : '예매 알림 설정'),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  String _formatTicketTime(DateTime? value) {
    if (value == null) {
      return '오픈 시간 미정';
    }
    return DateFormat('MM.dd HH:mm').format(value);
  }
}

class _HighlightCard extends StatefulWidget {
  final Game game;
  final String gameId;

  const _HighlightCard({required this.game, required this.gameId});

  @override
  State<_HighlightCard> createState() => _HighlightCardState();
}

class _HighlightCardState extends State<_HighlightCard> {
  YoutubePlayerController? _controller;
  String? _playingVideoId;
  bool _webPlayerInteractive = false;

  @override
  void dispose() {
    _controller?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final game = widget.game;
    final highlight = game.highlightInfo!;
    final videos = highlight.youtubeVideos;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.divider),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_playingVideoId != null && _controller != null)
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  IgnorePointer(
                    ignoring: kIsWeb && !_webPlayerInteractive,
                    child: YoutubePlayer(
                      controller: _controller!,
                      aspectRatio: 16 / 9,
                    ),
                  ),
                  if (kIsWeb) _webPlayerModeOverlay(),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '하이라이트',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                if (videos.isNotEmpty)
                  Text(
                    kIsWeb
                        ? '기본은 스크롤 모드이며, 필요할 때만 플레이어 조작 모드로 전환할 수 있습니다.'
                        : '여러 영상을 좌우로 넘기면서 바로 재생할 수 있습니다.',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  )
                else
                  Text(
                    '공식 하이라이트 페이지에서 확인할 수 있습니다.',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                const SizedBox(height: 12),
                if (videos.isNotEmpty)
                  SizedBox(
                    height: _videoListHeight(context),
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      physics: const ClampingScrollPhysics(),
                      itemCount: videos.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 12),
                      itemBuilder: (context, index) =>
                          _videoCard(videos[index]),
                    ),
                  ),
                if (highlight.officialUrl != null) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () => _openUrl(highlight.officialUrl!),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: AppColors.divider),
                        foregroundColor: AppColors.textPrimary,
                        padding: const EdgeInsets.symmetric(
                          vertical: 12,
                          horizontal: 14,
                        ),
                      ),
                      child: const Text('KBO 공식 하이라이트 열기'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _videoCard(HighlightVideo video) {
    final isPlayable = video.videoId.isNotEmpty;
    final isSearchFallback = video.source == 'youtube_search_fallback';
    final cardTitle = isSearchFallback ? '유튜브에서 하이라이트 찾기' : video.title;
    final thumbnailUrl = video.thumbnailUrl.isNotEmpty
        ? video.thumbnailUrl
        : (video.videoId.isNotEmpty
              ? 'https://img.youtube.com/vi/${video.videoId}/hqdefault.jpg'
              : '');
    return SizedBox(
      width: 260,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.cardSub,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: _playingVideoId == video.videoId
                ? AppColors.live
                : AppColors.divider,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            AppPressable(
              onTap: isPlayable
                  ? () => _playInline(video.videoId)
                  : () => _openUrl(video.videoUrl),
              pressedScale: 0.985,
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (thumbnailUrl.isNotEmpty)
                      CachedNetworkImage(
                        imageUrl: thumbnailUrl,
                        fit: BoxFit.cover,
                        memCacheWidth: 960,
                        memCacheHeight: 540,
                        errorWidget: (_, _, _) => _thumbnailFallback(),
                        placeholder: (_, _) =>
                            Container(color: AppColors.cardSub),
                      )
                    else if (isSearchFallback)
                      _searchFallbackThumbnail()
                    else
                      _thumbnailFallback(),
                    Container(color: Colors.black.withValues(alpha: 0.22)),
                    Center(
                      child: Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.65),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          isPlayable
                              ? Icons.play_arrow_rounded
                              : Icons.open_in_browser_rounded,
                          color: Colors.white,
                          size: 32,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    cardTitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      height: 1.25,
                    ),
                  ),
                  if (isSearchFallback) ...[
                    const SizedBox(height: 4),
                    Text(
                      '앱 안 브라우저에서 유튜브 검색 결과를 엽니다.',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: isPlayable
                          ? () => _playInline(video.videoId)
                          : () => _openUrl(video.videoUrl),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.live,
                        foregroundColor: AppColors.textPrimary,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                      child: Text(
                        isSearchFallback
                            ? '유튜브 검색 열기'
                            : _playingVideoId == video.videoId
                            ? '재생 중'
                            : '바로 재생',
                      ),
                    ),
                  ),
                  if (!isSearchFallback) ...[
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: () => _openUrl(video.videoUrl),
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.textSecondary,
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(0, 0),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        icon: const Icon(Icons.open_in_new_rounded, size: 16),
                        label: const Text('열기'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _thumbnailFallback() {
    return Container(
      color: AppColors.cardSub,
      alignment: Alignment.center,
      child: Icon(
        Icons.ondemand_video_rounded,
        color: AppColors.textSecondary,
        size: 42,
      ),
    );
  }

  Widget _searchFallbackThumbnail() {
    final awayTeam = KboTeams.resolve(
      id: widget.game.away.teamId,
      name: widget.game.away.shortName,
      shortName: widget.game.away.shortName,
    );
    final homeTeam = KboTeams.resolve(
      id: widget.game.home.teamId,
      name: widget.game.home.shortName,
      shortName: widget.game.home.shortName,
    );

    Widget teamBadge(KboTeam? team, String shortName) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          KboTeamLogoImage(
            teamId: team?.id,
            fallback: shortName,
            size: 28,
            padding: 1.5,
          ),
          const SizedBox(height: 4),
          Text(
            shortName,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      );
    }

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF1A1A1A),
            AppColors.cardSub,
            const Color(0xFF161616),
          ],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0, -0.25),
                  radius: 1.05,
                  colors: [
                    AppColors.live.withValues(alpha: 0.16),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Column(
              children: [
                Align(
                  alignment: Alignment.topLeft,
                  child: Text(
                    '유튜브 검색',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textDisabled,
                      letterSpacing: 0,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: Center(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        teamBadge(awayTeam, widget.game.away.shortName),
                        Text(
                          'VS',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textDisabled,
                          ),
                        ),
                        teamBadge(homeTeam, widget.game.home.shortName),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${widget.game.away.shortName} vs ${widget.game.home.shortName}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '유튜브 검색 결과로 이동',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
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

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    final mode = kIsWeb
        ? LaunchMode.platformDefault
        : LaunchMode.inAppBrowserView;
    final launched = await launchUrl(uri, mode: mode);
    if (!launched && !kIsWeb) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _playInline(String videoId) {
    if (videoId.isEmpty) {
      return;
    }

    _controller?.close();
    _controller = YoutubePlayerController.fromVideoId(
      videoId: videoId,
      autoPlay: true,
      params: const YoutubePlayerParams(
        showControls: true,
        showFullscreenButton: true,
        strictRelatedVideos: true,
      ),
    );

    setState(() {
      _playingVideoId = videoId;
      _webPlayerInteractive = false;
    });
  }

  Widget _webPlayerModeOverlay() {
    return Align(
      alignment: Alignment.topRight,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _modeChip(
                  label: '스크롤',
                  selected: !_webPlayerInteractive,
                  onTap: () {
                    setState(() {
                      _webPlayerInteractive = false;
                    });
                  },
                ),
                const SizedBox(width: 4),
                _modeChip(
                  label: '플레이어 조작',
                  selected: _webPlayerInteractive,
                  onTap: () {
                    setState(() {
                      _webPlayerInteractive = true;
                    });
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _modeChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return AppPressable(
      onTap: onTap,
      pressedScale: 0.94,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: selected ? AppColors.textPrimary : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: selected ? AppColors.background : AppColors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }

  double _videoListHeight(BuildContext context) {
    final height = MediaQuery.of(context).size.height;
    if (height < 760) {
      return 270;
    }
    if (height < 860) {
      return 284;
    }
    return 296;
  }
}

class _HighlightSection extends ConsumerStatefulWidget {
  final Game game;
  final String gameId;

  const _HighlightSection({required this.game, required this.gameId});

  @override
  ConsumerState<_HighlightSection> createState() => _HighlightSectionState();
}

class _HighlightSectionState extends ConsumerState<_HighlightSection> {
  @override
  Widget build(BuildContext context) {
    final highlightAsync = ref.watch(highlightInfoProvider(widget.gameId));
    final highlightInfo = _resolveHighlightInfo(
      game: widget.game,
      fetched: highlightAsync.asData?.value,
    );
    final mergedGame = Game(
      gameId: widget.game.gameId,
      status: widget.game.status,
      inning: widget.game.inning,
      away: widget.game.away,
      home: widget.game.home,
      stadium: widget.game.stadium,
      startTime: widget.game.startTime,
      statusLabel: widget.game.statusLabel,
      crowd: widget.game.crowd,
      ticketInfo: widget.game.ticketInfo,
      highlightInfo: highlightInfo,
    );

    return _HighlightCard(game: mergedGame, gameId: widget.gameId);
  }
}

HighlightInfo _resolveHighlightInfo({
  required Game game,
  HighlightInfo? fetched,
}) {
  final existing = game.highlightInfo;
  final fallback = _fallbackHighlightInfoForGame(game);
  final videos = fetched?.youtubeVideos.isNotEmpty == true
      ? fetched!.youtubeVideos
      : existing?.youtubeVideos.isNotEmpty == true
      ? existing!.youtubeVideos
      : fallback.youtubeVideos;
  final officialUrl = _firstNonEmptyString([
    fetched?.officialUrl,
    existing?.officialUrl,
    fallback.officialUrl,
  ]);

  return HighlightInfo(officialUrl: officialUrl, youtubeVideos: videos);
}

HighlightInfo _fallbackHighlightInfoForGame(Game game) {
  final query = _highlightSearchQuery(game);
  return HighlightInfo(
    officialUrl: _officialHighlightUrlForGame(game.gameId),
    youtubeVideos: [
      HighlightVideo(
        videoId: '',
        title: '${game.away.shortName} vs ${game.home.shortName} 하이라이트 검색',
        thumbnailUrl: '',
        videoUrl: Uri.https('www.youtube.com', '/results', {
          'search_query': query,
        }).toString(),
        source: 'youtube_search_fallback',
      ),
    ],
  );
}

String _highlightSearchQuery(Game game) {
  final dateLabel = _highlightDateLabel(game.gameId);
  final away = game.away.teamName.isNotEmpty
      ? game.away.teamName
      : game.away.shortName;
  final home = game.home.teamName.isNotEmpty
      ? game.home.teamName
      : game.home.shortName;
  return '$dateLabel $away $home 하이라이트'.trim();
}

String _highlightDateLabel(String gameId) {
  if (gameId.length < 8) {
    return '';
  }
  final month = int.tryParse(gameId.substring(4, 6));
  final day = int.tryParse(gameId.substring(6, 8));
  if (month == null || day == null) {
    return '';
  }
  return '$month월 $day일';
}

String _officialHighlightUrlForGame(String gameId) {
  if (gameId.length < 8) {
    return 'https://www.koreabaseball.com/Schedule/GameCenter/Main.aspx';
  }
  return 'https://www.koreabaseball.com/Schedule/GameCenter/Main.aspx?gameDate=${gameId.substring(0, 8)}&gameId=$gameId&section=HIGHLIGHT';
}

String? _firstNonEmptyString(List<String?> values) {
  for (final value in values) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isNotEmpty) {
      return trimmed;
    }
  }
  return null;
}

class _TabBarHeaderDelegate extends SliverPersistentHeaderDelegate {
  final TabBar tabBar;

  const _TabBarHeaderDelegate(this.tabBar);

  @override
  double get minExtent => tabBar.preferredSize.height;

  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.background,
        border: Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      child: SizedBox(height: tabBar.preferredSize.height, child: tabBar),
    );
  }

  @override
  bool shouldRebuild(covariant _TabBarHeaderDelegate oldDelegate) {
    return oldDelegate.tabBar != tabBar;
  }
}
