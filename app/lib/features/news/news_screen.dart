import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/router/app_route_sanitizer.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_motion.dart';
import '../../core/widgets/app_page_frame.dart';
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
                '경기, 선수, 순위, 기록을 오늘 읽을 순서로 정리했습니다.',
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
  final ValueChanged<_NewsFilter> onFilterChanged;

  const _NewsContent({
    required this.aggregate,
    required this.filter,
    required this.onFilterChanged,
  });

  @override
  Widget build(BuildContext context) {
    final allItems = _newsItems(aggregate);
    final leadItems = _editorialLeadItems(allItems);
    final visibleItems = filter == _NewsFilter.all
        ? allItems.where((item) => !leadItems.contains(item)).toList()
        : allItems.where((item) => item.filter == filter).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _EditorialLead(aggregate: aggregate, items: leadItems),
        const SizedBox(height: 12),
        _NewsMixRail(items: allItems, onSelected: onFilterChanged),
        const SizedBox(height: 12),
        _FilterBar(selected: filter, onChanged: onFilterChanged),
        const SizedBox(height: 14),
        _SignalGrid(
          aggregate: aggregate,
          items: allItems,
          selected: filter,
          onSelected: onFilterChanged,
        ),
        const SizedBox(height: 16),
        _NewsSectionHeader(
          title: filter == _NewsFilter.all ? '핵심 브리프' : '${filter.label} 브리프',
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

class _EditorialLead extends StatelessWidget {
  final HomeAggregate aggregate;
  final List<_NewsCardData> items;

  const _EditorialLead({required this.aggregate, required this.items});

  @override
  Widget build(BuildContext context) {
    final brief = aggregate.kboBrief;
    final leadItems = _editorialLeadItems(items);

    return Container(
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
                      brief?.title ?? '오늘 읽을 순서',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      brief?.subtitle ?? '경기, 순위, 기록 흐름을 편집해 보여줍니다.',
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
          if (leadItems.isNotEmpty) ...[
            const SizedBox(height: 13),
            Container(height: 1, color: AppColors.divider),
            const SizedBox(height: 10),
            const Text(
              '오늘 읽을 순서',
              style: TextStyle(
                fontSize: 11,
                color: AppColors.textDisabled,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
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
      onTap: () => context.push(
        sanitizeAppRoute(item.route, fallback: '/news') ?? '/news',
      ),
      pressedScale: 0.985,
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: item.accent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Text(
              '$rank',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w900,
                color: item.accent,
              ),
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              item.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                height: 1.25,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            item.actionLabel,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textDisabled,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _NewsMixRail extends StatelessWidget {
  final List<_NewsCardData> items;
  final ValueChanged<_NewsFilter> onSelected;

  const _NewsMixRail({required this.items, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    final mixes = _mixData(items);
    if (mixes.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '뉴스 믹스',
          style: TextStyle(
            fontSize: 12,
            color: AppColors.textDisabled,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 36,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: mixes.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final mix = mixes[index];
              return AppPressable(
                onTap: () => onSelected(mix.filter),
                pressedScale: 0.96,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: mix.accent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: mix.accent.withValues(alpha: 0.42),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(mix.icon, size: 15, color: mix.accent),
                      const SizedBox(width: 6),
                      Text(
                        mix.label,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${mix.count}',
                        style: TextStyle(
                          fontSize: 11,
                          color: mix.accent,
                          fontWeight: FontWeight.w900,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _NewsMixData {
  final String label;
  final int count;
  final _NewsFilter filter;
  final IconData icon;
  final Color accent;

  const _NewsMixData({
    required this.label,
    required this.count,
    required this.filter,
    required this.icon,
    required this.accent,
  });
}

class _SignalGrid extends StatelessWidget {
  final HomeAggregate aggregate;
  final List<_NewsCardData> items;
  final _NewsFilter selected;
  final ValueChanged<_NewsFilter> onSelected;

  const _SignalGrid({
    required this.aggregate,
    required this.items,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final signals = _signalData(aggregate, items);
    return LayoutBuilder(
      builder: (context, constraints) {
        final tileWidth = (constraints.maxWidth - 10) / 2;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final signal in signals)
              SizedBox(
                width: tileWidth,
                child: _SignalTile(
                  signal: signal,
                  selected: selected == signal.filter,
                  onTap: () => onSelected(signal.filter),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _SignalTile extends StatelessWidget {
  final _NewsSignalData signal;
  final bool selected;
  final VoidCallback onTap;

  const _SignalTile({
    required this.signal,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AppPressable(
      onTap: onTap,
      pressedScale: 0.97,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected
              ? signal.accent.withValues(alpha: 0.14)
              : AppColors.card,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? signal.accent : AppColors.divider,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(signal.icon, size: 16, color: signal.accent),
                const Spacer(),
                Text(
                  signal.value,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              signal.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 3),
            Text(
              signal.caption,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 10,
                color: AppColors.textDisabled,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
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
          style: const TextStyle(
            fontSize: 11,
            color: AppColors.textDisabled,
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
      onTap: () => context.push(
        sanitizeAppRoute(item.route, fallback: '/news') ?? '/news',
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: AppColors.card,
            border: Border.all(color: AppColors.divider),
          ),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(width: 4, color: item.accent),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
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
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
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
                                ],
                              ),
                            ),
                            if (item.hasVisual) ...[
                              const SizedBox(width: 12),
                              _NewsCardVisual(item: item),
                            ],
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Icon(
                              Icons.arrow_forward_rounded,
                              size: 15,
                              color: item.accent,
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
                ),
              ],
            ),
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

  const _NewsCardVisual({required this.item});

  @override
  Widget build(BuildContext context) {
    final fallback = _VisualFallback(label: item.fallbackLabel ?? item.label);
    final imageUrl = item.imageUrl;

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: item.accent.withValues(alpha: 0.12),
          border: Border.all(color: item.accent.withValues(alpha: 0.34)),
        ),
        child: imageUrl == null || imageUrl.isEmpty
            ? fallback
            : Image.network(
                imageUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => fallback,
                loadingBuilder: (context, child, progress) {
                  if (progress == null) {
                    return child;
                  }
                  return fallback;
                },
              ),
      ),
    );
  }
}

class _VisualFallback extends StatelessWidget {
  final String label;

  const _VisualFallback({required this.label});

  @override
  Widget build(BuildContext context) {
    final letters = _visualLetters(label);
    return Center(
      child: Text(
        letters,
        maxLines: 1,
        overflow: TextOverflow.clip,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w900,
          color: AppColors.textPrimary,
        ),
      ),
    );
  }
}

class _NewsSignalData {
  final _NewsFilter filter;
  final String label;
  final String value;
  final String caption;
  final IconData icon;
  final Color accent;

  const _NewsSignalData({
    required this.filter,
    required this.label,
    required this.value,
    required this.caption,
    required this.icon,
    required this.accent,
  });
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
  final VoidCallback onShowAll;

  const _NewsEmptyState({
    required this.hasAnyNews,
    required this.filterLabel,
    required this.onShowAll,
  });

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
          onShowAll();
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
  final items = <_NewsCardData>[];

  void add(_NewsCardData item) {
    final duplicate = items.any(
      (current) =>
          current.route == item.route &&
          (current.title == item.title || current.label == item.label),
    );
    if (!duplicate && item.title.trim().isNotEmpty) {
      items.add(item);
    }
  }

  final briefItems = aggregate.kboBrief?.items ?? const <HomeKboBriefItem>[];
  for (final item in briefItems) {
    add(_NewsCardData.fromBriefItem(item));
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
  for (final standing in aggregate.standingsPreview.take(5)) {
    add(_NewsCardData.fromStanding(standing));
  }
  for (final item in aggregate.quickItems) {
    add(_NewsCardData.fromQuickItem(item));
  }

  return items;
}

List<_NewsCardData> _editorialLeadItems(List<_NewsCardData> items) {
  final ordered = [...items]
    ..sort((a, b) {
      final priority = _leadPriority(a).compareTo(_leadPriority(b));
      if (priority != 0) {
        return priority;
      }
      return a.title.compareTo(b.title);
    });
  return ordered.take(3).toList();
}

int _leadPriority(_NewsCardData item) {
  return switch (item.filter) {
    _NewsFilter.game => 0,
    _NewsFilter.standings => 1,
    _NewsFilter.records => 2,
    _NewsFilter.myTeam => 3,
    _NewsFilter.all => 4,
  };
}

List<_NewsSignalData> _signalData(
  HomeAggregate aggregate,
  List<_NewsCardData> items,
) {
  int countFor(_NewsFilter filter) =>
      items.where((item) => item.filter == filter).length;

  final recentCount = aggregate.myTeamBrief?.recentGamesCount ?? 0;
  final standingsCount = aggregate.standingsPreview.isEmpty
      ? countFor(_NewsFilter.standings)
      : aggregate.standingsPreview.length;

  return [
    _NewsSignalData(
      filter: _NewsFilter.game,
      label: '경기 흐름',
      value: '${countFor(_NewsFilter.game)}',
      caption: '스코어·일정',
      icon: _iconForFilter(_NewsFilter.game),
      accent: _accentForFilter(_NewsFilter.game),
    ),
    _NewsSignalData(
      filter: _NewsFilter.standings,
      label: '순위 변동',
      value: '$standingsCount',
      caption: '상위권·마이팀',
      icon: _iconForFilter(_NewsFilter.standings),
      accent: _accentForFilter(_NewsFilter.standings),
    ),
    _NewsSignalData(
      filter: _NewsFilter.records,
      label: '기록 신호',
      value: '${countFor(_NewsFilter.records)}',
      caption: '선수·리더보드',
      icon: _iconForFilter(_NewsFilter.records),
      accent: _accentForFilter(_NewsFilter.records),
    ),
    _NewsSignalData(
      filter: _NewsFilter.myTeam,
      label: '마이팀',
      value: recentCount > 0
          ? '$recentCount'
          : '${countFor(_NewsFilter.myTeam)}',
      caption: recentCount > 0 ? '최근 경기' : '개인화 브리프',
      icon: _iconForFilter(_NewsFilter.myTeam),
      accent: _accentForFilter(_NewsFilter.myTeam),
    ),
  ];
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
    this.imageUrl,
    this.fallbackLabel,
  });

  Color get accent => _accentForFilter(filter);

  bool get hasVisual {
    final label = fallbackLabel?.trim() ?? '';
    return (imageUrl != null && imageUrl!.isNotEmpty) || label.isNotEmpty;
  }

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
      fallbackLabel: brief.teamLabel,
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
      storyKind: _storyKindForBriefType(item.type, item.route),
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

    return _NewsCardData(
      filter: _NewsFilter.standings,
      label: '순위 압축',
      title: '${leader.rank}위 ${leader.teamName} 선두권 체크',
      subtitle: gap,
      sourceLabel: '순위표',
      actionLabel: '순위 보기',
      route: '/standings',
      storyKind: 'standings',
      fallbackLabel: leader.teamName,
    );
  }

  factory _NewsCardData.fromStanding(TeamStanding standing) {
    final gb = standing.gb.isEmpty || standing.gb == '-'
        ? '선두권'
        : '${standing.gb}G차';
    final streak = standing.streakLabel == '-'
        ? '최근 흐름 확인'
        : standing.streakLabel;
    return _NewsCardData(
      filter: _NewsFilter.standings,
      label: '${standing.rank}위',
      title: '${standing.teamName} ${standing.rank}위',
      subtitle:
          '${standing.wins}승 ${standing.losses}패 ${standing.draws}무 · $gb · $streak',
      sourceLabel: '순위표',
      actionLabel: '순위 보기',
      route: '/standings',
      storyKind: 'standings',
      fallbackLabel: standing.teamName,
    );
  }
}

List<_NewsMixData> _mixData(List<_NewsCardData> items) {
  final counts = <String, int>{};
  for (final item in items) {
    counts[item.storyKind] = (counts[item.storyKind] ?? 0) + 1;
  }

  _NewsMixData? build(String kind) {
    final count = counts[kind] ?? 0;
    if (count == 0) {
      return null;
    }
    final filter = _filterForStoryKind(kind);
    return _NewsMixData(
      label: _labelForStoryKind(kind),
      count: count,
      filter: filter,
      icon: _iconForStoryKind(kind),
      accent: _accentForStoryKind(kind),
    );
  }

  final mixes = <_NewsMixData>[];
  for (final kind in const [
    'live',
    'player',
    'standings',
    'record',
    'schedule',
    'my_team',
  ]) {
    final mix = build(kind);
    if (mix != null) {
      mixes.add(mix);
    }
  }
  return mixes;
}

_NewsFilter _filterForStoryKind(String kind) {
  return switch (kind) {
    'standings' => _NewsFilter.standings,
    'record' || 'player' => _NewsFilter.records,
    'my_team' => _NewsFilter.myTeam,
    _ => _NewsFilter.game,
  };
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

IconData _iconForStoryKind(String kind) {
  return switch (kind) {
    'live' => Icons.sports_baseball_rounded,
    'player' => Icons.person_search_rounded,
    'standings' => Icons.leaderboard_rounded,
    'record' => Icons.bar_chart_rounded,
    'schedule' => Icons.calendar_month_rounded,
    'my_team' => Icons.shield_rounded,
    _ => Icons.article_outlined,
  };
}

Color _accentForStoryKind(String kind) {
  return switch (kind) {
    'live' => AppColors.live,
    'player' => AppColors.positive,
    'standings' => AppColors.accent,
    'record' => AppColors.positive,
    'schedule' => AppColors.ballYellow,
    'my_team' => AppColors.ballYellow,
    _ => AppColors.textSecondary,
  };
}

String _storyKindForBriefType(String type, String route) {
  return switch (type) {
    'player_performance' || 'pitcher_check' => 'player',
    'record_radar' => 'record',
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

String _visualLetters(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return 'K';
  }
  final parts = trimmed
      .split(RegExp(r'\s+'))
      .where((part) => part.trim().isNotEmpty)
      .toList();
  if (parts.length >= 2) {
    return parts.take(2).map((part) => part.characters.first).join();
  }
  final chars = trimmed.characters.toList();
  return chars.take(chars.length >= 2 ? 2 : 1).join();
}

_NewsFilter _filterForBriefType(String type) {
  return switch (type) {
    'standings' || 'team_trend' => _NewsFilter.standings,
    'record_radar' ||
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
