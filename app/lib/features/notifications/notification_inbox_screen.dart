import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_route_sanitizer.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_motion.dart';
import '../../core/widgets/app_page_frame.dart';
import '../../services/notification_inbox_service.dart';
import '../../services/push_notification_service.dart';

typedef NotificationInboxEntriesLoader =
    Future<List<NotificationInboxEntry>> Function();
typedef NotificationInboxSettingsLoader =
    Future<PushNotificationSettings> Function();

enum _InboxFilter {
  all(label: '전체'),
  unread(label: '안 읽음'),
  games(label: '경기'),
  brief(label: '브리프');

  final String label;
  const _InboxFilter({required this.label});
}

class NotificationInboxScreen extends StatefulWidget {
  final NotificationInboxEntriesLoader? entriesLoader;
  final NotificationInboxSettingsLoader? settingsLoader;

  const NotificationInboxScreen({
    super.key,
    this.entriesLoader,
    this.settingsLoader,
  });

  @override
  State<NotificationInboxScreen> createState() =>
      _NotificationInboxScreenState();
}

class _NotificationInboxScreenState extends State<NotificationInboxScreen> {
  _InboxFilter _filter = _InboxFilter.all;
  List<NotificationInboxEntry>? _entries;
  PushNotificationSettings? _settings;
  Object? _entriesError;
  Object? _settingsError;
  bool _entriesLoading = true;
  bool _settingsLoading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    await Future.wait<void>([_loadEntries(), _loadSettings()]);
  }

  Future<void> _loadEntries() async {
    if (mounted) {
      setState(() {
        _entriesLoading = true;
        _entriesError = null;
      });
    }
    try {
      final entries =
          await (widget.entriesLoader?.call() ??
              NotificationInboxService.instance.loadEntries());
      if (!mounted) {
        return;
      }
      setState(() {
        _entries = entries;
        _entriesLoading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _entriesError = error;
        _entriesLoading = false;
      });
    }
  }

  Future<void> _loadSettings() async {
    if (mounted) {
      setState(() {
        _settingsLoading = true;
        _settingsError = null;
      });
    }
    try {
      final settings =
          await (widget.settingsLoader?.call() ??
              PushNotificationService.instance.loadSettings());
      if (!mounted) {
        return;
      }
      setState(() {
        _settings = settings;
        _settingsLoading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _settingsError = error;
        _settingsLoading = false;
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
    final entries = _entries;
    if (entries == null) {
      return;
    }
    setState(() {
      _entries = [
        for (final item in entries)
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
    final entries = _entries;
    final visibleEntries = entries == null
        ? const <NotificationInboxEntry>[]
        : _filteredEntries(entries, _filter);
    final unreadCount = entries?.where((entry) => !entry.read).length;
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
                  onMarkAllRead: unreadCount == null || unreadCount == 0
                      ? null
                      : _markAllRead,
                ),
                const SizedBox(height: 14),
                _InboxSummaryCard(
                  totalCount: entries?.length,
                  visibleCount: entries == null ? null : visibleEntries.length,
                  unreadCount: unreadCount,
                  isLoading: _entriesLoading,
                  hasError: _entriesError != null,
                ),
                const SizedBox(height: 14),
                _InboxFilterBar(
                  selected: _filter,
                  onChanged: (filter) => setState(() => _filter = filter),
                ),
                const SizedBox(height: 14),
                AppMotionSwitcher(child: _buildEntriesContent(visibleEntries)),
                const SizedBox(height: 18),
                _InboxPlaybookSection(
                  settings: settings,
                  isLoading: _settingsLoading,
                  hasError: _settingsError != null,
                  onRetry: () => unawaited(_loadSettings()),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEntriesContent(List<NotificationInboxEntry> visibleEntries) {
    if (_entries == null) {
      if (_entriesLoading) {
        return const KeyedSubtree(
          key: ValueKey('notification-inbox-loading'),
          child: _InboxLoadingList(),
        );
      }
      return KeyedSubtree(
        key: const ValueKey('notification-inbox-entries-error'),
        child: _InboxLoadErrorState(
          title: '최근 알림을 불러오지 못했습니다',
          body: '보관된 알림 목록만 확인할 수 없습니다. 알림 설정은 별도로 계속 불러옵니다.',
          actionLabel: '알림 목록 다시 시도',
          onRetry: () => unawaited(_loadEntries()),
        ),
      );
    }

    return KeyedSubtree(
      key: ValueKey(
        'notification-inbox-${_filter.name}-${visibleEntries.length}'
        '-error-${_entriesError != null}-loading-$_entriesLoading',
      ),
      child: Column(
        children: [
          if (_entriesError != null) ...[
            _InboxLoadNotice(
              message: '최근 알림 갱신에 실패해 이전 목록을 표시합니다.',
              actionLabel: '다시 시도',
              onRetry: () => unawaited(_loadEntries()),
            ),
            const SizedBox(height: 10),
          ],
          if (_entriesLoading) ...[
            const LinearProgressIndicator(minHeight: 2),
            const SizedBox(height: 10),
          ],
          if (visibleEntries.isEmpty)
            _InboxEmptyState(filter: _filter)
          else
            _InboxTimeline(entries: visibleEntries, onOpenEntry: _openEntry),
        ],
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
  final int? unreadCount;
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
        Expanded(
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
          child: Text(
            unreadCount == null
                ? '확인 불가'
                : unreadCount == 0
                ? '정리됨'
                : '모두 읽음',
          ),
        ),
      ],
    );
  }
}

class _InboxSummaryCard extends StatelessWidget {
  final int? totalCount;
  final int? visibleCount;
  final int? unreadCount;
  final bool isLoading;
  final bool hasError;

  const _InboxSummaryCard({
    required this.totalCount,
    required this.visibleCount,
    required this.unreadCount,
    required this.isLoading,
    required this.hasError,
  });

  @override
  Widget build(BuildContext context) {
    final hasCounts =
        totalCount != null && visibleCount != null && unreadCount != null;
    final summary = hasCounts
        ? '최근 최대 50개 보관 · $totalCount개 중 $visibleCount개 표시'
        : isLoading
        ? '최근 알림을 최대 50개까지 불러오는 중입니다'
        : hasError
        ? '최근 최대 50개 보관 · 현재 표시 수 확인 불가'
        : '최근 알림을 최대 50개까지 보관합니다';
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
                child: Icon(
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
                      '최근 알림 보관함',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      summary,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
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
                  label: '보관',
                  value: totalCount?.toString() ?? '—',
                  color: AppColors.live,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _SummaryMetric(
                  label: '현재 표시',
                  value: visibleCount?.toString() ?? '—',
                  color: AppColors.accent,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _SummaryMetric(
                  label: '안 읽음',
                  value: unreadCount?.toString() ?? '—',
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
      height: 44,
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
            semanticSelected: isSelected,
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
              Divider(
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
                        style: TextStyle(
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
                      style: TextStyle(
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
                        _SmallPill(label: '새 알림', color: AppColors.live),
                      if (entry.hasRoute)
                        _SmallPill(label: '바로 열기', color: AppColors.accent),
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
            child: Icon(
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
          Text(
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

class _InboxLoadErrorState extends StatelessWidget {
  final String title;
  final String body;
  final String actionLabel;
  final VoidCallback onRetry;

  const _InboxLoadErrorState({
    required this.title,
    required this.body,
    required this.actionLabel,
    required this.onRetry,
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
          Icon(Icons.sync_problem_rounded, color: AppColors.ballYellow),
          const SizedBox(height: 10),
          Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 5),
          Text(
            body,
            style: TextStyle(
              fontSize: 12,
              height: 1.4,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onRetry, child: Text(actionLabel)),
        ],
      ),
    );
  }
}

class _InboxLoadNotice extends StatelessWidget {
  final String message;
  final String actionLabel;
  final VoidCallback onRetry;

  const _InboxLoadNotice({
    required this.message,
    required this.actionLabel,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(
        color: AppColors.ballYellow.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.ballYellow.withValues(alpha: 0.32)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: 18,
            color: AppColors.ballYellow,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 11,
                height: 1.35,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          TextButton(onPressed: onRetry, child: Text(actionLabel)),
        ],
      ),
    );
  }
}

class _InboxPlaybookSection extends StatelessWidget {
  final PushNotificationSettings? settings;
  final bool isLoading;
  final bool hasError;
  final VoidCallback onRetry;

  const _InboxPlaybookSection({
    required this.settings,
    required this.isLoading,
    required this.hasError,
    required this.onRetry,
  });

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
            Expanded(
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
              onTap: () => context.go('/settings'),
              child: Row(
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
        if (hasError && loadedSettings != null) ...[
          _InboxLoadNotice(
            message: '알림 설정 갱신에 실패해 이전 설정을 표시합니다.',
            actionLabel: '설정 다시 시도',
            onRetry: onRetry,
          ),
          const SizedBox(height: 8),
        ],
        Container(
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.divider),
          ),
          child: loadedSettings == null
              ? _PlaybookLoadingRow(
                  isLoading: isLoading,
                  hasError: hasError,
                  onRetry: onRetry,
                )
              : Column(
                  children: [
                    if (isLoading) const LinearProgressIndicator(minHeight: 2),
                    for (int index = 0; index < items.length; index++) ...[
                      _PlaybookMomentRow(item: items[index]),
                      if (index != items.length - 1)
                        Divider(
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
  final bool isLoading;
  final bool hasError;
  final VoidCallback onRetry;

  const _PlaybookLoadingRow({
    required this.isLoading,
    required this.hasError,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(
            child: Text(
              isLoading
                  ? '알림 설정을 불러오는 중입니다'
                  : hasError
                  ? '알림 설정을 확인할 수 없습니다. 알림 목록은 그대로 유지됩니다.'
                  : '저장된 알림 설정이 없습니다',
              style: TextStyle(fontSize: 12, color: AppColors.textDisabled),
            ),
          ),
          if (hasError)
            TextButton(onPressed: onRetry, child: const Text('알림 설정 다시 시도')),
        ],
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
                  style: TextStyle(fontSize: 11, color: AppColors.textDisabled),
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
