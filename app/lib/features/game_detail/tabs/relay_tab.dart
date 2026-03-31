import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models/game.dart';
import '../../../data/models/relay.dart';
import '../../../data/providers.dart';

class RelayTab extends ConsumerStatefulWidget {
  final String gameId;
  final GameStatus gameStatus;

  const RelayTab({super.key, required this.gameId, required this.gameStatus});

  @override
  ConsumerState<RelayTab> createState() => _RelayTabState();
}

class _RelayTabState extends ConsumerState<RelayTab> {
  final ScrollController _scrollController = ScrollController();
  final Map<String, GlobalKey> _inningKeys = {};

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final relayDataAsync = ref.watch(relayDataProvider(widget.gameId));

    return relayDataAsync.when(
      loading: () =>
          const Center(child: CircularProgressIndicator(color: AppColors.live)),
      error: (_, _) => _buildUnavailableState(),
      data: (relayData) {
        if (relayData.relayItems.isEmpty && relayData.currentAtBat == null) {
          return _buildUnavailableState();
        }
        return _buildContent(relayData.relayItems, relayData.currentAtBat);
      },
    );
  }

  Widget _buildUnavailableState() {
    final message = switch (widget.gameStatus) {
      GameStatus.live => '실시간 문자중계는 준비 중입니다',
      GameStatus.final_ => '이 경기의 문자중계 데이터가 아직 없습니다',
      GameStatus.cancelled => '취소된 경기는 문자중계를 제공하지 않습니다',
      GameStatus.suspended => '서스펜디드 경기는 재개 전까지 문자중계를 제공하지 않습니다',
      GameStatus.scheduled => '경기 시작 후 문자중계가 제공됩니다',
    };

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.sports_baseball, size: 48, color: AppColors.divider),
          const SizedBox(height: 12),
          Text(message, style: const TextStyle(color: AppColors.textDisabled)),
        ],
      ),
    );
  }

  Widget _buildContent(List<RelayItem> items, CurrentAtBat? atBat) {
    final moments = _buildMoments(items);

    return CustomScrollView(
      controller: _scrollController,
      slivers: [
        if (atBat != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: _CurrentAtBatHero(atBat: atBat),
            ),
          ),
        if (items.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: 14),
              child: _buildInningChips(items),
            ),
          ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
          sliver: SliverList.separated(
            itemCount: moments.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final moment = moments[index];
              final key = _inningKeys.putIfAbsent(
                '${moment.inningLabel}-$index',
                () => GlobalKey(),
              );
              return KeyedSubtree(
                key: key,
                child: _RelayMomentCard(moment: moment),
              );
            },
          ),
        ),
      ],
    );
  }

  List<_RelayMoment> _buildMoments(List<RelayItem> items) {
    final moments = <_RelayMoment>[];
    var currentInningLabel = '';
    _RelayMomentBuilder? current;

    for (final item in items) {
      if (item.event == 'INNING_CHANGE') {
        currentInningLabel = _chipLabel(item.text);
        current = null;
        continue;
      }

      final inningLabel = currentInningLabel.isNotEmpty
          ? currentInningLabel
          : '${item.inning}${item.half == 'top' ? '회초' : '회말'}';

      final isPitchDetail = item.text.startsWith('- ');
      if (isPitchDetail) {
        if (current == null) {
          current = _RelayMomentBuilder(
            inningLabel: inningLabel,
            lead: item,
          );
          moments.add(current.build());
          current = null;
        } else {
          current.pitchItems.add(item);
          moments[moments.length - 1] = current.build();
        }
        continue;
      }

      current = _RelayMomentBuilder(
        inningLabel: inningLabel,
        lead: item,
      );
      moments.add(current.build());
    }

    return moments;
  }

  Widget _buildInningChips(List<RelayItem> items) {
    final chips = <String>[];
    for (final item in items) {
      if (item.inning >= 900) continue;
      final label = item.event == 'INNING_CHANGE'
          ? _chipLabel(item.text)
          : '${item.inning}${item.half == "top" ? "회초" : "회말"}';
      if (!chips.contains(label)) {
        chips.add(label);
      }
    }

    if (chips.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: chips.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final label = chips[index];
          final isActive = index == chips.length - 1;
          return GestureDetector(
            onTap: () => _scrollToInning(label),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: isActive ? AppColors.textPrimary : AppColors.cardSub,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: isActive
                      ? AppColors.background
                      : AppColors.textDisabled,
                  fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _scrollToInning(String label) {
    GlobalKey? targetKey;
    for (final entry in _inningKeys.entries) {
      if (entry.key.startsWith(label)) {
        targetKey = entry.value;
        break;
      }
    }
    if (targetKey == null || targetKey.currentContext == null) {
      return;
    }
    Scrollable.ensureVisible(
      targetKey.currentContext!,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      alignment: 0.1,
    );
  }

  String _chipLabel(String label) {
    if (label.contains('회초') || label.contains('회말')) {
      return label;
    }
    return label.replaceAll(' 공격 ---------------------------------------', '');
  }
}

class _CurrentAtBatHero extends StatelessWidget {
  final CurrentAtBat atBat;

  const _CurrentAtBatHero({required this.atBat});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 380;

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.divider),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text(
                    '현재 타석',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                  if (atBat.inningText.isNotEmpty)
                    _RelayPill(
                      label: atBat.inningText,
                      color: AppColors.textPrimary,
                      subtle: true,
                    ),
                  if (atBat.baseState.isNotEmpty)
                    _BaseStateBadge(baseState: atBat.baseState),
                ],
              ),
              const SizedBox(height: 12),
              if (isCompact) ...[
                _ParticipantCard(
                  title: '타자',
                  name: _formatBatterLabel(atBat),
                  detail: atBat.batterRecent.isEmpty
                      ? '최근 타석 정보 없음'
                      : '최근 타석: ${atBat.batterRecent}',
                ),
                const SizedBox(height: 10),
                _ParticipantCard(
                  title: '상대투수',
                  name: _formatPitcherLabel(atBat),
                  detail: atBat.pitchCount > 0 ? '${atBat.pitchCount}구' : '투구 수 집계 중',
                ),
              ] else
                Row(
                  children: [
                    Expanded(
                      child: _ParticipantCard(
                        title: '타자',
                        name: _formatBatterLabel(atBat),
                        detail: atBat.batterRecent.isEmpty
                            ? '최근 타석 정보 없음'
                            : '최근 타석: ${atBat.batterRecent}',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _ParticipantCard(
                        title: '상대투수',
                        name: _formatPitcherLabel(atBat),
                        detail: atBat.pitchCount > 0 ? '${atBat.pitchCount}구' : '투구 수 집계 중',
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 20,
                runSpacing: 10,
                children: [
                  _CountMeter('B', atBat.balls, 4, AppColors.ballYellow),
                  _CountMeter('S', atBat.strikes, 3, AppColors.live),
                  _CountMeter('O', atBat.outs, 3, AppColors.textPrimary),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  String _formatBatterLabel(CurrentAtBat ab) {
    final number = ab.batterNumber > 0 ? '${ab.batterNumber}번 ' : '';
    final hand = ab.batterHand.isNotEmpty ? ' · ${ab.batterHand}' : '';
    return '$number${ab.batterName}$hand';
  }

  String _formatPitcherLabel(CurrentAtBat ab) {
    final hand = ab.pitcherHand.isNotEmpty ? ' · ${ab.pitcherHand}' : '';
    return '${ab.pitcherName}$hand';
  }
}

class _ParticipantCard extends StatelessWidget {
  final String title;
  final String name;
  final String detail;

  const _ParticipantCard({
    required this.title,
    required this.name,
    required this.detail,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.cardSub,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 11, color: AppColors.textDisabled),
          ),
          const SizedBox(height: 6),
          Text(
            name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            detail,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _CountMeter extends StatelessWidget {
  final String label;
  final int filled;
  final int total;
  final Color activeColor;

  const _CountMeter(this.label, this.filled, this.total, this.activeColor);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: AppColors.textDisabled),
        ),
        const SizedBox(width: 6),
        for (int i = 0; i < total; i++)
          Container(
            width: 12,
            height: 12,
            margin: const EdgeInsets.only(right: 4),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: i < filled ? activeColor : Colors.transparent,
              border: Border.all(
                color: i < filled ? activeColor : AppColors.divider,
                width: 1.4,
              ),
            ),
          ),
      ],
    );
  }
}

class _RelayMomentCard extends StatelessWidget {
  final _RelayMoment moment;

  const _RelayMomentCard({required this.moment});

  @override
  Widget build(BuildContext context) {
    final accent = moment.isScoring
        ? AppColors.live
        : moment.isSubstitution
        ? AppColors.accent
        : AppColors.textSecondary;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: moment.isScoring
            ? const Color(0xFF1C1111)
            : AppColors.cardSub,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: moment.isScoring
              ? AppColors.live.withValues(alpha: 0.45)
              : AppColors.divider,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _RelayPill(
                label: moment.inningLabel,
                color: AppColors.textPrimary,
                subtle: true,
              ),
              const SizedBox(width: 8),
              if (moment.isScoring)
                const _RelayPill(label: '득점 장면', color: AppColors.live),
              if (moment.isSubstitution)
                const _RelayPill(label: '교체', color: AppColors.accent),
              if (moment.isGameEnd)
                const _RelayPill(label: '경기 종료', color: AppColors.textPrimary),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            moment.lead.text,
            style: TextStyle(
              fontSize: 15,
              fontWeight: moment.isScoring || moment.isGameEnd
                  ? FontWeight.w800
                  : FontWeight.w700,
              color: AppColors.textPrimary,
              height: 1.35,
            ),
          ),
          if (moment.pitchItems.isNotEmpty) ...[
            const SizedBox(height: 10),
            for (final pitch in moment.pitchItems) ...[
              _PitchLogRow(text: pitch.text),
              if (pitch != moment.pitchItems.last) const SizedBox(height: 6),
            ],
          ],
          if (moment.lead.pitchSequence != null &&
              moment.lead.pitchSequence!.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              moment.lead.pitchSequence!,
              style: TextStyle(
                fontSize: 11,
                color: accent,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PitchLogRow extends StatelessWidget {
  final String text;

  const _PitchLogRow({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.background.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text.replaceFirst('- ', ''),
        style: const TextStyle(
          fontSize: 12,
          color: AppColors.textSecondary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _RelayPill extends StatelessWidget {
  final String label;
  final Color color;
  final bool subtle;

  const _RelayPill({
    required this.label,
    required this.color,
    this.subtle = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: subtle ? AppColors.background : color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: subtle ? AppColors.divider : color.withValues(alpha: 0.3),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: subtle ? AppColors.textSecondary : color,
        ),
      ),
    );
  }
}

class _BaseStateBadge extends StatelessWidget {
  final String baseState;

  const _BaseStateBadge({required this.baseState});

  @override
  Widget build(BuildContext context) {
    final occupiedBases = switch (baseState) {
      '주자1루' => {1},
      '주자2루' => {2},
      '주자3루' => {3},
      '주자1,2루' => {1, 2},
      '주자1,3루' => {1, 3},
      '주자2,3루' => {2, 3},
      '만루' => {1, 2, 3},
      _ => <int>{},
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Transform.rotate(
                  angle: 0.785398,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: AppColors.textDisabled,
                        width: 1,
                      ),
                    ),
                  ),
                ),
                _baseDot(occupiedBases.contains(2), const Offset(0, -5)),
                _baseDot(occupiedBases.contains(1), const Offset(5, 0)),
                _baseDot(occupiedBases.contains(3), const Offset(-5, 0)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            baseState,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.accent,
            ),
          ),
        ],
      ),
    );
  }

  Widget _baseDot(bool visible, Offset offset) {
    return Transform.translate(
      offset: offset,
      child: Container(
        width: 5,
        height: 5,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: visible ? AppColors.accent : Colors.transparent,
          border: Border.all(
            color: visible ? AppColors.accent : AppColors.textDisabled,
            width: 0.8,
          ),
        ),
      ),
    );
  }
}

class _RelayMoment {
  final String inningLabel;
  final RelayItem lead;
  final List<RelayItem> pitchItems;
  final bool isScoring;
  final bool isGameEnd;
  final bool isSubstitution;

  const _RelayMoment({
    required this.inningLabel,
    required this.lead,
    required this.pitchItems,
    required this.isScoring,
    required this.isGameEnd,
    required this.isSubstitution,
  });
}

class _RelayMomentBuilder {
  final String inningLabel;
  final RelayItem lead;
  final List<RelayItem> pitchItems = [];

  _RelayMomentBuilder({
    required this.inningLabel,
    required this.lead,
  });

  _RelayMoment build() {
    return _RelayMoment(
      inningLabel: inningLabel,
      lead: lead,
      pitchItems: List<RelayItem>.from(pitchItems),
      isScoring: lead.isScoring,
      isGameEnd: lead.event == 'GAME_END',
      isSubstitution: lead.event == 'SUBSTITUTION',
    );
  }
}
