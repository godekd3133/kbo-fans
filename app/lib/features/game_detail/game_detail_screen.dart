import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import '../../core/constants/team_data.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/game.dart';
import '../../data/providers.dart';
import '../../services/ticket_alert_service.dart';
import 'tabs/boxscore_tab.dart';
import 'tabs/lineup_tab.dart';
import 'tabs/relay_tab.dart';
import 'tabs/score_tab.dart';

class GameDetailScreen extends ConsumerWidget {
  final String gameId;
  final Game? game;

  const GameDetailScreen({super.key, required this.gameId, this.game});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gameAsync = game != null
        ? AsyncValue.data(game)
        : ref.watch(gameProvider(gameId));

    return gameAsync.when(
      loading: () => const Scaffold(
        body: SafeArea(
          child: Center(
            child: CircularProgressIndicator(color: AppColors.live),
          ),
        ),
      ),
      error: (_, _) => Scaffold(
        appBar: AppBar(title: const Text('경기 상세')),
        body: const Center(child: Text('경기를 불러올 수 없습니다')),
      ),
      data: (loadedGame) {
        if (loadedGame == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('경기 상세')),
            body: const Center(child: Text('경기를 찾을 수 없습니다')),
          );
        }

        return _GameDetailBody(game: loadedGame, gameId: gameId);
      },
    );
  }
}

class _GameDetailBody extends ConsumerWidget {
  final String gameId;
  final Game game;

  const _GameDetailBody({required this.gameId, required this.game});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isLive = game.status == GameStatus.live;

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
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
                        '${game.stadium}${game.crowd != null ? " · ${_formatNumber(game.crowd!)}명" : ""}',
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
              Padding(
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
                          game.inning.isEmpty
                              ? '${game.startTime} 예정'
                              : game.inning,
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
              if (game.ticketInfo != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: _TicketInfoCard(game: game),
                ),
              if (game.highlightInfo != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: _HighlightCard(game: game),
                ),
              const TabBar(
                isScrollable: true,
                indicatorColor: AppColors.textPrimary,
                indicatorWeight: 2,
                labelColor: AppColors.textPrimary,
                labelStyle: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
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
              Expanded(
                child: TabBarView(
                  children: [
                    ScoreTab(gameId: gameId, game: game),
                    RelayTab(gameId: gameId, gameStatus: game.status),
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
          width: 40,
          height: 40,
          placeholder: (_, _) => Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.cardSub,
              shape: BoxShape.circle,
            ),
          ),
          errorWidget: (_, _, _) => Container(
            width: 40,
            height: 40,
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
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
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
              const Spacer(),
              if (ticket.isInferred)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.cardSub,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    '정책 기준',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          _infoRow('예매처', ticket.vendorName),
          _infoRow('예매 시작', _formatTicketTime(ticket.openAt)),
          if (ticket.note != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                ticket.note!,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textDisabled,
                ),
              ),
            ),
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
                              : LaunchMode.inAppBrowserView;
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

  const _HighlightCard({required this.game});

  @override
  State<_HighlightCard> createState() => _HighlightCardState();
}

class _HighlightCardState extends State<_HighlightCard> {
  YoutubePlayerController? _controller;
  String? _playingVideoId;

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
              child: YoutubePlayer(
                controller: _controller!,
                aspectRatio: 16 / 9,
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
                  const Text(
                    '여러 영상을 좌우로 넘기면서 바로 재생할 수 있습니다.',
                    style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  )
                else
                  const Text(
                    '공식 하이라이트 페이지에서 확인할 수 있습니다.',
                    style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                const SizedBox(height: 12),
                if (videos.isNotEmpty)
                  SizedBox(
                    height: 220,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: videos.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 12),
                      itemBuilder: (context, index) => _videoCard(videos[index]),
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
                        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
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

  Widget _videoCard(video) {
    final isPlayable = video.videoId.isNotEmpty;
    return SizedBox(
      width: 260,
      child: GestureDetector(
        onTap: isPlayable ? () => _playInline(video.videoId) : () => _openUrl(video.videoUrl),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.cardSub,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _playingVideoId == video.videoId ? AppColors.live : AppColors.divider,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 16 / 9,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if ((video.thumbnailUrl).isNotEmpty)
                      CachedNetworkImage(
                        imageUrl: video.thumbnailUrl,
                        fit: BoxFit.cover,
                        errorWidget: (_, _, _) => _thumbnailFallback(),
                        placeholder: (_, _) => Container(color: AppColors.cardSub),
                      )
                    else
                      _thumbnailFallback(),
                    Container(color: Colors.black.withOpacity(0.22)),
                    Center(
                      child: Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.65),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          isPlayable ? Icons.play_arrow_rounded : Icons.open_in_browser_rounded,
                          color: Colors.white,
                          size: 32,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      video.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: isPlayable ? () => _playInline(video.videoId) : () => _openUrl(video.videoUrl),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.live,
                              foregroundColor: AppColors.textPrimary,
                              padding: const EdgeInsets.symmetric(vertical: 10),
                            ),
                            child: Text(_playingVideoId == video.videoId ? '재생 중' : '바로 재생'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          onPressed: () => _openUrl(video.videoUrl),
                          icon: const Icon(Icons.open_in_new_rounded, color: AppColors.textSecondary),
                        ),
                      ],
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

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    final mode = kIsWeb ? LaunchMode.platformDefault : LaunchMode.inAppBrowserView;
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
    });
  }
}
