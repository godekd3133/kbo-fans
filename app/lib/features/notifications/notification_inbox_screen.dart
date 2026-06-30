import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_route_sanitizer.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_motion.dart';
import '../../core/widgets/app_page_frame.dart';
import '../../services/notification_inbox_service.dart';
import '../../services/push_notification_service.dart';

enum _InboxFilter {
  all(label: '전체'),
  unread(label: '안 읽음'),
  games(label: '경기'),
  brief(label: '브리프');

  final String label;
  const _InboxFilter({required this.label});
}

class NotificationInboxScreen extends StatefulWidget {
  const NotificationInboxScreen({super.key});

  @override
  State<NotificationInboxScreen> createState() =>
      _NotificationInboxScreenState();
}

class _NotificationInboxScreenState extends State<NotificationInboxScreen> {
  _InboxFilter _filter = _InboxFilter.all;
  List<NotificationInboxEntry> _entries = const <NotificationInboxEntry>[];
  PushNotificationSettings? _settings;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait<Object>([
        NotificationInboxService.instance.loadEntries(),
        PushNotificationService.instance.loadSettings(),
      ]);
      if (!mounted) {
        return;
      }
      setState(() {
        _entries = results[0] as List<NotificationInboxEntry>;
        _settings = results[1] as PushNotificationSettings;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _entries = const <NotificationInboxEntry>[];
        _settings = const PushNotificationSettings.defaults();
        _loading = false;
      });
    }
  }

  Future<void> _markAllRead() async {
    await NotificationInboxService.instance.markAllRead();
    await _load();
  }

  Future<void> _openEntry(NotificationInboxEntry entry) async {
    await NotificationInboxService.instance.markRead(entry.id);
    if (!mounted) {
      return;
    }
    setState(() {
      _entries = [
        for (final item in _entries)
          item.id == entry.id ? item.copyWith(read: true) : item,
      ];
    });
    if (!entry.hasRoute) {
      return;
    }
    if (!mounted) {
      return;
    }
    context.pushAppRoute(entry.route, fallback: '/home');
  }

  @override
  Widget build(BuildContext context) {
    final visibleEntries = _filteredEntries(_entries, _filter);
    final unreadCount = _entries.where((entry) => !entry.read).length;
    final settings = _settings;

    return Scaffold(
      body: SafeArea(
        child: AppPageFrame(
          child: RefreshIndicator(
            color: AppColors.live,
            onRefresh: _load,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
              children: [
                _InboxHeader(
                  unreadCount: unreadCount,
                  onBack: () {
                    if (context.canPop()) {
                      context.pop();
                      return;
                    }
                    context.go('/home');
                  },
                  onMarkAllRead: unreadCount == 0 ? null : _markAllRead,
                ),
                const SizedBox(height: 14),
                _InboxSummaryCard(
                  totalCount: _entries.length,
                  unreadCount: unreadCount,
                  settings: settings,
                ),
                const SizedBox(height: 14),
                _InboxFilterBar(
                  selected: _filter,
                  onChanged: (filter) => setState(() => _filter = filter),
                ),
                const SizedBox(height: 14),
                AppMotionSwitcher(
                  child: _loading
                      ? const KeyedSubtree(
                          key: ValueKey('notification-inbox-loading'),
                          child: _InboxLoadingList(),
                        )
                      : KeyedSubtree(
                          key: ValueKey(
                            'notification-inbox-${_filter.name}-${visibleEntries.length}',
                          ),
                          child: visibleEntries.isEmpty
                              ? _InboxEmptyState(filter: _filter)
                              : _InboxTimeline(
                                  entries: visibleEntries,
                                  onOpenEntry: _openEntry,
                                ),
                        ),
                ),
                const SizedBox(height: 18),
                _InboxPlaybookSection(settings: settings),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<NotificationInboxEntry> _filteredEntries(
    List<NotificationInboxEntry> entries,
    _InboxFilter filter,
  ) {
    return switch (filter) {
      _InboxFilter.all => entries,
      _InboxFilter.unread => entries.where((entry) => !entry.read).toList(),
      _InboxFilter.games =>
        entries.where((entry) => entry.type != 'baseball_info').toList(),
      _InboxFilter.brief =>
        entries.where((entry) => entry.type == 'baseball_info').toList(),
    };
  }
}

class _InboxHeader extends StatelessWidget {
  final int unreadCount;
  final VoidCallback onBack;
  final VoidCallback? onMarkAllRead;

  const _InboxHeader({
    required this.unreadCount,
    required this.onBack,
    required this.onMarkAllRead,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          tooltip: '뒤로',
          onPressed: onBack,
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
        ),
        const SizedBox(width: 2),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '푸시 알림',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  color: AppColors.textDisabled,
                ),
              ),
              SizedBox(height: 4),
              Text(
                '알림함',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  height: 1.05,
                ),
              ),
            ],
          ),
        ),
        TextButton(
          onPressed: onMarkAllRead,
          child: Text(unreadCount == 0 ? '정리됨' : '모두 읽음'),
        ),
      ],
    );
  }
}

class _InboxSummaryCard extends StatelessWidget {
  final int totalCount;
  final int unreadCount;
  final PushNotificationSettings? settings;

  const _InboxSummaryCard({
    required this.totalCount,
    required this.unreadCount,
    required this.settings,
  });

  @override
  Widget build(BuildContext context) {
    final immediateCount = settings == null
        ? 0
        : _momentItems(settings!)
              .where(
                (item) => item.delivery == PushNotificationDelivery.immediate,
              )
              .length;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.divider),
        boxShadow: [
          BoxShadow(
            color: AppColors.live.withValues(alpha: 0.12),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.live.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: AppColors.live.withValues(alpha: 0.38),
                  ),
                ),
                child: const Icon(
                  Icons.notifications_active_outlined,
                  color: AppColors.live,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '오늘 놓치지 않은 신호',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      totalCount == 0
                          ? '수신된 푸시가 이곳에 쌓입니다'
                          : '$totalCount개 수신 · $unreadCount개 안 읽음',
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
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _SummaryMetric(
                  label: '최근',
                  value: '$totalCount',
                  color: AppColors.live,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _SummaryMetric(
                  label: '안 읽음',
                  value: '$unreadCount',
                  color: AppColors.accent,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _SummaryMetric(
                  label: '바로',
                  value: '$immediateCount',
                  color: AppColors.positive,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SummaryMetric extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _SummaryMetric({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 62,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.cardSub,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.divider),
      ),
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
              color: color,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}

class _InboxFilterBar extends StatelessWidget {
  final _InboxFilter selected;
  final ValueChanged<_InboxFilter> onChanged;

  const _InboxFilterBar({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _InboxFilter.values.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final filter = _InboxFilter.values[index];
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

class _InboxTimeline extends StatelessWidget {
  final List<NotificationInboxEntry> entries;
  final ValueChanged<NotificationInboxEntry> onOpenEntry;

  const _InboxTimeline({required this.entries, required this.onOpenEntry});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        children: [
          for (int index = 0; index < entries.length; index++) ...[
            _InboxEntryRow(entry: entries[index], onTap: onOpenEntry),
            if (index != entries.length - 1)
              const Divider(
                color: AppColors.cardSub,
                height: 1,
                indent: 16,
                endIndent: 16,
              ),
          ],
        ],
      ),
    );
  }
}

class _InboxEntryRow extends StatelessWidget {
  final NotificationInboxEntry entry;
  final ValueChanged<NotificationInboxEntry> onTap;

  const _InboxEntryRow({required this.entry, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = _colorForEntry(entry);
    return AppPressable(
      onTap: () => onTap(entry),
      pressedScale: 0.985,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: color.withValues(alpha: 0.35)),
              ),
              child: Icon(_iconForEntry(entry), color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          entry.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: entry.read
                                ? FontWeight.w700
                                : FontWeight.w900,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _timeLabel(entry.receivedAt),
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textDisabled,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  if (entry.body.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      entry.body,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                        height: 1.35,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _SmallPill(label: _typeLabel(entry.type), color: color),
                      if (!entry.read)
                        const _SmallPill(label: '새 알림', color: AppColors.live),
                      if (entry.hasRoute)
                        const _SmallPill(
                          label: '바로 열기',
                          color: AppColors.accent,
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              entry.hasRoute
                  ? Icons.chevron_right_rounded
                  : Icons.check_rounded,
              size: 20,
              color: AppColors.textDisabled,
            ),
          ],
        ),
      ),
    );
  }
}

class _InboxEmptyState extends StatelessWidget {
  final _InboxFilter filter;

  const _InboxEmptyState({required this.filter});

  @override
  Widget build(BuildContext context) {
    return Container(
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
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.cardSub,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.divider),
            ),
            child: const Icon(
              Icons.notifications_none_rounded,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            filter == _InboxFilter.all ? '아직 받은 푸시가 없습니다' : '이 필터에 알림이 없습니다',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 5),
          const Text(
            '득점, 홈런, 타석, 야구 브리프처럼 앱 밖에서 온 신호가 이곳에 시간순으로 모입니다.',
            style: TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _InboxLoadingList extends StatelessWidget {
  const _InboxLoadingList();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var index = 0; index < 3; index++) ...[
          Container(
            height: 74,
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.divider),
            ),
          ),
          if (index != 2) const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _InboxPlaybookSection extends StatelessWidget {
  final PushNotificationSettings? settings;

  const _InboxPlaybookSection({required this.settings});

  @override
  Widget build(BuildContext context) {
    final loadedSettings = settings;
    final items = loadedSettings == null
        ? const <_MomentInboxItem>[]
        : _momentItems(loadedSettings);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                '받을 준비된 신호',
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            AppPressable(
              onTap: () => context.push('/settings'),
              child: const Row(
                children: [
                  Text(
                    '설정',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(width: 2),
                  Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.divider),
          ),
          child: items.isEmpty
              ? const _PlaybookLoadingRow()
              : Column(
                  children: [
                    for (int index = 0; index < items.length; index++) ...[
                      _PlaybookMomentRow(item: items[index]),
                      if (index != items.length - 1)
                        const Divider(
                          color: AppColors.cardSub,
                          height: 1,
                          indent: 16,
                          endIndent: 16,
                        ),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}

class _PlaybookLoadingRow extends StatelessWidget {
  const _PlaybookLoadingRow();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(16),
      child: Text(
        '알림 설정을 불러오는 중입니다',
        style: TextStyle(fontSize: 12, color: AppColors.textDisabled),
      ),
    );
  }
}

class _PlaybookMomentRow extends StatelessWidget {
  final _MomentInboxItem item;

  const _PlaybookMomentRow({required this.item});

  @override
  Widget build(BuildContext context) {
    final color = _deliveryColor(item.delivery);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      child: Row(
        children: [
          Icon(item.icon, size: 19, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.label,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  item.description,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textDisabled,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _SmallPill(label: _deliveryLabel(item.delivery), color: color),
        ],
      ),
    );
  }
}

class _SmallPill extends StatelessWidget {
  final String label;
  final Color color;

  const _SmallPill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.34)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          color: color,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _MomentInboxItem {
  final String label;
  final String description;
  final PushNotificationDelivery delivery;
  final IconData icon;

  const _MomentInboxItem({
    required this.label,
    required this.description,
    required this.delivery,
    required this.icon,
  });
}

List<_MomentInboxItem> _momentItems(PushNotificationSettings settings) {
  return [
    _MomentInboxItem(
      label: '경기 시작',
      description: '플레이볼과 시작 임박 알림',
      delivery: settings.gameStartDelivery,
      icon: Icons.sports_baseball_rounded,
    ),
    _MomentInboxItem(
      label: '득점',
      description: '점수 변화 즉시 알림',
      delivery: settings.scoringDelivery,
      icon: Icons.scoreboard_outlined,
    ),
    _MomentInboxItem(
      label: '안타',
      description: '타구 결과와 주자 상황',
      delivery: settings.hitDelivery,
      icon: Icons.sports_baseball_outlined,
    ),
    _MomentInboxItem(
      label: '홈런',
      description: '큰 장면 별도 알림',
      delivery: settings.homerunDelivery,
      icon: Icons.bolt_outlined,
    ),
    _MomentInboxItem(
      label: '역전',
      description: '승부 흐름 변화',
      delivery: settings.reversalDelivery,
      icon: Icons.swap_vert_rounded,
    ),
    _MomentInboxItem(
      label: '경기 종료',
      description: '최종 결과 확인',
      delivery: settings.gameEndDelivery,
      icon: Icons.flag_outlined,
    ),
    _MomentInboxItem(
      label: '라인업',
      description: '선발 공개와 변경',
      delivery: settings.lineupOpenedDelivery,
      icon: Icons.format_list_numbered_rounded,
    ),
    _MomentInboxItem(
      label: '이닝 교대',
      description: '라이브 표면 갱신',
      delivery: settings.inningChangeDelivery,
      icon: Icons.repeat_rounded,
    ),
    _MomentInboxItem(
      label: '타석',
      description: '새 타자 문자중계 연결',
      delivery: settings.atBatDelivery,
      icon: Icons.person_search_outlined,
    ),
    _MomentInboxItem(
      label: '야구 브리프',
      description: '일정, 순위, 기록 확인',
      delivery: settings.baseballInfoDelivery,
      icon: Icons.article_outlined,
    ),
  ];
}

String _timeLabel(DateTime receivedAt) {
  final now = DateTime.now();
  final local = receivedAt.toLocal();
  if (now.year == local.year &&
      now.month == local.month &&
      now.day == local.day) {
    return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }
  return '${local.month.toString().padLeft(2, '0')}.${local.day.toString().padLeft(2, '0')}';
}

String _typeLabel(String type) {
  return switch (type) {
    'game_start' || 'game_start_soon' => '경기 시작',
    'scoring' => '득점',
    'hit' => '안타',
    'homerun' => '홈런',
    'reversal' => '역전',
    'game_end' => '경기 종료',
    'lineup_opened' || 'lineup_changed' => '라인업',
    'inning_change' => '이닝 교대',
    'at_bat' => '타석',
    'baseball_info' => '야구 브리프',
    _ => '푸시',
  };
}

IconData _iconForEntry(NotificationInboxEntry entry) {
  return switch (entry.type) {
    'scoring' => Icons.scoreboard_outlined,
    'hit' => Icons.sports_baseball_outlined,
    'homerun' => Icons.bolt_outlined,
    'reversal' => Icons.swap_vert_rounded,
    'lineup_opened' || 'lineup_changed' => Icons.format_list_numbered_rounded,
    'at_bat' => Icons.person_search_outlined,
    'baseball_info' => Icons.article_outlined,
    _ => Icons.notifications_active_outlined,
  };
}

Color _colorForEntry(NotificationInboxEntry entry) {
  return switch (entry.type) {
    'baseball_info' => AppColors.accent,
    'lineup_opened' || 'lineup_changed' => AppColors.ballYellow,
    'hit' || 'homerun' || 'scoring' || 'reversal' => AppColors.live,
    'game_end' => AppColors.positive,
    _ => AppColors.textSecondary,
  };
}

String _deliveryLabel(PushNotificationDelivery delivery) {
  return switch (delivery) {
    PushNotificationDelivery.immediate => '바로',
    PushNotificationDelivery.summary => '요약',
    PushNotificationDelivery.liveOnly => '라이브',
    PushNotificationDelivery.off => '끔',
  };
}

Color _deliveryColor(PushNotificationDelivery delivery) {
  return switch (delivery) {
    PushNotificationDelivery.immediate => AppColors.live,
    PushNotificationDelivery.summary => AppColors.positive,
    PushNotificationDelivery.liveOnly => AppColors.accent,
    PushNotificationDelivery.off => AppColors.textDisabled,
  };
}
