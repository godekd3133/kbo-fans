import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/constants/team_data.dart';
import '../../core/constants/visual_assets.dart';
import '../../core/router/app_route_sanitizer.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/kbo_player_image_cache.dart';
import '../../core/widgets/app_artwork_card.dart';
import '../../core/utils/game_status_label.dart';
import '../../core/widgets/app_motion.dart';
import '../../core/widgets/app_page_frame.dart';
import '../../core/widgets/game_status_badge.dart';
import '../../core/widgets/dev_console.dart';
import '../../core/widgets/kbo_team_logo_image.dart';
import '../../data/models/boxscore.dart';
import '../../data/models/game.dart';
import '../../data/models/home_aggregate.dart';
import '../../data/models/player.dart';
import '../../data/models/records_overview.dart';
import '../../data/models/relay.dart';
import '../../data/models/schedule.dart';
import '../../data/models/team_stats.dart';
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

const _gameDetailPlayerImagePrefetchLimit = 80;
const _gameDetailPlayerImagePrefetchTimeout = Duration(seconds: 8);
const _gameDetailOpenRefreshTimeout = Duration(seconds: 4);
const _teamPlayerImagePrefetchTimeout = Duration(seconds: 3);
const _lineupImagePrefetchSourceTimeout = Duration(seconds: 4);

@visibleForTesting
List<String> relayPlayerImagePrefetchUrlsForTesting({
  required RelayData relayData,
  required Iterable<PlayerProfile> teamPlayers,
  required int season,
}) {
  return _relayPlayerImagePrefetchUrls(
    relayData: relayData,
    teamPlayers: teamPlayers,
    season: season,
  );
}

@visibleForTesting
List<String> lineupPlayerImagePrefetchUrlsForTesting({
  required GameLineupData lineupData,
  required Iterable<PlayerProfile> awayPlayers,
  required Iterable<PlayerProfile> homePlayers,
  required int season,
}) {
  return _lineupPlayerImagePrefetchUrls(
    lineupData: lineupData,
    awayPlayers: awayPlayers,
    homePlayers: homePlayers,
    season: season,
  );
}

@visibleForTesting
List<String> boxscorePlayerImagePrefetchUrlsForTesting({
  required GameBoxscoreData boxscoreData,
  required Iterable<PlayerProfile> awayPlayers,
  required Iterable<PlayerProfile> homePlayers,
  required int season,
}) {
  return _boxscorePlayerImagePrefetchUrls(
    boxscoreData: boxscoreData,
    awayPlayers: awayPlayers,
    homePlayers: homePlayers,
    season: season,
  );
}

@visibleForTesting
bool shouldLoadPreviousScoreboardForTesting(List<Game> todayGames) {
  return _shouldLoadPreviousScoreboard(todayGames);
}

@visibleForTesting
List<Game> previousResultGamesForTesting(List<Game> games) {
  return _previousResultGames(games);
}

List<String> _relayPlayerImagePrefetchUrls({
  required RelayData relayData,
  required Iterable<PlayerProfile> teamPlayers,
  required int season,
}) {
  final imageByName = _playerImageUrlByName(teamPlayers, season);
  final imageUrls = <String>[];
  final seen = <String>{};

  void addUrl(String? rawUrl) {
    final imageUrl = rawUrl?.trim() ?? '';
    if (imageUrl.isEmpty || !seen.add(imageUrl)) {
      return;
    }
    imageUrls.add(imageUrl);
  }

  final currentAtBat = relayData.currentAtBat;
  if (currentAtBat != null) {
    addUrl(
      currentAtBat.batterImageUrl.isNotEmpty
          ? currentAtBat.batterImageUrl
          : _resolvePlayerImageUrl(imageByName, currentAtBat.batterName),
    );
    addUrl(
      currentAtBat.pitcherImageUrl.isNotEmpty
          ? currentAtBat.pitcherImageUrl
          : _resolvePlayerImageUrl(imageByName, currentAtBat.pitcherName),
    );
  }

  final sortedItems = List<RelayItem>.from(relayData.relayItems)
    ..sort((a, b) => b.seqNo.compareTo(a.seqNo));
  for (final item in sortedItems) {
    final actorLabel = _relayActorLabelForImagePrefetch(item.text);
    if (actorLabel == null) {
      continue;
    }
    addUrl(_resolvePlayerImageUrl(imageByName, actorLabel));
  }
  for (final imageUrl in _playerProfileImageUrlsForPrefetch(
    teamPlayers,
    season,
  )) {
    addUrl(imageUrl);
  }

  return imageUrls.take(_gameDetailPlayerImagePrefetchLimit).toList();
}

List<String> _lineupPlayerImagePrefetchUrls({
  required GameLineupData lineupData,
  required Iterable<PlayerProfile> awayPlayers,
  required Iterable<PlayerProfile> homePlayers,
  required int season,
}) {
  final imageUrls = <String>[];
  final seen = <String>{};

  void addUrl(String? rawUrl) {
    final imageUrl = rawUrl?.trim() ?? '';
    if (imageUrl.isEmpty || !seen.add(imageUrl)) {
      return;
    }
    imageUrls.add(imageUrl);
  }

  void addTeamUrls(TeamLineupData teamLineup, Iterable<PlayerProfile> players) {
    final imageByName = _playerImageUrlByName(players, season);
    addUrl(
      _lineupStarterImageUrl(
        teamLineup,
        imageByName: imageByName,
        season: season,
      ),
    );
    for (final entry in teamLineup.lineup) {
      addUrl(
        _lineupEntryImageUrl(entry, imageByName: imageByName, season: season),
      );
    }
    for (final imageUrl in _playerProfileImageUrlsForPrefetch(
      players,
      season,
    )) {
      addUrl(imageUrl);
    }
  }

  addTeamUrls(lineupData.away, awayPlayers);
  addTeamUrls(lineupData.home, homePlayers);

  return imageUrls.take(_gameDetailPlayerImagePrefetchLimit).toList();
}

List<String> _boxscorePlayerImagePrefetchUrls({
  required GameBoxscoreData boxscoreData,
  required Iterable<PlayerProfile> awayPlayers,
  required Iterable<PlayerProfile> homePlayers,
  required int season,
}) {
  final imageUrls = <String>[];
  final seen = <String>{};

  void addUrl(String? rawUrl) {
    final imageUrl = rawUrl?.trim() ?? '';
    if (imageUrl.isEmpty || !seen.add(imageUrl)) {
      return;
    }
    imageUrls.add(imageUrl);
  }

  void addTeamUrls(TeamBoxscoreData team, Iterable<PlayerProfile> players) {
    final imageByName = _playerImageUrlByName(players, season);
    for (final batter in team.batters) {
      addUrl(
        _boxscoreRowImageUrl(
          imageUrl: batter.imageUrl,
          playerId: batter.playerId,
          name: batter.name,
          imageByName: imageByName,
          season: season,
        ),
      );
    }
    for (final pitcher in team.pitchers) {
      addUrl(
        _boxscoreRowImageUrl(
          imageUrl: pitcher.imageUrl,
          playerId: pitcher.playerId,
          name: pitcher.name,
          imageByName: imageByName,
          season: season,
        ),
      );
    }
    for (final imageUrl in _playerProfileImageUrlsForPrefetch(
      players,
      season,
    )) {
      addUrl(imageUrl);
    }
  }

  addTeamUrls(boxscoreData.away, awayPlayers);
  addTeamUrls(boxscoreData.home, homePlayers);

  return imageUrls.take(_gameDetailPlayerImagePrefetchLimit).toList();
}

String? _boxscoreRowImageUrl({
  required String? imageUrl,
  required String? playerId,
  required String name,
  required Map<String, String> imageByName,
  required int season,
}) {
  final sourceImageUrl = imageUrl?.trim() ?? '';
  if (sourceImageUrl.isNotEmpty) {
    return sourceImageUrl;
  }
  final cleanedPlayerId = playerId?.trim() ?? '';
  if (cleanedPlayerId.isNotEmpty) {
    return kboPlayerImageUrl(season: season, playerId: cleanedPlayerId);
  }
  return _resolvePlayerImageUrl(imageByName, name);
}

List<String> _playerProfileImageUrlsForPrefetch(
  Iterable<PlayerProfile> players,
  int season,
) {
  final imageUrls = <String>[];
  for (final player in players) {
    final imageUrl = playerProfileImageUrl(player, season: season)?.trim();
    if (imageUrl != null && imageUrl.isNotEmpty) {
      imageUrls.add(imageUrl);
    }
  }
  return imageUrls;
}

Map<String, String> _playerImageUrlByName(
  Iterable<PlayerProfile> players,
  int season,
) {
  return {
    for (final player in players)
      if (player.name.isNotEmpty)
        _normalizePlayerNameForImagePrefetch(player.name):
            playerProfileImageUrl(player, season: season) ?? '',
  }..removeWhere((_, imageUrl) => imageUrl.isEmpty);
}

String? _lineupStarterImageUrl(
  TeamLineupData teamLineup, {
  required Map<String, String> imageByName,
  required int season,
}) {
  final starterImageUrl = teamLineup.starterImageUrl?.trim() ?? '';
  if (starterImageUrl.isNotEmpty) {
    return starterImageUrl;
  }
  final starterId = teamLineup.starterId?.trim() ?? '';
  if (starterId.isNotEmpty) {
    return kboPlayerImageUrl(season: season, playerId: starterId);
  }
  return _resolvePlayerImageUrl(imageByName, teamLineup.starterName ?? '');
}

String? _lineupEntryImageUrl(
  LineupEntry entry, {
  required Map<String, String> imageByName,
  required int season,
}) {
  final imageUrl = entry.imageUrl?.trim() ?? '';
  if (imageUrl.isNotEmpty) {
    return imageUrl;
  }
  final playerId = entry.playerId?.trim() ?? '';
  if (playerId.isNotEmpty) {
    return kboPlayerImageUrl(season: season, playerId: playerId);
  }
  return _resolvePlayerImageUrl(imageByName, entry.name);
}

String? _resolvePlayerImageUrl(
  Map<String, String> imageByName,
  String rawName,
) {
  final normalizedTarget = _normalizePlayerNameForImagePrefetch(rawName);
  if (normalizedTarget.isEmpty) {
    return null;
  }
  final exact = imageByName[normalizedTarget];
  if (exact != null && exact.isNotEmpty) {
    return exact;
  }
  for (final entry in imageByName.entries) {
    if (entry.key.contains(normalizedTarget) ||
        normalizedTarget.contains(entry.key)) {
      return entry.value;
    }
  }
  return null;
}

String _normalizePlayerNameForImagePrefetch(String value) {
  return value
      .replaceFirst(RegExp(r'^\d+\s*번?\s*타자\s*'), '')
      .replaceFirst(RegExp(r'^\d+번\s*'), '')
      .replaceFirst(RegExp(r'^(대타|대주자|투수|타자)\s+'), '')
      .replaceAll(RegExp(r'\s+'), '')
      .replaceAll(RegExp(r'[·ㆍ.]'), '')
      .trim();
}

String? _relayActorLabelForImagePrefetch(String text) {
  final colonIndex = text.indexOf(':');
  if (colonIndex > 0) {
    return text.substring(0, colonIndex).trim();
  }
  final byMatch = RegExp(r'^(.*?)\s+(교체|볼넷|삼진|안타|홈런|아웃)').firstMatch(text);
  final actor = byMatch?.group(1)?.trim() ?? '';
  return actor.isEmpty ? null : actor;
}

int _seasonFromGameId(String gameId) {
  if (gameId.length >= 4) {
    final parsed = int.tryParse(gameId.substring(0, 4));
    if (parsed != null) {
      return parsed;
    }
  }
  return DateTime.now().year;
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

String _previousScoreboardDate(String date) {
  final parsed = DateTime.tryParse(date);
  if (parsed == null) {
    return date;
  }
  return DateFormat(
    'yyyy-MM-dd',
  ).format(parsed.subtract(const Duration(days: 1)));
}

bool _shouldLoadPreviousScoreboard(List<Game> todayGames) {
  if (todayGames.isEmpty) {
    return true;
  }
  return todayGames.every(
    (game) =>
        game.status == GameStatus.scheduled ||
        game.status == GameStatus.cancelled,
  );
}

List<Game> _previousResultGames(List<Game> games) {
  return _uniqueGamesById(
    games.where((game) => game.status == GameStatus.final_).toList(),
  );
}

Game? _liveMyTeamGameFor(List<Game> games, String? myTeamId) {
  final teamId = myTeamId?.trim() ?? '';
  if (teamId.isEmpty) {
    return null;
  }
  for (final game in _uniqueGamesById(games)) {
    if (game.status == GameStatus.live &&
        (game.away.teamId == teamId || game.home.teamId == teamId)) {
      return game;
    }
  }
  return null;
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
  String? _lastPreviousScoreboardErrorLogKey;
  String? _openingGameDetailId;
  double _openingGameDetailProgress = 0;

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
    AppColors.sync(AppTheme.colorsOf(context));
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final scoreboardAsync = ref.watch(scoreboardProvider(today));
    final myTeamId = ref.watch(myTeamProvider);
    _logHomeLoad(scoreboardAsync, today);
    final fallbackGames = _lastScoreboardGamesFor(today);

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
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
                                  style: TextStyle(
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
                      key: ValueKey(
                        'home-scoreboard-$today-${displayGames.length}',
                      ),
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
            if (_openingGameDetailId != null)
              Positioned.fill(child: _buildGameDetailLoadingOverlay(context)),
          ],
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

  void _logPreviousScoreboardFailure(String date, Object error) {
    final key = '$date|${error.runtimeType}|$error';
    if (_lastPreviousScoreboardErrorLogKey == key) {
      return;
    }
    _lastPreviousScoreboardErrorLogKey = key;
    DevConsole.instance.warn(
      'HOME previous scoreboard unavailable; keeping today-only view: $error',
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
          ? Center(
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

  Widget _buildGameDetailLoadingOverlay(BuildContext context) {
    final progress = _openingGameDetailProgress.clamp(0.0, 1.0).toDouble();
    final percent = (progress * 100).round();

    return ColoredBox(
      key: const ValueKey('home-game-detail-loading'),
      color: AppColors.background.withValues(alpha: 0.72),
      child: Center(
        child: Container(
          width: 224,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.divider),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: AppColors.live,
                ),
              ),
              SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '경기 정보 갱신 중',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  SizedBox(width: 10),
                  Text(
                    '$percent%',
                    key: const ValueKey('home-game-detail-loading-percent'),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      color: AppColors.live,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  key: const ValueKey('home-game-detail-loading-progress'),
                  value: progress,
                  minHeight: 6,
                  color: AppColors.live,
                  backgroundColor: AppColors.divider.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
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
    final liveMyTeamGame = _liveMyTeamGameFor(games, myTeamId);
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
                  final season = int.tryParse(today.substring(0, 4)) ?? 2026;
                  final teamRecordsKey = myTeamId == null
                      ? null
                      : '$myTeamId|$season';
                  final shouldLoadTeamRecords =
                      _secondarySectionsEnabled &&
                      teamRecordsKey != null &&
                      myTeamId?.isNotEmpty == true &&
                      myTeamBrief != null;
                  final AsyncValue<TeamStats>? teamStatsAsync =
                      shouldLoadTeamRecords
                      ? ref.watch(teamStatsProvider(teamRecordsKey))
                      : null;
                  final AsyncValue<List<PlayerProfile>>? teamPlayersAsync =
                      shouldLoadTeamRecords
                      ? ref.watch(teamPlayersProvider(teamRecordsKey))
                      : null;

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
                                teamStatsAsync: teamStatsAsync,
                                teamPlayersAsync: teamPlayersAsync,
                                onOpenGame: _openGameDetail,
                              )
                            : const _DeferredSectionCard(
                                title: '마이팀 브리프',
                                subtitle: '홈 첫 화면을 먼저 띄우는 중입니다.',
                              ),
                      ),
                      if (liveMyTeamGame != null)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                          child: _LiveMyTeamGameCard(
                            game: liveMyTeamGame,
                            myTeamId: myTeamId!,
                            onOpenRelay: () => _openGameDetail(
                              liveMyTeamGame,
                              tab: 'relay',
                              focusRelay: true,
                            ),
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 5, 12, 0),
                        child: Consumer(
                          builder: (context, ref, _) {
                            final previousDate = _previousScoreboardDate(today);
                            final previousScoreboardAsync =
                                _shouldLoadPreviousScoreboard(games)
                                ? ref.watch(scoreboardProvider(previousDate))
                                : null;
                            previousScoreboardAsync?.whenOrNull(
                              error: (error, _) =>
                                  _logPreviousScoreboardFailure(
                                    previousDate,
                                    error,
                                  ),
                            );
                            final previousResultGames = _previousResultGames(
                              previousScoreboardAsync?.asData?.value ??
                                  const <Game>[],
                            );
                            return _TodayGamesReferenceCard(
                              games: games,
                              previousResultGames: previousResultGames,
                              myTeamId: myTeamId,
                              standings: standingsPreview,
                              onOpenGame: _openGameDetail,
                            );
                          },
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
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
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
                      if (_secondarySectionsEnabled &&
                          kboBrief != null &&
                          _displayableKboBriefItems(kboBrief).isNotEmpty)
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
    if (_openingGameDetailId != null) {
      return;
    }
    unawaited(
      _openGameDetailAfterRefresh(game, tab: tab, focusRelay: focusRelay),
    );
  }

  void _updateGameDetailOpenProgress(double progress) {
    if (!mounted || _openingGameDetailId == null) {
      return;
    }
    final nextProgress = progress.clamp(0.0, 1.0).toDouble();
    if ((_openingGameDetailProgress - nextProgress).abs() < 0.001) {
      return;
    }
    setState(() {
      _openingGameDetailProgress = nextProgress;
    });
  }

  Future<void> _openGameDetailAfterRefresh(
    Game game, {
    String? tab,
    required bool focusRelay,
  }) async {
    setState(() {
      _openingGameDetailId = game.gameId;
      _openingGameDetailProgress = 0;
    });

    try {
      var gameToOpen = game;
      try {
        gameToOpen = await _refreshGameDetailBeforeOpen(game, tab: tab);
      } catch (error) {
        DevConsole.instance.warn(
          'HOME game detail open refresh failed; opening existing game: ${game.gameId} $error',
        );
      }
      if (!mounted) {
        return;
      }
      GoRouter.of(context).push(
        gameDetailLocationFor(gameToOpen, tab: tab, focusRelay: focusRelay),
        extra: gameToOpen,
      );
    } finally {
      if (mounted) {
        setState(() {
          _openingGameDetailId = null;
          _openingGameDetailProgress = 0;
        });
      }
    }
  }

  Future<Game> _refreshGameDetailBeforeOpen(Game game, {String? tab}) async {
    final gameId = game.gameId;
    final targetTab = tab ?? (game.status == GameStatus.live ? 'relay' : null);

    ref.invalidate(gameProvider(gameId));
    final gameFuture = ref.read(gameProvider(gameId).future);
    Future<RelayData?>? relayFuture;
    Future<GameLineupData?>? lineupFuture;
    Future<GameBoxscoreData?>? boxscoreFuture;
    RelayData? relayData;
    GameLineupData? lineupData;
    GameBoxscoreData? boxscoreData;

    Future<T?> readWarmupProvider<T>(String label, Future<T> future) {
      return future.then<T?>((value) => value).catchError((
        Object error,
        StackTrace stackTrace,
      ) {
        DevConsole.instance.warn(
          'HOME game detail $label warmup skipped: $gameId $error',
        );
        return null;
      });
    }

    Future<RelayData?> startRelayWarmup() {
      relayFuture ??= () {
        ref.invalidate(relayDataProvider(gameId));
        return readWarmupProvider<RelayData>(
          'relay',
          ref.read(relayDataProvider(gameId).future),
        );
      }();
      return relayFuture!;
    }

    Future<GameLineupData?> startLineupWarmup() {
      lineupFuture ??= () {
        ref.invalidate(gameLineupProvider(gameId));
        return readWarmupProvider<GameLineupData>(
          'lineup',
          ref.read(gameLineupProvider(gameId).future),
        );
      }();
      return lineupFuture!;
    }

    Future<GameBoxscoreData?> startBoxscoreWarmup() {
      boxscoreFuture ??= () {
        ref.invalidate(gameBoxscoreProvider(gameId));
        return readWarmupProvider<GameBoxscoreData>(
          'boxscore',
          ref.read(gameBoxscoreProvider(gameId).future),
        );
      }();
      return boxscoreFuture!;
    }

    switch (targetTab) {
      case 'relay':
        relayFuture = startRelayWarmup();
        break;
      case 'boxscore':
        boxscoreFuture = startBoxscoreWarmup();
        break;
      case 'lineup':
        lineupFuture = startLineupWarmup();
        break;
      case null:
        lineupFuture = startLineupWarmup();
        break;
    }

    final refreshedGame = await gameFuture.timeout(
      _gameDetailOpenRefreshTimeout,
    );
    if (refreshedGame == null) {
      throw StateError('game detail missing: $gameId');
    }
    _updateGameDetailOpenProgress(1);

    unawaited(() async {
      try {
        relayData = await _awaitGameDetailWarmup(relayFuture);
        lineupData = await _awaitGameDetailWarmup(lineupFuture);
        boxscoreData = await _awaitGameDetailWarmup(boxscoreFuture);
        await _precacheGameDetailPlayerImagesBeforeOpen(
          refreshedGame,
          targetTab: targetTab,
          relayData: relayData,
          lineupData: lineupData,
          boxscoreData: boxscoreData,
        ).timeout(_gameDetailPlayerImagePrefetchTimeout, onTimeout: () {});
      } catch (error) {
        DevConsole.instance.warn(
          'HOME game detail background warmup skipped: $gameId $error',
        );
      }
    }());
    return refreshedGame;
  }

  Future<T?> _awaitGameDetailWarmup<T>(Future<T?>? future) {
    if (future == null) {
      return Future<T?>.value();
    }
    return future.timeout(_gameDetailOpenRefreshTimeout, onTimeout: () => null);
  }

  Future<void> _precacheGameDetailPlayerImagesBeforeOpen(
    Game game, {
    required String? targetTab,
    RelayData? relayData,
    GameLineupData? lineupData,
    GameBoxscoreData? boxscoreData,
  }) async {
    if (!mounted) {
      return;
    }

    try {
      final imageUrls = <String>[];
      switch (targetTab) {
        case 'relay':
          imageUrls.addAll(await _relayImageUrlsBeforeOpen(game, relayData));
          imageUrls.addAll(
            await _lineupImageUrlsBeforeOpen(
              game,
              lineupData ?? await _lineupDataForImagePrefetch(game.gameId),
            ),
          );
          break;
        case 'lineup':
          imageUrls.addAll(await _lineupImageUrlsBeforeOpen(game, lineupData));
          break;
        case 'boxscore':
          imageUrls.addAll(
            await _boxscoreImageUrlsBeforeOpen(game, boxscoreData),
          );
          imageUrls.addAll(
            await _lineupImageUrlsBeforeOpen(
              game,
              lineupData ?? await _lineupDataForImagePrefetch(game.gameId),
            ),
          );
          break;
        case null:
          imageUrls.addAll(await _lineupImageUrlsBeforeOpen(game, lineupData));
          break;
      }
      if (imageUrls.isEmpty || !mounted) {
        return;
      }
      await precacheKboPlayerImageUrls(
        context,
        imageUrls,
        limit: _gameDetailPlayerImagePrefetchLimit,
      ).timeout(_gameDetailPlayerImagePrefetchTimeout);
    } catch (error) {
      DevConsole.instance.warn(
        'HOME game detail image prefetch skipped: ${game.gameId} $error',
      );
    }
  }

  Future<List<String>> _boxscoreImageUrlsBeforeOpen(
    Game game,
    GameBoxscoreData? boxscoreData,
  ) async {
    final season = _seasonFromGameId(game.gameId);
    if (boxscoreData == null) {
      final teamPlayers = await _teamPlayersForImagePrefetch(game, season);
      return _playerProfileImageUrlsForPrefetch(
        teamPlayers,
        season,
      ).take(_gameDetailPlayerImagePrefetchLimit).toList();
    }
    final awayTeamId = boxscoreData.away.teamId.isNotEmpty
        ? boxscoreData.away.teamId
        : game.away.teamId;
    final homeTeamId = boxscoreData.home.teamId.isNotEmpty
        ? boxscoreData.home.teamId
        : game.home.teamId;
    final awayPlayers = await _teamPlayersForTeamIds([awayTeamId], season);
    final homePlayers = await _teamPlayersForTeamIds([homeTeamId], season);
    return _boxscorePlayerImagePrefetchUrls(
      boxscoreData: boxscoreData,
      awayPlayers: awayPlayers,
      homePlayers: homePlayers,
      season: season,
    );
  }

  Future<List<String>> _relayImageUrlsBeforeOpen(
    Game game,
    RelayData? relayData,
  ) async {
    if (relayData == null) {
      return const [];
    }
    final season = _seasonFromGameId(game.gameId);
    final teamPlayers = await _teamPlayersForImagePrefetch(game, season);
    if (relayData.relayItems.isEmpty && relayData.currentAtBat == null) {
      return _playerProfileImageUrlsForPrefetch(
        teamPlayers,
        season,
      ).take(_gameDetailPlayerImagePrefetchLimit).toList();
    }
    return _relayPlayerImagePrefetchUrls(
      relayData: relayData,
      teamPlayers: teamPlayers,
      season: season,
    );
  }

  Future<List<String>> _lineupImageUrlsBeforeOpen(
    Game game,
    GameLineupData? lineupData,
  ) async {
    final season = _seasonFromGameId(game.gameId);
    if (lineupData == null) {
      final teamPlayers = await _teamPlayersForImagePrefetch(game, season);
      return _playerProfileImageUrlsForPrefetch(
        teamPlayers,
        season,
      ).take(_gameDetailPlayerImagePrefetchLimit).toList();
    }
    final awayTeamId = lineupData.away.teamId.isNotEmpty
        ? lineupData.away.teamId
        : game.away.teamId;
    final homeTeamId = lineupData.home.teamId.isNotEmpty
        ? lineupData.home.teamId
        : game.home.teamId;
    final awayPlayers = await _teamPlayersForTeamIds([awayTeamId], season);
    final homePlayers = await _teamPlayersForTeamIds([homeTeamId], season);
    return _lineupPlayerImagePrefetchUrls(
      lineupData: lineupData,
      awayPlayers: awayPlayers,
      homePlayers: homePlayers,
      season: season,
    );
  }

  Future<List<PlayerProfile>> _teamPlayersForImagePrefetch(
    Game game,
    int season,
  ) async {
    return _teamPlayersForTeamIds([game.away.teamId, game.home.teamId], season);
  }

  Future<List<PlayerProfile>> _teamPlayersForTeamIds(
    Iterable<String> rawTeamIds,
    int season,
  ) async {
    final teamIds = <String>{...rawTeamIds}
      ..removeWhere((teamId) => teamId.isEmpty);
    if (teamIds.isEmpty) {
      return const [];
    }

    final groups = await Future.wait([
      for (final teamId in teamIds)
        _readTeamPlayersForImagePrefetch(teamId, season),
    ]);
    return [for (final group in groups) ...group];
  }

  Future<List<PlayerProfile>> _readTeamPlayersForImagePrefetch(
    String teamId,
    int season,
  ) async {
    try {
      return await ref
          .read(teamPlayersProvider('$teamId|$season').future)
          .timeout(_teamPlayerImagePrefetchTimeout);
    } catch (error) {
      DevConsole.instance.warn(
        'HOME game detail team image source skipped: $teamId $season $error',
      );
      return const [];
    }
  }

  Future<GameLineupData?> _lineupDataForImagePrefetch(String gameId) async {
    try {
      return await ref
          .read(gameLineupProvider(gameId).future)
          .timeout(_lineupImagePrefetchSourceTimeout);
    } catch (error) {
      DevConsole.instance.warn(
        'HOME game detail lineup image source skipped: $gameId $error',
      );
      return null;
    }
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
              (game.status == GameStatus.live || game.isPregameLineupOpen) &&
              _isMyTeamGame(game, myTeamId),
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
        await LiveActivityService.instance.syncFollowedGame(
          game,
          repository: ref.read(gameRepositoryProvider),
        );
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
    if (kIsWeb) {
      return Column(
        children: [
          const _ReferenceStatusBar(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: const _HeaderBar(height: 34),
          ),
        ],
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
      child: const _HeaderBar(height: 48),
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
    final lastGames = _lastScoreboardGamesFor(today) ?? const <Game>[];
    if (_shouldLoadPreviousScoreboard(lastGames)) {
      ref.invalidate(scoreboardProvider(_previousScoreboardDate(today)));
    }
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
        repository: ref.read(gameRepositoryProvider),
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
        icon: Icon(icon, size: 26),
        color: AppColors.textPrimary,
        constraints: const BoxConstraints.tightFor(width: 40, height: 40),
        padding: EdgeInsets.zero,
        splashRadius: 22,
      ),
    );
  }
}

class _ReferenceStatusBar extends StatelessWidget {
  const _ReferenceStatusBar();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(23, 10, 22, 0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '9:41',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
                height: 1,
              ),
            ),
            const Spacer(),
            Image.asset(
              'assets/visuals/reference_status_icons.png',
              width: 74,
              height: 13,
              fit: BoxFit.contain,
              alignment: Alignment.topRight,
              filterQuality: FilterQuality.high,
            ),
          ],
        ),
      ),
    );
  }
}

class _HeaderBar extends StatelessWidget {
  final double height;

  const _HeaderBar({required this.height});

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final logoAsset = isLight
        ? 'assets/visuals/kbo_header_logo_light.png'
        : 'assets/visuals/kbo_header_logo.png';

    return SizedBox(
      height: height,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Image.asset(
              logoAsset,
              key: const ValueKey('home-header-logo'),
              width: 64,
              height: 28,
              fit: BoxFit.contain,
            ),
          ),
          const Text(
            '홈',
            style: TextStyle(
              fontSize: 19,
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
                  onPressed: () => context.push('/notifications'),
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
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
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
  final AsyncValue<TeamStats>? teamStatsAsync;
  final AsyncValue<List<PlayerProfile>>? teamPlayersAsync;
  final ValueChanged<Game> onOpenGame;

  const _MyTeamBriefCard({
    required this.myTeamId,
    required this.brief,
    required this.todayGame,
    required this.teamStatsAsync,
    required this.teamPlayersAsync,
    required this.onOpenGame,
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
            Text(
              '응원팀을 선택하면 오늘 경기, 최근 5경기, 순위를 홈에서 바로 보여줍니다.',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: const [
                _BenefitChip(label: '오늘 경기 우선'),
                _BenefitChip(label: '예매 오픈 추적'),
                _BenefitChip(label: '순위/최근 5경기'),
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
    final colors = AppTheme.colorsOf(context);
    final accent = colors.readableAccent(team?.primaryColor ?? colors.accent);
    final recordBrief = _TeamRecordBriefData.resolve(
      teamStatsAsync: teamStatsAsync,
      teamPlayersAsync: teamPlayersAsync,
    );
    final metrics = recordBrief.metrics;
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
        onOpenGame(todayGame!);
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
      backgroundOpacity: 0.14,
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
                        size: 76,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        standing == null
                            ? view.subline
                            : '${standing.rank}위 · ${standing.wins}승 ${standing.losses}패 ${standing.draws}무',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
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
                              style: TextStyle(
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
            _TeamRecordSpotlightRow(recordBrief: recordBrief),
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
          style: TextStyle(
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
          style: TextStyle(
            fontSize: 10,
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _resultBubbleRow(
    List<_RecentGameSummaryData> summaries, {
    double size = 34,
    bool centered = false,
  }) {
    final visible = summaries.take(5).toList();
    if (visible.isEmpty) {
      return Text(
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
        side: BorderSide(color: AppColors.divider),
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

  static _BriefMetricSnapshot _fromTeamStats(TeamStats stats) {
    final avg = _statValue(stats.hitting, const ['AVG', '타율']);
    final avgRank = _statValue(stats.hitting, const ['순위', 'Rank', 'RANK']);
    final ops = _statValue(stats.hitting, const ['OPS']);
    final era = _statValue(stats.pitching, const ['ERA', '평균자책점', '평균자책']);
    final eraRank = _statValue(stats.pitching, const ['순위', 'Rank', 'RANK']);
    final whip = _statValue(stats.pitching, const ['WHIP']);

    return _BriefMetricSnapshot(
      avg: _formatAverage(avg),
      avgRank: avgRank.isNotEmpty
          ? _formatRank(avgRank)
          : _formatLabeledStat('OPS', ops),
      era: _formatEra(era),
      eraRank: eraRank.isNotEmpty
          ? _formatRank(eraRank)
          : _formatLabeledStat('WHIP', whip),
    );
  }

  static String _statValue(Map<String, String> values, List<String> keys) {
    for (final key in keys) {
      final value = values[key]?.trim();
      if (value != null && value.isNotEmpty) {
        return value;
      }
    }

    final normalizedKeys = keys.map(_normalizeStatKey).toSet();
    for (final entry in values.entries) {
      if (normalizedKeys.contains(_normalizeStatKey(entry.key))) {
        final value = entry.value.trim();
        if (value.isNotEmpty) {
          return value;
        }
      }
    }
    return '';
  }

  static String _normalizeStatKey(String key) {
    return key.replaceAll(RegExp(r'\s+'), '').toUpperCase();
  }

  static String _formatAverage(String raw) {
    final value = raw.trim();
    if (value.isEmpty || value == '-') {
      return '-';
    }
    if (value.startsWith('.') && RegExp(r'^\.\d+$').hasMatch(value)) {
      return '0$value';
    }
    final parsed = double.tryParse(value.replaceAll(',', ''));
    if (parsed != null && parsed > 0 && parsed < 1) {
      return parsed.toStringAsFixed(3);
    }
    return value;
  }

  static String _formatEra(String raw) {
    final value = raw.trim();
    if (value.isEmpty || value == '-') {
      return '-';
    }
    final parsed = double.tryParse(value.replaceAll(',', ''));
    if (parsed != null) {
      return parsed.toStringAsFixed(2);
    }
    return value;
  }

  static String _formatRank(String raw) {
    final value = raw.trim();
    if (value.isEmpty || value == '-') {
      return '순위 없음';
    }
    if (value.endsWith('위')) {
      return value;
    }
    final match = RegExp(r'\d+').firstMatch(value);
    if (match != null) {
      return '${match.group(0)}위';
    }
    return value;
  }

  static String _formatLabeledStat(String label, String raw) {
    final value = raw.trim();
    if (value.isEmpty || value == '-') {
      return '집계 중';
    }
    return '$label $value';
  }
}

class _PlayerRecordHighlight {
  final String name;
  final String value;

  const _PlayerRecordHighlight({required this.name, required this.value});
}

class _TeamRecordBriefData {
  final _BriefMetricSnapshot metrics;
  final _PlayerRecordHighlight? homeRunLeader;
  final _PlayerRecordHighlight? risingPlayer;
  final bool isLoading;
  final bool hasError;

  const _TeamRecordBriefData({
    required this.metrics,
    this.homeRunLeader,
    this.risingPlayer,
    this.isLoading = false,
    this.hasError = false,
  });

  static _TeamRecordBriefData resolve({
    required AsyncValue<TeamStats>? teamStatsAsync,
    required AsyncValue<List<PlayerProfile>>? teamPlayersAsync,
  }) {
    final teamStats = teamStatsAsync?.asData?.value;
    final players = teamPlayersAsync?.asData?.value;
    if (teamStats == null) {
      if (teamStatsAsync?.hasError == true ||
          teamPlayersAsync?.hasError == true) {
        return const _TeamRecordBriefData(
          metrics: _BriefMetricSnapshot(
            avg: '-',
            avgRank: '확인 필요',
            era: '-',
            eraRank: '확인 필요',
          ),
          hasError: true,
        );
      }

      return const _TeamRecordBriefData(
        metrics: _BriefMetricSnapshot(
          avg: '-',
          avgRank: '불러오는 중',
          era: '-',
          eraRank: '불러오는 중',
        ),
        isLoading: true,
      );
    }

    return _TeamRecordBriefData(
      metrics: _BriefMetricSnapshot._fromTeamStats(teamStats),
      homeRunLeader: players == null
          ? null
          : _homeRunLeaderFromPlayers(players),
      risingPlayer: players == null ? null : _risingPlayerFromPlayers(players),
      isLoading: players == null && teamPlayersAsync?.hasError != true,
      hasError: teamPlayersAsync?.hasError == true,
    );
  }

  static _PlayerRecordHighlight? _homeRunLeaderFromPlayers(
    List<PlayerProfile> players,
  ) {
    PlayerProfile? leader;
    var leaderHomeRuns = 0;
    for (final player in players) {
      if (player.playerType != PlayerType.hitter || player.isRetired) {
        continue;
      }
      final homeRuns = _homeRunsForPlayer(player);
      if (homeRuns > leaderHomeRuns) {
        leader = player;
        leaderHomeRuns = homeRuns;
      }
    }
    if (leader == null || leaderHomeRuns <= 0) {
      return null;
    }
    return _PlayerRecordHighlight(
      name: leader.name,
      value: '$leaderHomeRuns홈런',
    );
  }

  static _PlayerRecordHighlight? _risingPlayerFromPlayers(
    List<PlayerProfile> players,
  ) {
    PlayerProfile? bestHitter;
    var bestHitterScore = -1.0;
    for (final player in players) {
      if (player.playerType != PlayerType.hitter || player.isRetired) {
        continue;
      }
      final score = player.ops ?? player.avg;
      if (score != null && score > bestHitterScore) {
        bestHitter = player;
        bestHitterScore = score;
      }
    }
    if (bestHitter != null && bestHitterScore >= 0) {
      final value = bestHitter.ops != null
          ? 'OPS ${bestHitter.ops!.toStringAsFixed(3)}'
          : 'AVG ${bestHitter.avg!.toStringAsFixed(3)}';
      return _PlayerRecordHighlight(name: bestHitter.name, value: value);
    }

    PlayerProfile? bestPitcher;
    var bestPitcherEra = 999.0;
    for (final player in players) {
      if (player.playerType != PlayerType.pitcher || player.isRetired) {
        continue;
      }
      final era = player.era;
      if (era != null && era < bestPitcherEra) {
        bestPitcher = player;
        bestPitcherEra = era;
      }
    }
    if (bestPitcher == null || bestPitcherEra >= 999) {
      return null;
    }
    return _PlayerRecordHighlight(
      name: bestPitcher.name,
      value: 'ERA ${bestPitcherEra.toStringAsFixed(2)}',
    );
  }

  static int _homeRunsForPlayer(PlayerProfile player) {
    final candidates = [
      ...player.seasonStats,
      player.headlineStat,
      player.secondaryStat,
      ...player.highlights,
    ];
    for (final candidate in candidates) {
      final text = candidate.trim();
      if (text.isEmpty) {
        continue;
      }
      final hrMatch = RegExp(
        r'(?:^|[\s·])HR\s*([0-9,]+)',
        caseSensitive: false,
      ).firstMatch(text);
      if (hrMatch != null) {
        return _parseInt(hrMatch.group(1));
      }
      final koreanMatch = RegExp(r'([0-9,]+)\s*홈런').firstMatch(text);
      if (koreanMatch != null) {
        return _parseInt(koreanMatch.group(1));
      }
    }
    return 0;
  }

  static int _parseInt(String? value) {
    if (value == null) {
      return 0;
    }
    return int.tryParse(value.replaceAll(',', '')) ?? 0;
  }
}

class _TeamRecordSpotlightRow extends StatelessWidget {
  final _TeamRecordBriefData recordBrief;

  const _TeamRecordSpotlightRow({required this.recordBrief});

  @override
  Widget build(BuildContext context) {
    final placeholderTitle = recordBrief.isLoading
        ? '불러오는 중'
        : recordBrief.hasError
        ? '확인 불가'
        : '집계 중';
    final placeholderSubtitle = recordBrief.isLoading
        ? '팀 기록 확인'
        : recordBrief.hasError
        ? '팀 기록 API'
        : '선수 기록 없음';

    return Row(
      children: [
        Expanded(
          child: _RecordSpotlightTile(
            icon: Icons.local_fire_department_rounded,
            label: '팀 홈런 1위',
            title: recordBrief.homeRunLeader?.name ?? placeholderTitle,
            subtitle: recordBrief.homeRunLeader?.value ?? placeholderSubtitle,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _RecordSpotlightTile(
            icon: Icons.trending_up_rounded,
            label: '뜨는 선수',
            title: recordBrief.risingPlayer?.name ?? placeholderTitle,
            subtitle: recordBrief.risingPlayer?.value ?? placeholderSubtitle,
          ),
        ),
      ],
    );
  }
}

class _RecordSpotlightTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String title;
  final String subtitle;

  const _RecordSpotlightTile({
    required this.icon,
    required this.label,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 68,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.background.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.divider.withValues(alpha: 0.8)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.ballYellow),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    color: AppColors.textDisabled,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w700,
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
        situation: '다음 경기 전까지 최근 5경기와 현재 순위를 먼저 확인하세요.',
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

  const _BriefTeamMark({
    required this.team,
    required this.fallbackLabel,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: KboTeamLogoImage(
        teamId: team?.id,
        fallback: fallbackLabel,
        size: size,
        padding: 0,
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

class _LiveMyTeamGameCard extends StatelessWidget {
  final Game game;
  final String myTeamId;
  final VoidCallback onOpenRelay;

  const _LiveMyTeamGameCard({
    required this.game,
    required this.myTeamId,
    required this.onOpenRelay,
  });

  @override
  Widget build(BuildContext context) {
    final isAway = game.away.teamId == myTeamId;
    final myTeam = isAway ? game.away : game.home;
    final opponent = isAway ? game.home : game.away;
    final myTeamInfo = KboTeams.byId(myTeam.teamId);
    final opponentInfo = KboTeams.byId(opponent.teamId);
    final colors = AppTheme.colorsOf(context);
    final accent = colors.readableAccent(
      myTeamInfo?.primaryColor ?? colors.live,
    );
    final inningText = game.inning.trim().isNotEmpty
        ? game.inning.trim()
        : game.statusLabel?.trim().isNotEmpty == true
        ? game.statusLabel!.trim()
        : 'LIVE';
    final stadiumText = game.stadium.trim().isEmpty ? '구장 미정' : game.stadium;

    return AppPressable(
      key: const ValueKey('home-live-my-team-game'),
      onTap: onOpenRelay,
      pressedScale: 0.988,
      child: _sectionCard(
        padding: const EdgeInsets.fromLTRB(13, 12, 13, 12),
        accentColor: AppColors.live,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.live.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: AppColors.live.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Text(
                    'LIVE',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    '내 경기 진행 중',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 23,
                  color: AppColors.textSecondary,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _LiveTeamScoreInline(
                    team: myTeamInfo,
                    fallbackLabel: myTeam.shortName,
                    score: myTeam.score,
                    highlighted: true,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 9),
                  child: Text(
                    ':',
                    style: TextStyle(
                      fontSize: 22,
                      height: 1,
                      color: accent,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Expanded(
                  child: _LiveTeamScoreInline(
                    team: opponentInfo,
                    fallbackLabel: opponent.shortName,
                    score: opponent.score,
                    alignEnd: true,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 9),
            Row(
              children: [
                Icon(
                  Icons.sports_baseball_rounded,
                  size: 15,
                  color: AppColors.live,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '$inningText · $stadiumText',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.live.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: AppColors.live.withValues(alpha: 0.34),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.notes_rounded,
                        size: 14,
                        color: AppColors.textPrimary,
                      ),
                      SizedBox(width: 4),
                      Text(
                        '문자중계 보기',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
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

class _LiveTeamScoreInline extends StatelessWidget {
  final KboTeam? team;
  final String fallbackLabel;
  final int score;
  final bool highlighted;
  final bool alignEnd;

  const _LiveTeamScoreInline({
    required this.team,
    required this.fallbackLabel,
    required this.score,
    this.highlighted = false,
    this.alignEnd = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);
    final accent = colors.readableAccent(team?.primaryColor ?? colors.live);
    final logo = _TeamLogo(
      team: team,
      fallbackLabel: fallbackLabel,
      size: 28,
      visualScale: 1.18,
    );
    final label = Expanded(
      child: Column(
        crossAxisAlignment: alignEnd
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          Text(
            fallbackLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14,
              color: highlighted ? accent : AppColors.textPrimary,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            highlighted ? '마이팀' : '상대팀',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
    final scoreText = Text(
      '$score',
      maxLines: 1,
      softWrap: false,
      style: TextStyle(
        fontSize: 24,
        height: 1,
        color: highlighted ? accent : AppColors.textPrimary,
        fontWeight: FontWeight.w900,
      ),
    );

    return Row(
      mainAxisAlignment: alignEnd
          ? MainAxisAlignment.end
          : MainAxisAlignment.start,
      children: alignEnd
          ? [
              scoreText,
              const SizedBox(width: 8),
              label,
              const SizedBox(width: 7),
              logo,
            ]
          : [
              logo,
              const SizedBox(width: 7),
              label,
              const SizedBox(width: 8),
              scoreText,
            ],
    );
  }
}

class _TodayGamesReferenceCard extends StatelessWidget {
  final List<Game> games;
  final List<Game> previousResultGames;
  final String? myTeamId;
  final List<TeamStanding> standings;
  final ValueChanged<Game> onOpenGame;

  const _TodayGamesReferenceCard({
    required this.games,
    required this.previousResultGames,
    required this.myTeamId,
    required this.standings,
    required this.onOpenGame,
  });

  @override
  Widget build(BuildContext context) {
    final orderedTodayGames = _orderedGames(games);
    final orderedPreviousGames = _orderedGames(previousResultGames);
    final hasPreviousResults = orderedPreviousGames.isNotEmpty;
    final standingsByTeamId = {
      for (final standing in standings) standing.teamId: standing,
    };
    final headerTitle = orderedTodayGames.isEmpty && hasPreviousResults
        ? '어제 결과'
        : '오늘 경기';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ReferenceSectionHeader(
          key: const ValueKey('home-today-games-header'),
          title: headerTitle,
          showAction: false,
        ),
        const SizedBox(height: 8),
        _sectionCard(
          key: const ValueKey('home-today-games-card'),
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (orderedTodayGames.isEmpty && orderedPreviousGames.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                  child: _ReferenceEmptyState(
                    title: '오늘은 경기가 없습니다',
                    subtitle: '일정과 순위를 먼저 확인할 수 있습니다.',
                    actionLabel: '일정 보기',
                    onAction: () => context.go('/schedule'),
                  ),
                )
              else ...[
                for (final entry in orderedTodayGames.indexed)
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
                    showDivider: entry.$1 < orderedTodayGames.length - 1,
                    onTap: () => onOpenGame(entry.$2),
                  ),
                if (orderedTodayGames.isNotEmpty && hasPreviousResults)
                  const _TodayGameGroupLabel(label: '어제 결과'),
                for (final entry in orderedPreviousGames.indexed)
                  _TodayGameReferenceRow(
                    key: ValueKey('home-previous-game-${entry.$2.gameId}'),
                    game: entry.$2,
                    awayRecord: _teamRecordText(
                      standingsByTeamId[entry.$2.away.teamId],
                    ),
                    homeRecord: _teamRecordText(
                      standingsByTeamId[entry.$2.home.teamId],
                    ),
                    isMyTeam: _isMyTeam(entry.$2),
                    showDivider: entry.$1 < orderedPreviousGames.length - 1,
                    onTap: () => onOpenGame(entry.$2),
                  ),
              ],
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

  List<Game> _orderedGames(List<Game> sourceGames) {
    final uniqueGames = _uniqueGamesById(sourceGames);
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

class _TodayGameGroupLabel extends StatelessWidget {
  final String label;

  const _TodayGameGroupLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: AppColors.divider.withValues(alpha: 0.55)),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          color: AppColors.textSecondary,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
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
                ? AppColors.live.withValues(alpha: 0.04)
                : Colors.transparent,
            border: Border(
              top: BorderSide(
                color: isMyTeam
                    ? AppColors.divider.withValues(alpha: 0.55)
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
                      style: TextStyle(
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
                      style: TextStyle(
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
            style: TextStyle(
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
    final rows = _flowRows();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ReferenceSectionHeader(title: '최근 5경기', showAction: false),
        const SizedBox(height: 8),
        _sectionCard(
          key: const ValueKey('home-standings-card'),
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isLoading)
                const Padding(
                  padding: EdgeInsets.all(14),
                  child: _ReferenceStatusLine(text: '최근 5경기 집계 중입니다.'),
                )
              else if (hasError)
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: _ReferenceEmptyState(
                    title: '최근 5경기를 불러오지 못했습니다',
                    subtitle: '순위 화면에서 다시 확인해 주세요.',
                    actionLabel: '순위 보기',
                    onAction: () => context.go('/standings'),
                  ),
                )
              else if (rows.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: _ReferenceEmptyState(
                    title: '표시할 최근 5경기가 없습니다',
                    subtitle: '순위 데이터가 준비되면 보여줍니다.',
                    actionLabel: '순위 보기',
                    onAction: () => context.go('/standings'),
                  ),
                )
              else
                for (final entry in rows.indexed)
                  _RecentFlowRow(
                    key: ValueKey('home-recent-flow-row-${entry.$2.teamId}'),
                    team: entry.$2.team,
                    teamLabel: entry.$2.teamLabel,
                    summaries: entry.$2.summaries,
                    trailingText: entry.$2.trailingText,
                    showDivider: entry.$1 < rows.length - 1,
                    onTap: entry.$2.teamId.isEmpty
                        ? null
                        : () {
                            HapticFeedback.selectionClick();
                            context.push('/records/team/${entry.$2.teamId}');
                          },
                  ),
            ],
          ),
        ),
      ],
    );
  }

  List<_RecentFlowEntry> _flowRows() {
    if (standings.isEmpty) {
      return const [];
    }

    final sorted = [...standings]..sort((a, b) => a.rank.compareTo(b.rank));
    return [
      for (final standing in sorted)
        if (standing.teamId == myTeamId &&
            brief != null &&
            brief!.recentSummaries.isNotEmpty)
          _flowEntryForMyTeam(standing, brief!)
        else
          _flowEntryForStanding(standing),
    ];
  }

  _RecentFlowEntry _flowEntryForMyTeam(
    TeamStanding standing,
    _MyTeamBriefData brief,
  ) {
    final team = KboTeams.byId(standing.teamId);
    return _RecentFlowEntry(
      teamId: standing.teamId,
      team: team,
      teamLabel: team?.shortName ?? brief.teamLabel,
      summaries: brief.recentSummaries,
      trailingText: _recentFlowTrailing(brief, standing),
    );
  }

  _RecentFlowEntry _flowEntryForStanding(TeamStanding standing) {
    final otherTeam = KboTeams.byId(standing.teamId);
    return _RecentFlowEntry(
      teamId: standing.teamId,
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
    final standingStreak = standing == null
        ? ''
        : _displayStreak(standing.streak, fallback: '');
    if (standingStreak.isNotEmpty) {
      return standingStreak;
    }
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
    return streak;
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
  final String teamId;
  final KboTeam? team;
  final String teamLabel;
  final List<_RecentGameSummaryData> summaries;
  final String trailingText;

  const _RecentFlowEntry({
    required this.teamId,
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
  final VoidCallback? onTap;

  const _RecentFlowRow({
    super.key,
    required this.team,
    required this.teamLabel,
    required this.summaries,
    required this.trailingText,
    required this.showDivider,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: onTap != null,
      label: onTap == null ? null : '$teamLabel 팀 기록 보기',
      child: AppPressable(
        onTap: onTap,
        pressedScale: 0.988,
        pressedOpacity: 0.82,
        child: SizedBox(
          height: 28,
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 2, 14, 2),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(
                  color: AppColors.divider.withValues(alpha: 0.55),
                ),
                bottom: showDivider
                    ? BorderSide(
                        color: AppColors.divider.withValues(alpha: 0.45),
                      )
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
                                (summary) => _ResultBubble(
                                  result: summary.result,
                                  size: 19,
                                ),
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
                          trailingText.contains('연승') ||
                              trailingText.contains('승')
                          ? AppColors.live
                          : AppColors.textSecondary,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
          ),
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
          key: const ValueKey('home-standings-header'),
          title: '순위',
          showAction: false,
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
                    key: ValueKey('home-standings-row-${standing.teamId}'),
                    standing: standing,
                    highlighted: standing.teamId == myTeamId,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      context.go('/standings');
                    },
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  List<TeamStanding> _visibleStandings(List<TeamStanding> standings) {
    return [...standings]..sort((a, b) => a.rank.compareTo(b.rank));
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
          _StandingCell('게임차', width: 44, muted: true),
        ],
      ),
    );
  }
}

class _StandingSnapshotRow extends StatelessWidget {
  final TeamStanding standing;
  final bool highlighted;
  final VoidCallback onTap;

  const _StandingSnapshotRow({
    super.key,
    required this.standing,
    required this.highlighted,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final team = KboTeams.byId(standing.teamId);
    final games = standing.wins + standing.losses + standing.draws;

    return Semantics(
      button: true,
      label: '${team?.shortName ?? standing.teamName} 순위 전체 보기',
      child: AppPressable(
        onTap: onTap,
        pressedScale: 0.99,
        pressedOpacity: 0.84,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 3, 14, 3),
          decoration: BoxDecoration(
            color: highlighted ? AppColors.live.withValues(alpha: 0.22) : null,
            border: Border(
              bottom: BorderSide(
                color: AppColors.divider.withValues(alpha: 0.5),
              ),
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
              _StandingCell(_gbLabel(standing.gb), width: 44),
            ],
          ),
        ),
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
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool showAction;

  const _ReferenceSectionHeader({
    super.key,
    required this.title,
    this.actionLabel,
    this.onAction,
    this.showAction = true,
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
        if (showAction && actionLabel != null && onAction != null)
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
                Text(actionLabel!, style: const TextStyle(fontSize: 12)),
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
                  style: TextStyle(
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
        style: TextStyle(
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
    return Transform.scale(
      scale: visualScale,
      child: KboTeamLogoImage(
        teamId: team?.id,
        fallback: fallbackLabel,
        size: size,
        padding: 0,
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
        style: TextStyle(
          fontSize: 12,
          color: AppColors.textSecondary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _KboBriefCard extends StatelessWidget {
  final HomeKboBrief brief;

  const _KboBriefCard({required this.brief});

  @override
  Widget build(BuildContext context) {
    final insightItems = _displayableKboBriefItems(brief);
    final featuredItem = _featuredKboBriefItem(insightItems);
    final topicItems = _topicKboBriefItems(insightItems);
    final miniItems = _miniKboBriefItems(insightItems, featuredItem);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ReferenceSectionHeader(
          title: '인사이트',
          actionLabel: '전체 보기',
          onAction: () => context.push('/news'),
        ),
        const SizedBox(height: 8),
        _sectionCard(
          padding: const EdgeInsets.fromLTRB(12, 13, 12, 12),
          backgroundAssetName: VisualAssets.liveRelayField,
          backgroundAlignment: Alignment.center,
          backgroundOpacity: 0.08,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 5, 8, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '오늘의 KBO 소식',
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0,
                        height: 1.12,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      insightItems.isEmpty
                          ? '오늘 체크할 장면을 준비 중입니다'
                          : '지금 볼 장면 ${insightItems.length}개',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              if (topicItems.isNotEmpty) ...[
                const SizedBox(height: 14),
                Column(
                  children: [
                    for (int index = 0; index < topicItems.length; index++)
                      Padding(
                        padding: EdgeInsets.only(top: index == 0 ? 0 : 8),
                        child: _KboInsightTopicCard(item: topicItems[index]),
                      ),
                  ],
                ),
              ],
              if (featuredItem != null) ...[
                const SizedBox(height: 10),
                _KboInsightScoreStrip(item: featuredItem),
              ],
              if (miniItems.isNotEmpty) ...[
                const SizedBox(height: 10),
                _KboInsightMiniGrid(items: miniItems),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _KboInsightTopicCard extends StatelessWidget {
  final HomeKboBriefItem item;

  const _KboInsightTopicCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final accent = _kboBriefAccent(item.type);
    return AppPressable(
      onTap: () => context.push(
        sanitizeAppRoute(item.route, fallback: '/news') ?? '/news',
      ),
      pressedScale: 0.985,
      child: Container(
        padding: const EdgeInsets.fromLTRB(11, 11, 10, 10),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border(
            top: BorderSide(color: accent.withValues(alpha: 0.85), width: 2),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _kboBriefShortTitle(item),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    _kboBriefBadgeLabel(item),
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _kboBriefCompactSubtitle(item),
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w700,
                      height: 1.25,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            _KboInsightItemVisual(item: item, accent: accent, size: 42),
          ],
        ),
      ),
    );
  }
}

class _KboInsightScoreStrip extends StatelessWidget {
  final HomeKboBriefItem item;

  const _KboInsightScoreStrip({required this.item});

  @override
  Widget build(BuildContext context) {
    final awayTeamId = item.teamIds.isNotEmpty ? item.teamIds.first : null;
    final homeTeamId = item.teamIds.length > 1 ? item.teamIds[1] : null;
    final awayTeam = KboTeams.byId(awayTeamId ?? '');
    final homeTeam = KboTeams.byId(homeTeamId ?? '');
    final score = _parseKboBriefScoreTitle(item.title);
    final isLive = _kboBriefScoreStripIsLive(item);
    final statusLabel = isLive ? 'LIVE' : _kboBriefBadgeLabel(item);
    final statusColor = isLive ? AppColors.live : AppColors.textSecondary;

    return AppPressable(
      onTap: () => context.push(
        sanitizeAppRoute(item.route, fallback: '/news') ?? '/news',
      ),
      pressedScale: 0.988,
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
        decoration: BoxDecoration(
          color: AppColors.cardSub.withValues(alpha: 0.78),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.divider),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: isLive
                        ? AppColors.live
                        : AppColors.cardSub.withValues(alpha: 0.92),
                    borderRadius: BorderRadius.circular(6),
                    border: isLive
                        ? null
                        : Border.all(color: AppColors.divider),
                  ),
                  child: Text(
                    statusLabel,
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                if (awayTeam != null)
                  _TeamLogo(
                    team: awayTeam,
                    fallbackLabel: awayTeam.shortName,
                    size: 30,
                  ),
                const SizedBox(width: 7),
                Text(
                  score.awayLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  fit: FlexFit.tight,
                  child: Text(
                    score.value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  score.homeLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 7),
                if (homeTeam != null)
                  _TeamLogo(
                    team: homeTeam,
                    fallbackLabel: homeTeam.shortName,
                    size: 30,
                  ),
                const SizedBox(width: 8),
                Text(
                  _kboBriefTimeLabel(item),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: statusColor,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            if (isLive) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        _ScoreDotGroup(label: 'B', active: 3, total: 3),
                        SizedBox(width: 14),
                        _ScoreDotGroup(label: 'S', active: 2, total: 2),
                        SizedBox(width: 14),
                        _ScoreDotGroup(label: 'O', active: 2, total: 2),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  const _BaseDiamond(),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

bool _kboBriefScoreStripIsLive(HomeKboBriefItem item) {
  return item.type == 'league_now' ||
      item.eyebrow.contains('LIVE') ||
      item.eyebrow.contains('진행 중');
}

class _ScoreDotGroup extends StatelessWidget {
  final String label;
  final int active;
  final int total;

  const _ScoreDotGroup({
    required this.label,
    required this.active,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    final dotColor = label == 'S' ? AppColors.ballYellow : AppColors.positive;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(width: 4),
        for (var index = 0; index < total; index++) ...[
          Icon(
            Icons.circle,
            size: 7,
            color: index < active
                ? dotColor
                : AppColors.textDisabled.withValues(alpha: 0.35),
          ),
          if (index < total - 1) const SizedBox(width: 3),
        ],
      ],
    );
  }
}

class _BaseDiamond extends StatelessWidget {
  const _BaseDiamond();

  @override
  Widget build(BuildContext context) {
    Widget base(Color color) {
      return Transform.rotate(
        angle: 0.785398,
        child: Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color),
        ),
      );
    }

    return SizedBox(
      width: 28,
      height: 24,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(top: 1, child: base(AppColors.ballYellow)),
          Positioned(left: 3, bottom: 3, child: base(AppColors.textPrimary)),
          Positioned(right: 3, bottom: 3, child: base(AppColors.textPrimary)),
        ],
      ),
    );
  }
}

class _KboInsightMiniGrid extends StatelessWidget {
  final List<HomeKboBriefItem> items;

  const _KboInsightMiniGrid({required this.items});

  @override
  Widget build(BuildContext context) {
    final visibleItems = items.take(4).toList();
    return Column(
      children: [
        for (int index = 0; index < visibleItems.length; index++)
          Padding(
            padding: EdgeInsets.only(top: index == 0 ? 0 : 8),
            child: _KboInsightMiniCard(item: visibleItems[index]),
          ),
      ],
    );
  }
}

class _KboInsightMiniCard extends StatelessWidget {
  final HomeKboBriefItem item;

  const _KboInsightMiniCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final accent = _kboBriefAccent(item.type);
    return AppPressable(
      onTap: () => context.push(
        sanitizeAppRoute(item.route, fallback: '/news') ?? '/news',
      ),
      pressedScale: 0.985,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.cardSub.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.divider),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _kboBriefShortTitle(item),
                    style: TextStyle(
                      fontSize: 14,
                      color: accent,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    item.title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      height: 1.18,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _kboBriefCompactSubtitle(item),
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w700,
                      height: 1.25,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            _KboInsightItemVisual(item: item, accent: accent, size: 44),
          ],
        ),
      ),
    );
  }
}

class _KboInsightItemVisual extends StatelessWidget {
  final HomeKboBriefItem item;
  final Color accent;
  final double size;

  const _KboInsightItemVisual({
    required this.item,
    required this.accent,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    final imageUrl = item.imageUrl;
    final team = _kboBriefVisualTeam(item);
    if (imageUrl != null && imageUrl.isNotEmpty) {
      final cacheSize = kboPlayerImageCacheSize(size);
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: CachedNetworkImage(
          imageUrl: imageUrl,
          httpHeaders: kboPlayerImageHeaders,
          cacheManager: kboPlayerImageCacheManager,
          width: size,
          height: size,
          memCacheWidth: cacheSize,
          memCacheHeight: cacheSize,
          maxWidthDiskCache: cacheSize,
          maxHeightDiskCache: cacheSize,
          fit: BoxFit.cover,
          placeholder: (_, _) => _fallback(),
          errorWidget: (_, _, _) => _fallback(),
        ),
      );
    }
    if (team != null) {
      return KboTeamLogoImage(
        key: ValueKey('kbo-brief-team-logo-${item.type}-${team.id}'),
        teamId: team.id,
        fallback: team.shortName,
        size: size,
        padding: 0,
      );
    }
    return _fallback();
  }

  KboTeam? _kboBriefVisualTeam(HomeKboBriefItem item) {
    if (item.teamIds.isEmpty) {
      return null;
    }
    final teamId = item.teamIds.first;
    final label = item.fallbackLabel ?? item.title;
    return KboTeams.resolve(id: teamId, name: label, shortName: label);
  }

  Widget _fallback() {
    final label = (item.fallbackLabel ?? item.title).trim();
    final initial = label.isEmpty ? '' : label.characters.first;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accent.withValues(alpha: 0.32)),
      ),
      alignment: Alignment.center,
      child: initial.isNotEmpty
          ? Text(
              initial,
              style: TextStyle(
                color: accent,
                fontSize: size * 0.36,
                fontWeight: FontWeight.w900,
              ),
            )
          : Icon(_kboBriefIcon(item.type), size: size * 0.66, color: accent),
    );
  }
}

List<HomeKboBriefItem> _displayableKboBriefItems(HomeKboBrief brief) {
  return brief.items
      .where((item) => item.type != 'schedule_remaining')
      .take(8)
      .toList();
}

HomeKboBriefItem? _featuredKboBriefItem(List<HomeKboBriefItem> items) {
  for (final item in items) {
    if (item.type == 'game_flow') return item;
  }
  for (final item in items) {
    if (item.type == 'big_match') return item;
  }
  return items.isEmpty ? null : items.first;
}

List<HomeKboBriefItem> _topicKboBriefItems(List<HomeKboBriefItem> items) {
  final preferredTypes = ['game_flow', 'standings', 'record_radar'];
  final ordered = <HomeKboBriefItem>[];
  for (final type in preferredTypes) {
    final match = items.where((item) => item.type == type).firstOrNull;
    if (match != null && !ordered.contains(match)) {
      ordered.add(match);
    }
  }
  for (final item in items) {
    if (ordered.length >= 3) break;
    if (!ordered.contains(item)) ordered.add(item);
  }
  return ordered.take(3).toList();
}

List<HomeKboBriefItem> _miniKboBriefItems(
  List<HomeKboBriefItem> items,
  HomeKboBriefItem? featuredItem,
) {
  final preferredTypes = [
    'player_performance',
    'team_trend',
    'record_radar',
    'pitcher_check',
  ];
  final ordered = <HomeKboBriefItem>[];
  for (final type in preferredTypes) {
    final match = items
        .where((item) => item.type == type && !identical(item, featuredItem))
        .firstOrNull;
    if (match != null) {
      ordered.add(match);
    }
  }
  for (final item in items) {
    if (ordered.length >= 4) break;
    if (!identical(item, featuredItem) && !ordered.contains(item)) {
      ordered.add(item);
    }
  }
  return ordered.take(4).toList();
}

_KboBriefScore _parseKboBriefScoreTitle(String title) {
  final match = RegExp(
    r'^(.+?)\s+([0-9]+)\s*:\s*([0-9]+)\s+(.+)$',
  ).firstMatch(title);
  if (match == null) {
    return _KboBriefScore(awayLabel: '', value: title, homeLabel: '');
  }
  return _KboBriefScore(
    awayLabel: match.group(1)?.trim() ?? '',
    value: '${match.group(2)} : ${match.group(3)}',
    homeLabel: match.group(4)?.trim() ?? '',
  );
}

class _KboBriefScore {
  final String awayLabel;
  final String value;
  final String homeLabel;

  const _KboBriefScore({
    required this.awayLabel,
    required this.value,
    required this.homeLabel,
  });
}

String _kboBriefShortTitle(HomeKboBriefItem item) {
  if (item.eyebrow.contains('접전')) return '접전';
  if (item.eyebrow.contains('순위') || item.eyebrow.contains('선두')) {
    return '순위';
  }
  if (item.eyebrow.contains('기록')) return '기록';
  if (item.eyebrow.contains('실책')) return '실책';
  if (item.eyebrow.contains('타율')) return '타율';
  if (item.eyebrow.contains('일정')) return '일정';
  if (item.eyebrow.contains('안타') || item.eyebrow.contains('타격')) {
    return '승부처';
  }
  if (item.eyebrow.contains('선발')) return '선발 체크';
  if (item.eyebrow.contains('LIVE')) return 'LIVE';
  return item.eyebrow;
}

String _kboBriefCompactSubtitle(HomeKboBriefItem item) {
  final parts = item.subtitle
      .split('·')
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty)
      .toList();
  if (parts.isEmpty) {
    return item.subtitle;
  }
  return parts.take(2).join(' · ');
}

String _kboBriefTimeLabel(HomeKboBriefItem item) {
  final match = RegExp(r'([0-9]+회[초말]?)').firstMatch(item.subtitle);
  return match?.group(1) ?? _kboBriefBadgeLabel(item);
}

Color _kboBriefAccent(String type) {
  switch (type) {
    case 'game_flow':
      return AppColors.live;
    case 'player_performance':
    case 'defense_issue':
    case 'defense_rank':
      return AppColors.positive;
    case 'batting_leader':
    case 'record_radar':
      return AppColors.ballYellow;
    case 'standings':
    case 'team_trend':
      return AppColors.accent;
    case 'pitcher_check':
      return AppColors.positive;
    case 'big_match':
    case 'league_now':
      return AppColors.textPrimary;
    case 'offday':
      return AppColors.textSecondary;
    default:
      return AppColors.textSecondary;
  }
}

IconData _kboBriefIcon(String type) {
  switch (type) {
    case 'game_flow':
      return Icons.sports_baseball_rounded;
    case 'player_performance':
    case 'defense_issue':
    case 'defense_rank':
      return Icons.local_fire_department_rounded;
    case 'batting_leader':
    case 'record_radar':
      return Icons.auto_graph_rounded;
    case 'standings':
      return Icons.leaderboard_rounded;
    case 'team_trend':
      return Icons.show_chart_rounded;
    case 'pitcher_check':
      return Icons.speed_rounded;
    case 'big_match':
      return Icons.event_available_rounded;
    case 'league_now':
      return Icons.insights_rounded;
    case 'offday':
      return Icons.calendar_today_rounded;
    default:
      return Icons.notes_rounded;
  }
}

String _kboBriefBadgeLabel(HomeKboBriefItem item) {
  switch (item.type) {
    case 'game_flow':
      if (item.eyebrow.contains('접전')) return '접전';
      if (item.eyebrow.contains('득점')) return '공방';
      return '경기';
    case 'standings':
      final gapMatch = RegExp(r'([0-9.]+G)').firstMatch(item.subtitle);
      return gapMatch?.group(1) ?? '순위';
    case 'record_radar':
      final valueMatch = RegExp(r'([0-9]+)').firstMatch(item.title);
      return valueMatch == null ? 'TOP' : '${valueMatch.group(1)}개';
    case 'batting_leader':
      return '타율';
    case 'player_performance':
      return '타격';
    case 'defense_issue':
    case 'defense_rank':
      return '실책';
    case 'pitcher_check':
      return '선발';
    case 'team_trend':
      return '흐름';
    case 'league_now':
      return 'LIVE';
    case 'big_match':
      return '예정';
    default:
      return '체크';
  }
}

class _QuickContentSection extends StatelessWidget {
  final List<_QuickContentItemData> items;

  const _QuickContentSection({required this.items});

  @override
  Widget build(BuildContext context) {
    final visibleItems = items.take(4).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ReferenceSectionHeader(
          title: '지금 보면 좋은 정보',
          actionLabel: '더보기',
          onAction: () => context.push('/news'),
        ),
        const SizedBox(height: 8),
        Column(
          children: [
            for (int index = 0; index < visibleItems.length; index++)
              Padding(
                padding: EdgeInsets.only(top: index == 0 ? 0 : 10),
                child: _QuickContentListItem(item: visibleItems[index]),
              ),
          ],
        ),
      ],
    );
  }
}

class _QuickContentListItem extends ConsumerWidget {
  final _QuickContentItemData item;

  const _QuickContentListItem({required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accent = _quickItemAccent(item);
    final playerRoute = _PlayerQuickRoute.tryParse(item.route);

    return AppPressable(
      onTap: () => _handleTap(context, ref, playerRoute),
      pressedScale: 0.985,
      child: Container(
        clipBehavior: Clip.antiAlias,
        padding: const EdgeInsets.fromLTRB(13, 12, 13, 12),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.divider),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    item.eyebrow,
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w900,
                      height: 1.18,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '더보기',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textDisabled,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: AppColors.textDisabled,
                ),
              ],
            ),
            const SizedBox(height: 11),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          height: 1.18,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        item.subtitle,
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                          height: 1.35,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                _quickItemAvatar(context, item, accent),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _quickItemCta(item),
                    style: TextStyle(
                      fontSize: 12,
                      color: accent,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Icon(Icons.chevron_right_rounded, size: 18, color: accent),
              ],
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
      context.push(sanitizeAppRoute(item.route, fallback: '/news') ?? '/news');
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
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                child: playerAsync.when(
                  loading: () => SizedBox(
                    height: 220,
                    child: Center(
                      child: CircularProgressIndicator(color: AppColors.live),
                    ),
                  ),
                  error: (error, stackTrace) => Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _playerBottomSheetHeader(context, item: item),
                      const SizedBox(height: 12),
                      Text(
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
                  data: (player) {
                    final recentGames = player.recentGames.take(5).toList();
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _playerBottomSheetHeader(
                          context,
                          item: item,
                          playerName: player.name,
                        ),
                        const SizedBox(height: 14),
                        const Text(
                          '최근 5경기',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 10),
                        if (recentGames.isEmpty)
                          Text(
                            '최근 5경기 기록이 없습니다',
                            style: TextStyle(
                              fontSize: 13,
                              color: AppColors.textSecondary,
                            ),
                          )
                        else
                          ...recentGames.map(_playerRecentGameCard),
                        const SizedBox(height: 6),
                        _playerBottomSheetButton(context),
                      ],
                    );
                  },
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _playerBottomSheetHeader(
    BuildContext context, {
    required _QuickContentItemData item,
    String? playerName,
  }) {
    final accent = _quickItemAccent(item);
    return Row(
      children: [
        _quickItemAvatar(context, item, accent),
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
                style: TextStyle(
                  fontSize: 18,
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                item.subtitle,
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _playerRecentGameCard(PlayerRecentGame game) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.cardSub,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.divider),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    game.date,
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'vs ${game.opponent}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 7),
            Text(
              game.summary,
              style: TextStyle(
                fontSize: 13,
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _playerBottomSheetButton(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: () {
          Navigator.of(context).pop();
          context.push(
            sanitizeAppRoute(item.route, fallback: '/records') ?? '/records',
          );
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
  Key? key,
  required Widget child,
  EdgeInsetsGeometry padding = const EdgeInsets.all(16),
  Color? accentColor,
  String? backgroundAssetName,
  Alignment backgroundAlignment = Alignment.center,
  double backgroundOpacity = 0.22,
}) {
  return Container(
    key: key,
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
  if (key.contains('기록')) return AppColors.ballYellow;
  if (key.contains('예매')) return AppColors.ballYellow;
  if (key.contains('일정')) return AppColors.textPrimary;
  if (key.contains('마이팀')) return AppColors.accent;
  if (key.contains('순위')) return AppColors.accent;
  if (key.contains('오늘의 플레이어') || key.contains('오늘의 선수')) {
    return AppColors.positive;
  }
  return AppColors.textSecondary;
}

String _quickItemIcon(_QuickContentItemData item) {
  final key = item.eyebrow;
  if (key.contains('홈런')) return 'HR';
  if (key.contains('기록')) return 'R';
  if (key.contains('예매')) return 'T';
  if (key.contains('일정')) return 'S';
  if (key.contains('마이팀 경기')) return 'G';
  if (key.contains('마이팀 하이라이트')) return 'V';
  if (key.contains('오늘의 플레이어') || key.contains('오늘의 선수')) return 'P';
  if (key.contains('순위')) return 'R';
  return '•';
}

String _quickItemCta(_QuickContentItemData item) {
  final key = item.eyebrow;
  if (key.contains('마이팀 경기')) return '경기 상세';
  if (key.contains('일정')) return '일정 보기';
  if (key.contains('순위')) return '전체 순위';
  if (key.contains('홈런') || key.contains('기록')) return '전체 기록';
  if (key.contains('오늘의 플레이어') || key.contains('오늘의 선수')) {
    return '선수 상세';
  }
  if (item.route.contains('/schedule')) return '일정 보기';
  return '자세히 보기';
}

Widget _quickItemAvatar(
  BuildContext context,
  _QuickContentItemData item,
  Color accent,
) {
  final colors = AppTheme.colorsOf(context);
  final team = KboTeams.resolve(
    id: item.teamId,
    name: item.fallbackLabel,
    shortName: item.fallbackLabel,
  );
  final imageUrl = item.imageUrl;

  if (imageUrl != null && imageUrl.isNotEmpty) {
    final cacheSize = kboPlayerImageCacheSize(52);
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: CachedNetworkImage(
        imageUrl: imageUrl,
        httpHeaders: kboPlayerImageHeaders,
        cacheManager: kboPlayerImageCacheManager,
        width: 52,
        height: 52,
        memCacheWidth: cacheSize,
        memCacheHeight: cacheSize,
        maxWidthDiskCache: cacheSize,
        maxHeightDiskCache: cacheSize,
        fit: BoxFit.cover,
        errorWidget: (_, _, _) =>
            _quickItemAvatarFallback(item, accent, team, colors),
        placeholder: (_, _) =>
            _quickItemAvatarFallback(item, accent, team, colors),
      ),
    );
  }

  if (team != null) {
    return KboTeamLogoImage(
      teamId: team.id,
      fallback: team.shortName,
      size: 52,
      padding: 0,
    );
  }

  return _quickItemAvatarFallback(item, accent, team, colors);
}

Widget _quickItemAvatarFallback(
  _QuickContentItemData item,
  Color accent,
  KboTeam? team,
  AppThemeColors colors,
) {
  final label = (item.fallbackLabel ?? item.title).trim();
  final initial = label.isEmpty ? _quickItemIcon(item) : label.characters.first;
  final foreground = colors.readableAccent(team?.primaryColor ?? accent);
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
        color: foreground,
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
