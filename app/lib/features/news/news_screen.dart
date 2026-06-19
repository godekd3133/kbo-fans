import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_motion.dart';
import '../../core/widgets/app_page_frame.dart';
import '../../data/models/home_aggregate.dart';
import '../../data/providers.dart';

enum _NewsFilter {
  all(label: '전체'),
  game(label: '경기'),
  standings(label: '순위'),
  records(label: '기록'),
  myTeam(label: '마이팀');

  final String label;
  const _NewsFilter({required this.label});
}

class NewsScreen extends ConsumerStatefulWidget {
  const NewsScreen({super.key});

  @override
  ConsumerState<NewsScreen> createState() => _NewsScreenState();
}

class _NewsScreenState extends ConsumerState<NewsScreen> {
  _NewsFilter _filter = _NewsFilter.all;

  @override
  Widget build(BuildContext context) {
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final displayDate = DateFormat('yyyy.MM.dd').format(DateTime.now());
    final myTeamId = ref.watch(myTeamProvider);
    final aggregateKey = '$today|${myTeamId ?? ''}';
    final aggregateAsync = ref.watch(homeAggregateProvider(aggregateKey));

    return Scaffold(
      body: SafeArea(
        child: AppPageFrame(
          child: RefreshIndicator(
            color: AppColors.live,
            onRefresh: () => _refresh(aggregateKey),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
              children: [
                _NewsHeader(
                  displayDate: displayDate,
                  onRefresh: () => unawaited(_refresh(aggregateKey)),
                ),
                const SizedBox(height: 14),
                _FilterBar(
                  selected: _filter,
                  onChanged: (filter) => setState(() => _filter = filter),
                ),
                const SizedBox(height: 14),
                AppMotionSwitcher(
                  child: aggregateAsync.when(
                    loading: () => const KeyedSubtree(
                      key: ValueKey('news-loading'),
                      child: _NewsLoadingList(),
                    ),
                    error: (error, stackTrace) => KeyedSubtree(
                      key: const ValueKey('news-error'),
                      child: _NewsErrorState(
                        onRetry: () => unawaited(_refresh(aggregateKey)),
                      ),
                    ),
                    data: (aggregate) => KeyedSubtree(
                      key: ValueKey(
                        'news-data-${aggregate.date}-${aggregate.kboBrief?.items.length ?? 0}',
                      ),
                      child: _NewsContent(
                        aggregate: aggregate,
                        filter: _filter,
                      ),
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

  Future<void> _refresh(String aggregateKey) async {
    ref.invalidate(homeAggregateProvider(aggregateKey));
    try {
      await ref.read(homeAggregateProvider(aggregateKey).future);
    } catch (_) {
      // The provider owns the rendered error state; pull-to-refresh should settle.
    }
  }
}

class _NewsHeader extends StatelessWidget {
  final String displayDate;
  final VoidCallback onRefresh;

  const _NewsHeader({required this.displayDate, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$displayDate 기준',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textDisabled,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 5),
              const Text(
                '뉴스',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  height: 1.05,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '오늘 경기, 순위, 기록 흐름을 짧은 카드로 모았습니다.',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: '뉴스 새로고침',
          onPressed: onRefresh,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
    );
  }
}

class _FilterBar extends StatelessWidget {
  final _NewsFilter selected;
  final ValueChanged<_NewsFilter> onChanged;

  const _FilterBar({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _NewsFilter.values.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final filter = _NewsFilter.values[index];
          final isSelected = filter == selected;
          return AppPressable(
            onTap: isSelected ? null : () => onChanged(filter),
            pressedScale: 0.96,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: isSelected ? AppColors.textPrimary : AppColors.card,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isSelected ? AppColors.textPrimary : AppColors.divider,
                ),
              ),
              alignment: Alignment.center,
              child: Text(
                filter.label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: isSelected
                      ? AppColors.background
                      : AppColors.textSecondary,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _NewsContent extends StatelessWidget {
  final HomeAggregate aggregate;
  final _NewsFilter filter;

  const _NewsContent({required this.aggregate, required this.filter});

  @override
  Widget build(BuildContext context) {
    final allItems = _newsItems(aggregate);
    final visibleItems = filter == _NewsFilter.all
        ? allItems
        : allItems.where((item) => item.filter == filter).toList();

    if (visibleItems.isEmpty) {
      return _NewsEmptyState(
        hasAnyNews: allItems.isNotEmpty,
        filterLabel: filter.label,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (aggregate.kboBrief != null) ...[
          _BriefSummary(brief: aggregate.kboBrief!),
          const SizedBox(height: 12),
        ],
        for (var index = 0; index < visibleItems.length; index++) ...[
          AppMotionListItem(
            index: index,
            child: _NewsCard(item: visibleItems[index]),
          ),
          if (index != visibleItems.length - 1) const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _BriefSummary extends StatelessWidget {
  final HomeKboBrief brief;

  const _BriefSummary({required this.brief});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppColors.live.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.bolt_rounded,
              color: AppColors.live,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  brief.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  brief.subtitle,
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
        ],
      ),
    );
  }
}

class _NewsCard extends StatelessWidget {
  final _NewsCardData item;

  const _NewsCard({required this.item});

  @override
  Widget build(BuildContext context) {
    return AppPressable(
      onTap: () => context.push(item.route),
      child: Container(
        width: double.infinity,
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
                _NewsIcon(filter: item.filter),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    item.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textDisabled,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(
                  item.sourceLabel,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textDisabled,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              item.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 7),
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
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(
                  Icons.open_in_new_rounded,
                  size: 15,
                  color: AppColors.textDisabled,
                ),
                const SizedBox(width: 5),
                Text(
                  item.actionLabel,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w800,
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

class _NewsIcon extends StatelessWidget {
  final _NewsFilter filter;

  const _NewsIcon({required this.filter});

  @override
  Widget build(BuildContext context) {
    final icon = switch (filter) {
      _NewsFilter.game => Icons.sports_baseball_rounded,
      _NewsFilter.standings => Icons.leaderboard_rounded,
      _NewsFilter.records => Icons.bar_chart_rounded,
      _NewsFilter.myTeam => Icons.shield_rounded,
      _NewsFilter.all => Icons.article_outlined,
    };
    final color = switch (filter) {
      _NewsFilter.game => AppColors.live,
      _NewsFilter.standings => AppColors.accent,
      _NewsFilter.records => AppColors.positive,
      _NewsFilter.myTeam => AppColors.ballYellow,
      _NewsFilter.all => AppColors.textSecondary,
    };

    return Container(
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, size: 16, color: color),
    );
  }
}

class _NewsLoadingList extends StatelessWidget {
  const _NewsLoadingList();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(
        4,
        (index) => Container(
          height: index == 0 ? 74 : 124,
          margin: EdgeInsets.only(bottom: index == 3 ? 0 : 10),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.divider),
          ),
        ),
      ),
    );
  }
}

class _NewsErrorState extends StatelessWidget {
  final VoidCallback onRetry;

  const _NewsErrorState({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return _StateCard(
      icon: Icons.wifi_off_rounded,
      title: '뉴스를 불러올 수 없습니다',
      body: '오늘 경기와 기록 흐름을 다시 확인해 주세요.',
      actionLabel: '다시 확인',
      onAction: onRetry,
    );
  }
}

class _NewsEmptyState extends StatelessWidget {
  final bool hasAnyNews;
  final String filterLabel;

  const _NewsEmptyState({required this.hasAnyNews, required this.filterLabel});

  @override
  Widget build(BuildContext context) {
    final title = hasAnyNews ? '$filterLabel 뉴스가 없습니다' : '오늘 보여줄 뉴스가 없습니다';
    final body = hasAnyNews
        ? '다른 필터를 선택하거나 새로고침해 최신 흐름을 확인하세요.'
        : '경기, 순위, 기록 데이터가 들어오면 이 탭에 짧은 카드로 정리됩니다.';
    return _StateCard(
      icon: Icons.article_outlined,
      title: title,
      body: body,
      actionLabel: hasAnyNews ? '전체 보기' : '일정 보기',
      onAction: () {
        if (hasAnyNews) {
          context.go('/news');
          return;
        }
        context.go('/schedule');
      },
    );
  }
}

class _StateCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final String actionLabel;
  final VoidCallback onAction;

  const _StateCard({
    required this.icon,
    required this.title,
    required this.body,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.cardSub,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: AppColors.textSecondary, size: 21),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 7),
          Text(
            body,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 14),
          TextButton(onPressed: onAction, child: Text(actionLabel)),
        ],
      ),
    );
  }
}

List<_NewsCardData> _newsItems(HomeAggregate aggregate) {
  final items = <_NewsCardData>[
    if (aggregate.myTeamBrief != null)
      _NewsCardData.fromMyTeamBrief(aggregate.myTeamBrief!),
  ];
  final briefItems = aggregate.kboBrief?.items ?? const <HomeKboBriefItem>[];
  items.addAll(briefItems.map(_NewsCardData.fromBriefItem));
  return items;
}

class _NewsCardData {
  final _NewsFilter filter;
  final String label;
  final String title;
  final String subtitle;
  final String sourceLabel;
  final String actionLabel;
  final String route;

  const _NewsCardData({
    required this.filter,
    required this.label,
    required this.title,
    required this.subtitle,
    required this.sourceLabel,
    required this.actionLabel,
    required this.route,
  });

  factory _NewsCardData.fromMyTeamBrief(HomeMyTeamBrief brief) {
    final hasRecent = brief.recentGamesCount > 0;
    final title = hasRecent
        ? '${brief.teamLabel} 최근 ${brief.recentGamesCount}경기 ${brief.recentWins}승 ${brief.recentLosses}패'
        : '${brief.teamLabel} 오늘 흐름 확인';
    final nextGame = brief.nextGame;
    final subtitle = switch ((brief.todayGameId, nextGame)) {
      (final todayGameId?, _) when todayGameId.isNotEmpty =>
        '오늘 경기 상세에서 스코어와 중계를 바로 확인하세요.',
      (_, final game?) => '${game.time} · ${game.awayName} vs ${game.homeName}',
      _ => '팀 기록과 다음 일정을 함께 확인하세요.',
    };
    final route = brief.todayGameId != null && brief.todayGameId!.isNotEmpty
        ? '/game/${brief.todayGameId}'
        : '/records/team/${brief.teamId}';

    return _NewsCardData(
      filter: _NewsFilter.myTeam,
      label: '마이팀',
      title: title,
      subtitle: subtitle,
      sourceLabel: '홈 브리프',
      actionLabel: '마이팀 보기',
      route: route,
    );
  }

  factory _NewsCardData.fromBriefItem(HomeKboBriefItem item) {
    final filter = _filterForBriefType(item.type);
    return _NewsCardData(
      filter: filter,
      label: item.eyebrow,
      title: item.title,
      subtitle: item.subtitle,
      sourceLabel: _sourceLabelForFilter(filter),
      actionLabel: _actionLabelForRoute(item.route),
      route: item.route,
    );
  }
}

_NewsFilter _filterForBriefType(String type) {
  return switch (type) {
    'standings' => _NewsFilter.standings,
    'record_radar' => _NewsFilter.records,
    'live' || 'final' || 'big_match' || 'offday' => _NewsFilter.game,
    _ => _NewsFilter.game,
  };
}

String _sourceLabelForFilter(_NewsFilter filter) {
  return switch (filter) {
    _NewsFilter.game => '스코어보드',
    _NewsFilter.standings => '순위',
    _NewsFilter.records => '기록실',
    _NewsFilter.myTeam => '마이팀',
    _NewsFilter.all => '브리프',
  };
}

String _actionLabelForRoute(String route) {
  if (route.startsWith('/game/')) {
    return '경기 보기';
  }
  if (route.startsWith('/standings')) {
    return '순위 보기';
  }
  if (route.startsWith('/records')) {
    return '기록 보기';
  }
  if (route.startsWith('/schedule')) {
    return '일정 보기';
  }
  return '자세히 보기';
}
