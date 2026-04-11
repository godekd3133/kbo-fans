import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import '../../core/constants/team_data.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/game_status_label.dart';
import '../../data/models/game.dart';
import '../../data/models/highlight_video.dart';
import '../../data/providers.dart';
import '../../services/ticket_alert_service.dart';
import 'tabs/boxscore_tab.dart';
import 'tabs/lineup_tab.dart';
import 'tabs/relay_tab.dart';
import 'tabs/score_tab.dart';

const _kboImageHeaders = {
  'Referer': 'https://www.koreabaseball.com/',
  'User-Agent':
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36',
};

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

class GameDetailScreen extends ConsumerWidget {
  final String gameId;
  final Game? game;
  final String? initialTab;

  const GameDetailScreen({
    super.key,
    required this.gameId,
    this.game,
    this.initialTab,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gameAsync = ref.watch(gameProvider(gameId));

    return gameAsync.when(
      loading: () {
        if (game != null) {
          return _GameDetailBody(
            game: game!,
            gameId: gameId,
            initialTabIndex: _tabIndexFromName(initialTab),
          );
        }
        return const Scaffold(
          body: SafeArea(
            child: Center(
              child: CircularProgressIndicator(color: AppColors.live),
            ),
          ),
        );
      },
      error: (_, _) => Scaffold(
        appBar: AppBar(title: const Text('경기 상세')),
        body: Center(
          child: Text(game != null ? '최신 경기 정보를 불러올 수 없습니다' : '경기를 불러올 수 없습니다'),
        ),
      ),
      data: (loadedGame) {
        final resolvedGame = loadedGame ?? game;
        if (resolvedGame == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('경기 상세')),
            body: const Center(child: Text('경기를 찾을 수 없습니다')),
          );
        }

        return _GameDetailBody(
          game: resolvedGame,
          gameId: gameId,
          initialTabIndex: _tabIndexFromName(initialTab),
        );
      },
    );
  }
}

class _GameDetailBody extends ConsumerStatefulWidget {
  final String gameId;
  final Game game;
  final int initialTabIndex;

  const _GameDetailBody({
    required this.gameId,
    required this.game,
    this.initialTabIndex = 0,
  });

  @override
  ConsumerState<_GameDetailBody> createState() => _GameDetailBodyState();
}

class _GameDetailBodyState extends ConsumerState<_GameDetailBody>
    with WidgetsBindingObserver {
  Timer? _refreshTimer;
  bool _didInitialRefresh = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startRefreshTimer();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _didInitialRefresh) {
        return;
      }
      _didInitialRefresh = true;
      unawaited(_refreshGameDetail());
    });
  }

  @override
  void didUpdateWidget(covariant _GameDetailBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.gameId != widget.gameId ||
        oldWidget.game.status != widget.game.status) {
      _refreshTimer?.cancel();
      _startRefreshTimer();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startRefreshTimer();
      unawaited(_refreshGameDetail());
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
    _refreshTimer?.cancel();
    final interval = widget.game.status == GameStatus.live
        ? const Duration(seconds: 10)
        : const Duration(seconds: 15);
    _refreshTimer = Timer.periodic(interval, (_) {
      if (!mounted || ModalRoute.of(context)?.isCurrent != true) {
        return;
      }
      unawaited(_refreshGameDetail());
    });
  }

  Future<void> _refreshGameDetail() async {
    final gameId = widget.gameId;

    ref.invalidate(gameProvider(gameId));
    ref.invalidate(relayDataProvider(gameId));
    ref.invalidate(gameBoxscoreProvider(gameId));
    ref.invalidate(gameLineupProvider(gameId));

    await Future.wait([
      ref.read(gameProvider(gameId).future),
      ref.read(relayDataProvider(gameId).future),
      ref.read(gameBoxscoreProvider(gameId).future),
      ref.read(gameLineupProvider(gameId).future),
    ]);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final game = widget.game;
    final gameId = widget.gameId;
    final isLive = game.status == GameStatus.live;
    final showTicketInfo =
        game.ticketInfo != null && !isTerminalGameStatus(game.status);
    const tabBar = TabBar(
      isScrollable: true,
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
    );

    return DefaultTabController(
      length: 4,
      initialIndex: widget.initialTabIndex.clamp(0, 3),
      child: Scaffold(
        body: SafeArea(
          child: NestedScrollView(
            headerSliverBuilder: (context, innerBoxIsScrolled) => [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back, size: 24),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      Expanded(
                        child: Text(
                          _displayStadiumName(game.stadium),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
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
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: _teamSection(
                          game.away.teamId,
                          game.away.shortName,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Column(
                        children: [
                          Text(
                            '${game.away.score} : ${game.home.score}',
                            style: const TextStyle(
                              fontSize: 36,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 4,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            secondaryTextForGameStatus(
                              game.status,
                              inning: game.inning,
                              startTime: game.startTime,
                            ),
                            style: TextStyle(
                              fontSize: 14,
                              color: isLive
                                  ? AppColors.live
                                  : AppColors.textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _teamSection(
                          game.home.teamId,
                          game.home.shortName,
                        ),
                      ),
                    ],
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
              if (game.status == GameStatus.final_)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: _HighlightSection(game: game, gameId: gameId),
                  ),
                ),
              SliverPersistentHeader(
                pinned: true,
                delegate: _TabBarHeaderDelegate(tabBar),
              ),
            ],
            body: TabBarView(
              children: [
                ScoreTab(
                  gameId: gameId,
                  game: game,
                  onRefresh: _refreshGameDetail,
                ),
                RelayTab(
                  gameId: gameId,
                  gameStatus: game.status,
                  game: game,
                  onRefresh: _refreshGameDetail,
                ),
                BoxscoreTab(
                  gameId: gameId,
                  game: game,
                  gameStatus: game.status,
                  awayName: game.away.shortName,
                  homeName: game.home.shortName,
                  awayTeamId: game.away.teamId,
                  homeTeamId: game.home.teamId,
                  onRefresh: _refreshGameDetail,
                ),
                LineupTab(
                  gameId: gameId,
                  gameStatus: game.status,
                  awayName: game.away.shortName,
                  homeName: game.home.shortName,
                  awayTeamId: game.away.teamId,
                  homeTeamId: game.home.teamId,
                  onRefresh: _refreshGameDetail,
                ),
              ],
            ),
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
          httpHeaders: _kboImageHeaders,
          width: 48,
          height: 48,
          placeholder: (_, _) => Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.cardSub,
              shape: BoxShape.circle,
            ),
          ),
          errorWidget: (_, _, _) => Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.cardSub,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                shortName,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          shortName,
          style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
        ),
      ],
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
        borderRadius: BorderRadius.circular(14),
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
                    side: const BorderSide(color: AppColors.divider),
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
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
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
        borderRadius: BorderRadius.circular(14),
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
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  )
                else
                  const Text(
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
                        side: const BorderSide(color: AppColors.divider),
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
          borderRadius: BorderRadius.circular(12),
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
            InkWell(
              onTap: isPlayable
                  ? () => _playInline(video.videoId)
                  : () => _openUrl(video.videoUrl),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (thumbnailUrl.isNotEmpty)
                      CachedNetworkImage(
                        imageUrl: thumbnailUrl,
                        fit: BoxFit.cover,
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
                    const Text(
                      '앱 밖에서 유튜브 검색 결과를 엽니다.',
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
      child: const Icon(
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
          CachedNetworkImage(
            imageUrl: team?.logoUrl ?? '',
            width: 34,
            height: 34,
            errorWidget: (_, _, _) => _teamBadgeFallback(shortName),
            placeholder: (_, _) => _teamBadgeFallback(shortName),
          ),
          const SizedBox(height: 6),
          Text(
            shortName,
            style: const TextStyle(
              fontSize: 12,
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
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            child: Column(
              children: [
                const Align(
                  alignment: Alignment.topLeft,
                  child: Text(
                    'YOUTUBE SEARCH',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textDisabled,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
                const Spacer(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    teamBadge(awayTeam, widget.game.away.shortName),
                    const Text(
                      'VS',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textDisabled,
                      ),
                    ),
                    teamBadge(homeTeam, widget.game.home.shortName),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  '${widget.game.away.shortName} vs ${widget.game.home.shortName}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  '유튜브 검색 결과로 이동',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
                const Spacer(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _teamBadgeFallback(String shortName) {
    final initial = shortName.isNotEmpty ? shortName.substring(0, 1) : '?';
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: AppColors.background.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(10),
      ),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w800,
          color: AppColors.textPrimary,
        ),
      ),
    );
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    final mode = kIsWeb
        ? LaunchMode.platformDefault
        : LaunchMode.externalApplication;
    await launchUrl(uri, mode: mode);
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
    return Material(
      color: selected ? AppColors.textPrimary : Colors.transparent,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
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

class _HighlightSection extends ConsumerWidget {
  final Game game;
  final String gameId;

  const _HighlightSection({required this.game, required this.gameId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final highlightAsync = ref.watch(highlightInfoProvider(gameId));

    final mergedGame = Game(
      gameId: game.gameId,
      status: game.status,
      inning: game.inning,
      away: game.away,
      home: game.home,
      stadium: game.stadium,
      startTime: game.startTime,
      crowd: game.crowd,
      ticketInfo: game.ticketInfo,
      highlightInfo: highlightAsync.asData?.value ?? game.highlightInfo,
    );

    if (highlightAsync.isLoading && mergedGame.highlightInfo == null) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.divider),
        ),
        child: const Row(
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.live,
              ),
            ),
            SizedBox(width: 12),
            Text('하이라이트 불러오는 중'),
          ],
        ),
      );
    }

    if (mergedGame.highlightInfo == null) {
      return const SizedBox.shrink();
    }

    return _HighlightCard(game: mergedGame, gameId: gameId);
  }
}

class _TabBarHeaderDelegate extends SliverPersistentHeaderDelegate {
  final TabBar tabBar;

  const _TabBarHeaderDelegate(this.tabBar);

  @override
  double get minExtent => tabBar.preferredSize.height + 1;

  @override
  double get maxExtent => tabBar.preferredSize.height + 1;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return DecoratedBox(
      decoration: const BoxDecoration(color: AppColors.background),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          tabBar,
          const Divider(height: 1, color: AppColors.divider),
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _TabBarHeaderDelegate oldDelegate) {
    return oldDelegate.tabBar != tabBar;
  }
}
