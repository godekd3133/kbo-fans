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
    return CustomScrollView(
      controller: _scrollController,
      slivers: [
        if (atBat != null) SliverToBoxAdapter(child: _buildCurrentAtBat(atBat)),
        if (items.isNotEmpty)
          SliverToBoxAdapter(child: _buildInningChips(items)),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverList.builder(
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              if (item.event == 'INNING_CHANGE') {
                final key = _inningKeys.putIfAbsent(
                  item.text,
                  () => GlobalKey(),
                );
                return KeyedSubtree(
                  key: key,
                  child: _buildInningDivider(item.text),
                );
              }
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _buildRelayItem(item),
              );
            },
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }

  Widget _buildCurrentAtBat(CurrentAtBat ab) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '현재 타석',
            style: TextStyle(fontSize: 12, color: AppColors.textDisabled),
          ),
          const SizedBox(height: 8),
          if (ab.inningText.isNotEmpty || ab.baseState.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (ab.inningText.isNotEmpty)
                    _statusBadge(
                      label: ab.inningText,
                      color: AppColors.textPrimary,
                      subtle: true,
                    ),
                  if (ab.baseState.isNotEmpty)
                    _BaseStateBadge(baseState: ab.baseState),
                ],
              ),
            ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  _formatBatterLabel(ab),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  _formatPitcherLabel(ab),
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          if (ab.batterRecent.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                '최근 타석: ${ab.batterRecent}',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textDisabled,
                ),
              ),
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildCount('B', ab.balls, 4, AppColors.ballYellow),
              const SizedBox(width: 24),
              _buildCount('S', ab.strikes, 3, AppColors.live),
              const SizedBox(width: 24),
              _buildCount('O', ab.outs, 3, AppColors.textPrimary),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCount(String label, int filled, int total, Color activeColor) {
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
                width: 1.5,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildInningChips(List<RelayItem> items) {
    final chips = <String>[];
    for (final item in items) {
      if (item.inning >= 900) continue;
      final label = item.event == 'INNING_CHANGE'
          ? item.text
          : '${item.inning}${item.half == "top" ? "회초" : "회말"}';
      if (!chips.contains(label)) {
        chips.add(label);
      }
    }

    if (chips.isEmpty) return const SizedBox.shrink();

    return Container(
      height: 40,
      margin: const EdgeInsets.only(bottom: 12),
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
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                _chipLabel(label),
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

  Widget _buildInningDivider(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          const Expanded(child: Divider(color: AppColors.divider)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textDisabled,
              ),
            ),
          ),
          const Expanded(child: Divider(color: AppColors.divider)),
        ],
      ),
    );
  }

  Widget _buildRelayItem(RelayItem item) {
    final isScoring = item.isScoring;
    final isPitchDetail = item.text.startsWith('- ');
    final isGameEnd = item.event == 'GAME_END';
    final isSubstitution = item.event == 'SUBSTITUTION';
    final isDecisionPitch =
        isPitchDetail &&
        (item.text.contains('타격') ||
            item.text.contains('헛스윙') ||
            item.text.contains('스트라이크') ||
            item.text.contains('볼'));
    final pitchBadge = _extractPitchBadge(item.text);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: 16,
        vertical: isPitchDetail ? 8 : 12,
      ),
      decoration: BoxDecoration(
        color: isGameEnd
            ? AppColors.card
            : isScoring
            ? const Color(0xFF1C1111)
            : isSubstitution
            ? AppColors.cardSub.withValues(alpha: 0.72)
            : isPitchDetail
            ? (isDecisionPitch
                  ? AppColors.background.withValues(alpha: 0.82)
                  : AppColors.cardSub.withValues(alpha: 0.45))
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        border: Border(
          left: BorderSide(
            color: isGameEnd
                ? AppColors.textPrimary
                : isScoring
                ? AppColors.live
                : isSubstitution
                ? AppColors.accent
                : AppColors.divider,
            width: 4,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isScoring || isGameEnd)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                isGameEnd ? '경기 종료' : '득점 장면',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: isGameEnd ? AppColors.textPrimary : AppColors.live,
                ),
              ),
            ),
          if (isSubstitution)
            const Padding(
              padding: EdgeInsets.only(bottom: 6),
              child: Text(
                '교체',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.accent,
                ),
              ),
            ),
          Text(
            item.text,
            style: TextStyle(
              fontSize: isPitchDetail ? 12 : 14,
              fontWeight: isScoring || isGameEnd
                  ? FontWeight.w700
                  : FontWeight.normal,
              color: isSubstitution
                  ? AppColors.textPrimary
                  : isPitchDetail
                  ? AppColors.textDisabled
                  : AppColors.textPrimary,
            ),
          ),
          if (pitchBadge != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Wrap(
                spacing: 8,
                children: [
                  _pill(pitchBadge.$1, AppColors.textSecondary, subtle: true),
                  _pill(pitchBadge.$3, pitchBadge.$2),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _formatBatterLabel(CurrentAtBat ab) {
    final number = ab.batterNumber > 0 ? 'No.${ab.batterNumber} ' : '';
    final hand = ab.batterHand.isNotEmpty ? ' (${ab.batterHand})' : '';
    return '타자  $number${ab.batterName}$hand';
  }

  String _formatPitcherLabel(CurrentAtBat ab) {
    final number = ab.pitcherNumber > 0 ? 'No.${ab.pitcherNumber} ' : '';
    final hand = ab.pitcherHand.isNotEmpty ? ' (${ab.pitcherHand})' : '';
    final pitchCount = ab.pitchCount > 0 ? ' · ${ab.pitchCount}구' : '';
    return '투수  $number${ab.pitcherName}$hand$pitchCount';
  }

  String _chipLabel(String label) {
    if (label.contains('회초') || label.contains('회말')) {
      return label;
    }
    return label.replaceAll(' 공격 ---------------------------------------', '');
  }

  void _scrollToInning(String label) {
    final targetKey = _inningKeys[label];
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

  (String, Color, String)? _extractPitchBadge(String text) {
    final match = RegExp(r'^-\s*(\d+구)\s+(.+)$').firstMatch(text);
    if (match == null) return null;

    final pitchNo = match.group(1)!;
    final result = match.group(2)!;
    final color = switch (result) {
      '볼' => AppColors.ballYellow,
      '스트라이크' => AppColors.live,
      '헛스윙' => AppColors.live,
      '파울' => AppColors.textSecondary,
      '타격' => AppColors.accent,
      _ => AppColors.textPrimary,
    };
    return (pitchNo, color, result);
  }

  Widget _statusBadge({
    required String label,
    required Color color,
    bool subtle = false,
  }) {
    return _pill(label, color, subtle: subtle);
  }

  Widget _pill(String label, Color color, {bool subtle = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: subtle ? AppColors.background : color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: subtle ? AppColors.divider : color.withValues(alpha: 0.28),
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
