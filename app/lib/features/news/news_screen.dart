import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/router/app_route_sanitizer.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/kbo_time.dart';
import '../../core/widgets/app_motion.dart';
import '../../core/widgets/app_page_frame.dart';
import '../../core/widgets/kbo_team_logo_image.dart';
import '../../data/models/home_aggregate.dart';
import '../../data/models/schedule.dart';
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

const int _kboRegularSeasonGames = 144;
const int _editorialLeadCount = 3;

class NewsScreen extends ConsumerStatefulWidget {
  const NewsScreen({super.key});

  @override
  ConsumerState<NewsScreen> createState() => _NewsScreenState();
}

class _NewsScreenState extends ConsumerState<NewsScreen> {
  _NewsFilter _filter = _NewsFilter.all;

  @override
  Widget build(BuildContext context) {
    final today = ref.watch(kboDateProvider);
    final displayDate = today.replaceAll('-', '.');
    final myTeamId = ref.watch(myTeamProvider);
    final aggregateKey = '$today|${myTeamId ?? ''}';
    final aggregateAsync = ref.watch(homeAggregateProvider(aggregateKey));

    return Scaffold(
      body: SafeArea(
        child: AppPageFrame(
          child: RefreshIndicator(
            color: AppColors.live,
            onRefresh: _refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
              children: [
                _NewsHeader(
                  displayDate: displayDate,
                  onRefresh: () => unawaited(_refresh()),
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
                        onRetry: () => unawaited(_refresh()),
                      ),
                    ),
                    data: (aggregate) => KeyedSubtree(
                      key: ValueKey(
                        'news-data-${aggregate.date}-${aggregate.kboBrief?.items.length ?? 0}',
                      ),
                      child: _NewsContent(
                        aggregate: aggregate,
                        filter: _filter,
                        onFilterChanged: (filter) =>
                            setState(() => _filter = filter),
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

  Future<void> _refresh() async {
    final today = ref.read(kboDateProvider);
    final myTeamId = ref.read(myTeamProvider);
    final aggregateKey = '$today|${myTeamId ?? ''}';
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
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textSupporting,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 5),
              const Text(
                '데이터 브리핑',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  height: 1.05,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '경기 · 순위 · 기록 · 마이팀 흐름을 한눈에',
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
          tooltip: '데이터 브리핑 새로고침',
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
    final useLargeText = MediaQuery.textScalerOf(context).scale(1) >= 1.6;

    Widget buildTab(_NewsFilter filter) => AppPressable(
      semanticSelected: filter == selected,
      onTap: () => onChanged(filter),
      pressedScale: 0.98,
      child: _FilterTab(
        filter: filter,
        selected: filter == selected,
        useLargeText: useLargeText,
      ),
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.divider),
      ),
      child: useLargeText
          ? Padding(
              padding: const EdgeInsets.all(4),
              child: Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [
                  for (final filter in _NewsFilter.values)
                    ConstrainedBox(
                      constraints: const BoxConstraints(minWidth: 80),
                      child: buildTab(filter),
                    ),
                ],
              ),
            )
          : SizedBox(
              height: 44,
              child: Row(
                children: [
                  for (final filter in _NewsFilter.values)
                    Expanded(child: buildTab(filter)),
                ],
              ),
            ),
    );
  }
}

class _FilterTab extends StatelessWidget {
  final _NewsFilter filter;
  final bool selected;
  final bool useLargeText;

  const _FilterTab({
    required this.filter,
    required this.selected,
    required this.useLargeText,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      margin: const EdgeInsets.all(4),
      padding: useLargeText
          ? const EdgeInsets.symmetric(horizontal: 12, vertical: 10)
          : EdgeInsets.zero,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: selected
            ? AppColors.live.withValues(alpha: 0.16)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: selected
              ? AppColors.live.withValues(alpha: 0.55)
              : Colors.transparent,
        ),
      ),
      child: Text(
        filter.label,
        maxLines: useLargeText ? null : 1,
        overflow: useLargeText ? TextOverflow.visible : TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w900,
          color: selected ? AppColors.textPrimary : AppColors.textSecondary,
        ),
      ),
    );
  }
}

class _NewsContent extends StatelessWidget {
  final HomeAggregate aggregate;
  final _NewsFilter filter;
  final ValueChanged<_NewsFilter> onFilterChanged;

  const _NewsContent({
    required this.aggregate,
    required this.filter,
    required this.onFilterChanged,
  });

  @override
  Widget build(BuildContext context) {
    final allItems = _newsItems(aggregate);
    final leadItems = _editorialLeadItems(allItems, myTeamId: aggregate.myTeam);
    final visibleItems = filter == _NewsFilter.all
        ? allItems.length > leadItems.length
              ? allItems.where((item) => !leadItems.contains(item)).toList()
              : allItems
        : allItems.where((item) => item.filter == filter).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _BriefingDisclosure(generatedAt: aggregate.generatedAt),
        const SizedBox(height: 12),
        _EditorialLead(items: leadItems),
        const SizedBox(height: 12),
        _FilterBar(selected: filter, onChanged: onFilterChanged),
        const SizedBox(height: 14),
        _NewsSectionHeader(
          title: filter == _NewsFilter.all
              ? '전체 데이터 흐름'
              : '${filter.label} 데이터 흐름',
          count: visibleItems.length,
        ),
        const SizedBox(height: 10),
        if (visibleItems.isEmpty)
          _NewsEmptyState(
            hasAnyNews: allItems.isNotEmpty,
            filterLabel: filter.label,
            onShowAll: () => onFilterChanged(_NewsFilter.all),
          )
        else
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

class _BriefingDisclosure extends StatelessWidget {
  final DateTime? generatedAt;

  const _BriefingDisclosure({required this.generatedAt});

  @override
  Widget build(BuildContext context) {
    final generatedLabel = generatedAt == null
        ? '생성 시각 미제공'
        : '${_twoDigits(kboCivilDateTime(generatedAt).hour)}:${_twoDigits(kboCivilDateTime(generatedAt).minute)} 생성';

    return Semantics(
      label: 'KBO 경기, 순위, 기록 데이터를 앱이 자동 정리한 브리핑. 실제 뉴스 기사가 아님. $generatedLabel',
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.cardSub.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.divider),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.info_outline_rounded,
              size: 17,
              color: AppColors.textSecondary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'KBO 데이터로 앱이 자동 정리한 브리핑입니다. 실제 뉴스 기사 아님 · $generatedLabel',
                style: TextStyle(
                  fontSize: 11,
                  height: 1.35,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EditorialLead extends StatelessWidget {
  final List<_NewsCardData> items;

  const _EditorialLead({required this.items});

  @override
  Widget build(BuildContext context) {
    final leadItems = items;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 13),
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
              Container(width: 3, height: 44, color: AppColors.live),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '먼저 볼 흐름',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (leadItems.isNotEmpty) ...[
            const SizedBox(height: 13),
            Container(height: 1, color: AppColors.divider),
            const SizedBox(height: 10),
            for (var index = 0; index < leadItems.length; index++) ...[
              _LeadRow(rank: index + 1, item: leadItems[index]),
              if (index != leadItems.length - 1) const SizedBox(height: 7),
            ],
          ],
        ],
      ),
    );
  }
}

class _LeadRow extends StatelessWidget {
  final int rank;
  final _NewsCardData item;

  const _LeadRow({required this.rank, required this.item});

  @override
  Widget build(BuildContext context) {
    return AppPressable(
      onTap: () => _pushNewsRoute(context, item.route),
      pressedScale: 0.985,
      child: Row(
        children: [
          SizedBox(
            width: 20,
            child: Text(
              '$rank',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: AppColors.live,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(width: 10),
          _NewsCardVisual(item: item, size: 34),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${_labelForStoryKind(item.storyKind)} · ${item.sourceLabel}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    color: AppColors.textSupporting,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Icon(
            Icons.chevron_right_rounded,
            size: 18,
            color: AppColors.textSupporting,
          ),
        ],
      ),
    );
  }
}

class _NewsSectionHeader extends StatelessWidget {
  final String title;
  final int count;

  const _NewsSectionHeader({required this.title, required this.count});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
          ),
        ),
        Text(
          '$count개',
          style: TextStyle(
            fontSize: 11,
            color: AppColors.textSupporting,
            fontWeight: FontWeight.w800,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

class _NewsCard extends StatelessWidget {
  final _NewsCardData item;

  const _NewsCard({required this.item});

  @override
  Widget build(BuildContext context) {
    return AppPressable(
      onTap: () => _pushNewsRoute(context, item.route),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: AppColors.card,
            border: Border.all(color: AppColors.divider),
          ),
          padding: const EdgeInsets.fromLTRB(12, 11, 10, 11),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _NewsCardVisual(item: item, size: 52),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          _labelForStoryKind(item.storyKind),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: item.accent,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Text(
                            '${item.sourceLabel} · ${item.label}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.textSupporting,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      item.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      item.actionLabel,
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textSupporting,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: AppColors.textSupporting,
              ),
            ],
          ),
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
    final icon = _iconForFilter(filter);
    final color = _accentForFilter(filter);

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

class _NewsCardVisual extends StatelessWidget {
  final _NewsCardData item;
  final double size;

  const _NewsCardVisual({required this.item, this.size = 48});

  @override
  Widget build(BuildContext context) {
    final imageUrl = item.imageUrl;
    final radius = BorderRadius.circular(size * 0.18);

    return ClipRRect(
      borderRadius: radius,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: item.accent.withValues(alpha: 0.1),
          border: Border.all(color: item.accent.withValues(alpha: 0.24)),
        ),
        child: imageUrl == null || imageUrl.isEmpty
            ? _TeamOrFallbackVisual(item: item, size: size)
            : Image.network(
                imageUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) =>
                    _TeamOrFallbackVisual(item: item, size: size),
                loadingBuilder: (context, child, progress) {
                  if (progress == null) {
                    return child;
                  }
                  return _TeamOrFallbackVisual(item: item, size: size);
                },
              ),
      ),
    );
  }
}

class _TeamOrFallbackVisual extends StatelessWidget {
  final _NewsCardData item;
  final double size;

  const _TeamOrFallbackVisual({required this.item, required this.size});

  @override
  Widget build(BuildContext context) {
    final fallback = item.fallbackLabel?.trim().isNotEmpty == true
        ? item.fallbackLabel!.trim()
        : item.label;
    if (fallback.trim().isEmpty && (item.teamId ?? '').isEmpty) {
      return Center(child: _NewsIcon(filter: item.filter));
    }
    return Padding(
      padding: EdgeInsets.all(size <= 36 ? 3 : 4),
      child: KboTeamLogoImage(
        teamId: item.teamId,
        fallback: fallback,
        size: size,
        padding: 0,
      ),
    );
  }
}

class _NewsLoadingList extends StatelessWidget {
  const _NewsLoadingList();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(
        5,
        (index) => Container(
          height: index == 0 ? 160 : (index == 1 ? 98 : 124),
          margin: EdgeInsets.only(bottom: index == 4 ? 0 : 10),
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
      title: '데이터 브리핑을 불러올 수 없습니다',
      body: '오늘 경기와 기록 흐름을 다시 확인해 주세요.',
      actionLabel: '다시 확인',
      onAction: onRetry,
    );
  }
}

class _NewsEmptyState extends StatelessWidget {
  final bool hasAnyNews;
  final String filterLabel;
  final VoidCallback onShowAll;

  const _NewsEmptyState({
    required this.hasAnyNews,
    required this.filterLabel,
    required this.onShowAll,
  });

  @override
  Widget build(BuildContext context) {
    final title = hasAnyNews
        ? '$filterLabel 데이터 흐름이 없습니다'
        : '오늘 정리할 데이터 흐름이 없습니다';
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
          onShowAll();
          return;
        }
        context.pushAppRoute(
          '/schedule',
          fallback: '/news',
          presentation: AppRoutePresentation.swipeBack,
        );
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
            style: TextStyle(
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

void _pushNewsRoute(BuildContext context, String route) {
  context.pushAppRoute(
    route,
    fallback: '/news',
    presentation: AppRoutePresentation.swipeBack,
  );
}

List<_NewsCardData> _newsItems(HomeAggregate aggregate) {
  final items = <_NewsCardData>[];
  final standingsByTeamId = _standingsByTeamId(aggregate.standingsPreview);

  void add(_NewsCardData item) {
    final duplicate = items.any((current) {
      if (current.route != item.route) {
        return false;
      }
      if (current.title == item.title) {
        return true;
      }
      if (current.label != item.label) {
        return false;
      }
      final currentTeamId = current.teamId;
      final itemTeamId = item.teamId;
      if (currentTeamId == null ||
          currentTeamId.isEmpty ||
          itemTeamId == null ||
          itemTeamId.isEmpty) {
        return true;
      }
      return currentTeamId == itemTeamId;
    });
    if (!duplicate && item.title.trim().isNotEmpty) {
      items.add(item);
    }
  }

  final briefItems = aggregate.kboBrief?.items ?? const <HomeKboBriefItem>[];
  for (final item in briefItems) {
    add(_NewsCardData.fromBriefItem(item));
  }
  final homeRunPaceItem = _homeRunPaceItem(
    aggregate.quickItems,
    standingsByTeamId,
  );
  if (homeRunPaceItem != null) {
    add(homeRunPaceItem);
  }
  if (aggregate.myTeamBrief != null) {
    final myTeamBrief = aggregate.myTeamBrief!;
    add(_NewsCardData.fromMyTeamBrief(myTeamBrief));
    for (var index = 0; index < myTeamBrief.recentSummaries.length; index++) {
      if (index >= 3) {
        break;
      }
      add(
        _NewsCardData.fromRecentSummary(
          brief: myTeamBrief,
          summary: myTeamBrief.recentSummaries[index],
          index: index,
        ),
      );
    }
  }
  final standingsItem = _NewsCardData.fromStandingsPreview(
    aggregate.standingsPreview,
  );
  if (standingsItem != null) {
    add(standingsItem);
  }
  for (final standing in aggregate.standingsPreview) {
    add(_NewsCardData.fromStanding(standing));
  }
  for (final item in _standingsRaceItems(aggregate.standingsPreview)) {
    add(item);
  }
  for (final item in _streakContrastItems(aggregate.standingsPreview)) {
    add(item);
  }
  for (final item in _winPaceItems(aggregate.standingsPreview)) {
    add(item);
  }
  for (final item in aggregate.quickItems) {
    add(_NewsCardData.fromQuickItem(item));
  }

  return items;
}

Map<String, TeamStanding> _standingsByTeamId(List<TeamStanding> standings) {
  final map = <String, TeamStanding>{};
  for (final standing in standings) {
    if (standing.teamId.isNotEmpty) {
      map[standing.teamId] = standing;
    }
  }
  return map;
}

_NewsCardData? _homeRunPaceItem(
  List<HomeQuickItem> quickItems,
  Map<String, TeamStanding> standingsByTeamId,
) {
  for (final item in quickItems) {
    if (!_isHomeRunLeaderItem(item)) {
      continue;
    }
    final teamId = item.teamId;
    if (teamId == null || teamId.isEmpty) {
      continue;
    }
    final standing = standingsByTeamId[teamId];
    if (standing == null) {
      continue;
    }
    final homeRuns = _homeRunCountFromTitle(item.title);
    final gamesPlayed = _gamesPlayed(standing);
    if (homeRuns == null || gamesPlayed <= 0) {
      continue;
    }
    final projectedHomeRuns = _projectSeasonTotal(homeRuns, gamesPlayed);
    final playerName = _homeRunLeaderName(item, homeRuns);
    final teamName = standing.teamName;
    final projectedHomeRunsText = '$projectedHomeRuns홈런';
    return _NewsCardData(
      filter: _NewsFilter.records,
      label: '홈런 페이스',
      title: '$playerName, 지금 페이스면 $projectedHomeRunsText',
      subtitle: '앱 계산 · $teamName $gamesPlayed경기 기준 · 현재 $homeRuns홈런',
      sourceLabel: '기록실',
      actionLabel: _actionLabelForRoute(item.route),
      route: item.route,
      storyKind: 'record',
      teamId: teamId,
      imageUrl: item.imageUrl,
      fallbackLabel: playerName,
    );
  }
  return null;
}

bool _isHomeRunLeaderItem(HomeQuickItem item) {
  return item.eyebrow.contains('홈런') || item.title.contains('홈런');
}

int? _homeRunCountFromTitle(String title) {
  final match = RegExp(r'(\d+)\s*(?:개|홈런)').firstMatch(title);
  if (match == null) {
    return null;
  }
  return int.tryParse(match.group(1)!);
}

String _homeRunLeaderName(HomeQuickItem item, int homeRuns) {
  final fallback = item.fallbackLabel?.trim();
  if (fallback != null && fallback.isNotEmpty) {
    return fallback;
  }
  final pattern = RegExp('\\s*$homeRuns\\s*(?:개|홈런).*');
  final name = item.title.replaceFirst(pattern, '').trim();
  return name.isEmpty ? item.title : name;
}

List<_NewsCardData> _winPaceItems(List<TeamStanding> standings) {
  if (standings.isEmpty) {
    return const [];
  }
  final sorted = [...standings]..sort((a, b) => a.rank.compareTo(b.rank));
  final items = <_NewsCardData>[];
  for (final standing in sorted) {
    final item = _winPaceItem(standing);
    if (item != null) {
      items.add(item);
    }
  }
  return items;
}

_NewsCardData? _winPaceItem(TeamStanding standing) {
  final gamesPlayed = _gamesPlayed(standing);
  if (gamesPlayed <= 0 || standing.wins <= 0) {
    return null;
  }
  final projectedWins = _projectSeasonTotal(standing.wins, gamesPlayed);
  final teamName = standing.teamName;
  final recordText = '${standing.wins}승 ${standing.losses}패 ${standing.draws}무';
  return _NewsCardData(
    filter: _NewsFilter.standings,
    label: '승수 페이스',
    title: '$teamName, 지금 페이스면 $projectedWins승',
    subtitle: '앱 계산 · 현재 $recordText · 144경기 환산',
    sourceLabel: '순위표',
    actionLabel: '순위 보기',
    route: '/standings',
    storyKind: 'standings',
    teamId: standing.teamId,
    fallbackLabel: standing.teamName,
  );
}

int _gamesPlayed(TeamStanding standing) {
  return standing.wins + standing.losses + standing.draws;
}

int _projectSeasonTotal(int value, int gamesPlayed) {
  return (value * _kboRegularSeasonGames / gamesPlayed).round();
}

List<_NewsCardData> _standingsRaceItems(List<TeamStanding> standings) {
  if (standings.length < 2) {
    return const [];
  }
  final sorted = [...standings]..sort((a, b) => a.rank.compareTo(b.rank));
  return [
    for (var index = 0; index < sorted.length - 1; index++)
      _standingsRaceItem(upper: sorted[index], lower: sorted[index + 1]),
  ];
}

_NewsCardData _standingsRaceItem({
  required TeamStanding upper,
  required TeamStanding lower,
}) {
  final lowerGap = lower.gb.isEmpty || lower.gb == '-'
      ? '선두권'
      : '선두와 ${lower.gb}G차';
  final parsedGap = _parseGamesBehind(lower.gb);
  final title = upper.rank != 1
      ? '${upper.teamName}-${lower.teamName}, 인접 순위 흐름'
      : parsedGap != null && parsedGap <= 2
      ? '${upper.teamName} 턱밑까지 쫓는 ${lower.teamName}'
      : '${upper.teamName} 선두, ${lower.teamName} ${lower.gb}G차 추격';
  return _NewsCardData(
    filter: _NewsFilter.standings,
    label: '순위권 구도',
    title: title,
    subtitle: '${lower.rank}위 ${lower.teamName} · $lowerGap',
    sourceLabel: '순위표',
    actionLabel: '순위 보기',
    route: '/standings',
    storyKind: 'standings',
    teamId: lower.teamId,
    fallbackLabel: lower.teamName,
  );
}

List<_NewsCardData> _streakContrastItems(List<TeamStanding> standings) {
  if (standings.isEmpty) {
    return const [];
  }
  final sorted = [...standings]..sort((a, b) => a.rank.compareTo(b.rank));
  final items = <_NewsCardData>[];

  for (final standing in sorted) {
    final signal = _streakSignal(standing);
    if (signal == null || signal.count < 2) {
      continue;
    }
    if (standing.rank >= 6 && signal.isWinning) {
      items.add(
        _streakContrastItem(
          standing: standing,
          signal: signal,
          title: '${standing.teamName}, ${standing.rank}위인데 ${signal.label}',
          subtitle: '전적은 중하위권이지만 최근 결과만 보면 흐름이 다릅니다.',
        ),
      );
    } else if (standing.rank <= 3 && signal.isLosing) {
      items.add(
        _streakContrastItem(
          standing: standing,
          signal: signal,
          title: '${standing.teamName}, ${standing.rank}위인데 ${signal.label}',
          subtitle: '상위권을 지키고 있지만 최근 결과는 다시 확인할 타이밍입니다.',
        ),
      );
    }
  }

  items.sort((a, b) => a.title.compareTo(b.title));
  return items.take(3).toList();
}

_NewsCardData _streakContrastItem({
  required TeamStanding standing,
  required _StreakSignal signal,
  required String title,
  required String subtitle,
}) {
  return _NewsCardData(
    filter: _NewsFilter.standings,
    label: '특이 흐름',
    title: title,
    subtitle:
        '${standing.wins}승 ${standing.losses}패 ${standing.draws}무 · $subtitle',
    sourceLabel: '순위표',
    actionLabel: '순위 보기',
    route: '/standings',
    storyKind: 'standings',
    teamId: standing.teamId,
    fallbackLabel: standing.teamName,
  );
}

_StreakSignal? _streakSignal(TeamStanding standing) {
  final label = standing.streakLabel;
  final match = RegExp(r'^(\d+)(연승|연패)$').firstMatch(label);
  if (match == null) {
    return null;
  }
  final count = int.tryParse(match.group(1)!);
  if (count == null || count <= 0) {
    return null;
  }
  return _StreakSignal(
    count: count,
    label: label,
    isWinning: match.group(2) == '연승',
  );
}

class _StreakSignal {
  final int count;
  final String label;
  final bool isWinning;

  const _StreakSignal({
    required this.count,
    required this.label,
    required this.isWinning,
  });

  bool get isLosing => !isWinning;
}

String _standingArticleTitle(TeamStanding standing) {
  if (standing.rank == 1) {
    final streak = standing.streakLabel;
    if (streak.endsWith('연패')) {
      return '선두가 흔들리는 ${standing.teamName}';
    }
    return '선두 지키는 ${standing.teamName}';
  }
  if (standing.rank == 2) {
    return '선두 추격하는 ${standing.teamName}';
  }
  if (standing.rank <= 5) {
    return '상위권 버티는 ${standing.teamName}';
  }
  if (standing.rank <= 8) {
    return '중위권 반등 노리는 ${standing.teamName}';
  }
  return '하위권 탈출 급한 ${standing.teamName}';
}

double? _parseGamesBehind(String value) {
  final normalized = value.trim();
  if (normalized.isEmpty || normalized == '-') {
    return null;
  }
  return double.tryParse(normalized);
}

String _briefNewsTitle(HomeKboBriefItem item) {
  if (item.type != 'standings') {
    return item.title;
  }
  final originalTitle = item.title.trim();
  if (_hasEditorialStandingPrefix(originalTitle)) {
    return originalTitle;
  }
  final teamName = _teamNameFromStandingBriefTitle(item.title);
  if (teamName == null) {
    return item.title;
  }
  final gap = _gapFromText(item.subtitle);
  if (gap != null && gap <= 2) {
    return '선두가 위태로운 $teamName';
  }
  return '선두 지키는 $teamName';
}

bool _hasEditorialStandingPrefix(String title) {
  return const [
    '선두가 위태로운 ',
    '선두 지키는 ',
    '선두 굳히는 ',
    '선두 추격하는 ',
    '상위권 버티는 ',
    '중위권 반등 노리는 ',
    '하위권 탈출 급한 ',
  ].any(title.startsWith);
}

String? _teamNameFromStandingBriefTitle(String title) {
  var normalized = title.trim();
  normalized = normalized.replaceFirst(RegExp(r'^[0-9]+위\s*'), '');
  normalized = normalized.replaceFirst(RegExp(r'\s*[0-9]+위.*$'), '');
  normalized = normalized.replaceAll('선두권 체크', '').replaceAll('유지', '').trim();
  return normalized.isEmpty ? null : normalized;
}

String _twoDigits(int value) => value.toString().padLeft(2, '0');

double? _gapFromText(String text) {
  final match = RegExp(r'([0-9]+(?:\.[0-9]+)?)G차').firstMatch(text);
  if (match == null) {
    return null;
  }
  return double.tryParse(match.group(1)!);
}

List<_NewsCardData> _editorialLeadItems(
  List<_NewsCardData> items, {
  String? myTeamId,
}) {
  final ordered = [...items]
    ..sort((a, b) {
      final priority = _leadPriority(
        a,
        myTeamId: myTeamId,
      ).compareTo(_leadPriority(b, myTeamId: myTeamId));
      if (priority != 0) {
        return priority;
      }
      return a.title.compareTo(b.title);
    });
  return ordered.take(_editorialLeadCount).toList();
}

int _leadPriority(_NewsCardData item, {String? myTeamId}) {
  if (item.filter == _NewsFilter.myTeam ||
      (myTeamId != null && item.teamId == myTeamId)) {
    return 0;
  }
  return switch (item.filter) {
    _NewsFilter.game => 1,
    _NewsFilter.standings => 2,
    _NewsFilter.records => 3,
    _NewsFilter.myTeam => 0,
    _NewsFilter.all => 4,
  };
}

class _NewsCardData {
  final _NewsFilter filter;
  final String label;
  final String title;
  final String subtitle;
  final String sourceLabel;
  final String actionLabel;
  final String route;
  final String storyKind;
  final String? teamId;
  final String? imageUrl;
  final String? fallbackLabel;

  const _NewsCardData({
    required this.filter,
    required this.label,
    required this.title,
    required this.subtitle,
    required this.sourceLabel,
    required this.actionLabel,
    required this.route,
    required this.storyKind,
    this.teamId,
    this.imageUrl,
    this.fallbackLabel,
  });

  Color get accent => _accentForFilter(filter);

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
      sourceLabel: '개인화',
      actionLabel: '마이팀 보기',
      route: route,
      storyKind: 'my_team',
      teamId: brief.teamId,
      fallbackLabel: brief.teamLabel,
    );
  }

  factory _NewsCardData.fromRecentSummary({
    required HomeMyTeamBrief brief,
    required HomeRecentGameSummary summary,
    required int index,
  }) {
    final route = summary.gameId.isEmpty
        ? '/records/team/${brief.teamId}'
        : '/game/${summary.gameId}';
    final opponent = summary.opponentName.trim().isEmpty
        ? '상대팀'
        : summary.opponentName.trim();
    return _NewsCardData(
      filter: _NewsFilter.myTeam,
      label: '최근 경기',
      title:
          '${brief.teamLabel} ${summary.result} · $opponent전 ${summary.score}',
      subtitle: '최근 ${index + 1}번째 경기 · 흐름을 이어서 확인하세요.',
      sourceLabel: '마이팀',
      actionLabel: summary.gameId.isEmpty ? '팀 기록 보기' : '경기 보기',
      route: route,
      storyKind: 'my_team',
      teamId: brief.teamId,
      fallbackLabel: brief.teamLabel,
    );
  }

  factory _NewsCardData.fromBriefItem(HomeKboBriefItem item) {
    final filter = _filterForBriefType(item.type);
    return _NewsCardData(
      filter: filter,
      label: item.eyebrow,
      title: _briefNewsTitle(item),
      subtitle: item.subtitle,
      sourceLabel: _sourceLabelForFilter(filter),
      actionLabel: _actionLabelForRoute(item.route),
      route: item.route,
      storyKind: _storyKindForBriefType(item.type, item.route),
      teamId: _firstTeamId(item.teamIds),
      imageUrl: item.imageUrl,
      fallbackLabel: item.fallbackLabel,
    );
  }

  factory _NewsCardData.fromQuickItem(HomeQuickItem item) {
    final filter = _filterForRoute(item.route, fallback: item.teamId);
    return _NewsCardData(
      filter: filter,
      label: item.eyebrow.isEmpty
          ? _sourceLabelForFilter(filter)
          : item.eyebrow,
      title: item.title,
      subtitle: item.subtitle.isEmpty
          ? '관련 화면에서 최신 흐름을 이어서 확인하세요.'
          : item.subtitle,
      sourceLabel: '추천',
      actionLabel: _actionLabelForRoute(item.route),
      route: item.route,
      storyKind: _storyKindForRoute(item.route, filter: filter),
      teamId: item.teamId,
      imageUrl: item.imageUrl,
      fallbackLabel: item.fallbackLabel,
    );
  }

  static _NewsCardData? fromStandingsPreview(List<TeamStanding> standings) {
    if (standings.isEmpty) {
      return null;
    }
    final sorted = [...standings]..sort((a, b) => a.rank.compareTo(b.rank));
    final leader = sorted.first;
    final second = sorted.length > 1 ? sorted[1] : null;
    final gap = second == null || second.gb.isEmpty || second.gb == '-'
        ? '상위권 흐름과 마이팀 위치를 같이 확인하세요.'
        : '${second.teamName}와 ${second.gb}G차 · 상위 ${sorted.length}팀 압축';
    final secondGap = second == null ? null : _parseGamesBehind(second.gb);

    return _NewsCardData(
      filter: _NewsFilter.standings,
      label: '순위 압축',
      title: secondGap != null && secondGap <= 2
          ? '선두가 위태로운 ${leader.teamName}'
          : '선두 굳히는 ${leader.teamName}',
      subtitle: gap,
      sourceLabel: '순위표',
      actionLabel: '순위 보기',
      route: '/standings',
      storyKind: 'standings',
      teamId: leader.teamId,
      fallbackLabel: leader.teamName,
    );
  }

  factory _NewsCardData.fromStanding(TeamStanding standing) {
    final gb = standing.gb.isEmpty || standing.gb == '-'
        ? '선두권'
        : '선두와 ${standing.gb}G차';
    final streak = standing.streakLabel == '-'
        ? '최근 흐름 확인'
        : standing.streakLabel;
    return _NewsCardData(
      filter: _NewsFilter.standings,
      label: '${standing.rank}위',
      title: _standingArticleTitle(standing),
      subtitle:
          '${standing.wins}승 ${standing.losses}패 ${standing.draws}무 · $gb · $streak',
      sourceLabel: '순위표',
      actionLabel: '순위 보기',
      route: '/standings',
      storyKind: 'standings',
      teamId: standing.teamId,
      fallbackLabel: standing.teamName,
    );
  }
}

String _labelForStoryKind(String kind) {
  return switch (kind) {
    'live' => '라이브',
    'player' => '선수',
    'standings' => '순위',
    'record' => '기록',
    'schedule' => '일정',
    'my_team' => '마이팀',
    _ => '경기',
  };
}

String _storyKindForBriefType(String type, String route) {
  return switch (type) {
    'player_performance' || 'pitcher_check' => 'player',
    'record_radar' ||
    'batting_leader' ||
    'defense_issue' ||
    'defense_rank' ||
    'record_milestone' => 'record',
    'standings' || 'team_trend' => 'standings',
    'big_match' || 'schedule_remaining' || 'offday' => 'schedule',
    'live' || 'league_now' || 'game_flow' => 'live',
    _ => _storyKindForRoute(route, filter: _filterForRoute(route)),
  };
}

String _storyKindForRoute(String route, {required _NewsFilter filter}) {
  if (route.startsWith('/records/player/')) {
    return 'player';
  }
  if (route.startsWith('/records')) {
    return 'record';
  }
  if (route.startsWith('/standings')) {
    return 'standings';
  }
  if (route.startsWith('/schedule')) {
    return 'schedule';
  }
  if (filter == _NewsFilter.myTeam) {
    return 'my_team';
  }
  return 'live';
}

String? _firstTeamId(List<String> teamIds) {
  for (final teamId in teamIds) {
    final normalized = teamId.trim();
    if (normalized.isNotEmpty) {
      return normalized;
    }
  }
  return null;
}

_NewsFilter _filterForBriefType(String type) {
  return switch (type) {
    'standings' || 'team_trend' => _NewsFilter.standings,
    'record_radar' ||
    'batting_leader' ||
    'defense_issue' ||
    'defense_rank' ||
    'record_milestone' ||
    'player_performance' ||
    'pitcher_check' => _NewsFilter.records,
    'offday' => _NewsFilter.records,
    'live' ||
    'final' ||
    'game_flow' ||
    'league_now' ||
    'schedule_remaining' ||
    'big_match' => _NewsFilter.game,
    _ => _NewsFilter.game,
  };
}

_NewsFilter _filterForRoute(String route, {String? fallback}) {
  if (route.startsWith('/standings')) {
    return _NewsFilter.standings;
  }
  if (route.startsWith('/records')) {
    return _NewsFilter.records;
  }
  if (route.startsWith('/game/') || route.startsWith('/schedule')) {
    return _NewsFilter.game;
  }
  if (fallback != null && fallback.isNotEmpty) {
    return _NewsFilter.myTeam;
  }
  return _NewsFilter.game;
}

IconData _iconForFilter(_NewsFilter filter) {
  return switch (filter) {
    _NewsFilter.game => Icons.sports_baseball_rounded,
    _NewsFilter.standings => Icons.leaderboard_rounded,
    _NewsFilter.records => Icons.bar_chart_rounded,
    _NewsFilter.myTeam => Icons.shield_rounded,
    _NewsFilter.all => Icons.article_outlined,
  };
}

Color _accentForFilter(_NewsFilter filter) {
  return switch (filter) {
    _NewsFilter.game => AppColors.live,
    _NewsFilter.standings => AppColors.accent,
    _NewsFilter.records => AppColors.positive,
    _NewsFilter.myTeam => AppColors.ballYellow,
    _NewsFilter.all => AppColors.textSecondary,
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
