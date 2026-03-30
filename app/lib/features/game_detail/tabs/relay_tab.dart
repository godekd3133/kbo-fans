import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models/game.dart';
import '../../../data/models/relay.dart';
import '../../../data/providers.dart';

class RelayTab extends ConsumerWidget {
  final String gameId;
  final GameStatus gameStatus;

  const RelayTab({super.key, required this.gameId, required this.gameStatus});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final relayDataAsync = ref.watch(relayDataProvider(gameId));

    return relayDataAsync.when(
      loading: () =>
          const Center(child: CircularProgressIndicator(color: AppColors.live)),
      error: (e, _) => _buildUnavailableState(),
      data: (relayData) {
        if (relayData.relayItems.isEmpty && relayData.currentAtBat == null) {
          return _buildUnavailableState();
        }
        return _buildContent(relayData.relayItems, relayData.currentAtBat);
      },
    );
  }

  Widget _buildUnavailableState() {
    final message = switch (gameStatus) {
      GameStatus.live => '실시간 문자중계는 준비 중입니다',
      GameStatus.final_ => '이 경기의 문자중계 데이터가 아직 없습니다',
      GameStatus.cancelled => '취소된 경기는 문자중계를 제공하지 않습니다',
      GameStatus.scheduled => '경기 시작 후 문자중계가 제공됩니다',
    };

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.sports_baseball, size: 48, color: AppColors.divider),
          const SizedBox(height: 12),
          Text(message, style: TextStyle(color: AppColors.textDisabled)),
        ],
      ),
    );
  }

  Widget _buildContent(List<RelayItem> items, CurrentAtBat? atBat) {
    if (items.isEmpty && atBat == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.sports_baseball, size: 48, color: AppColors.divider),
            const SizedBox(height: 12),
            Text(
              '문자중계 데이터가 없습니다',
              style: TextStyle(color: AppColors.textDisabled),
            ),
          ],
        ),
      );
    }

    return CustomScrollView(
      slivers: [
        if (atBat != null) SliverToBoxAdapter(child: _buildCurrentAtBat(atBat)),
        if (items.isNotEmpty) ...[
          SliverToBoxAdapter(child: _buildInningChips(items)),
        ],
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverList.builder(
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              if (item.event == 'INNING_CHANGE') {
                return _buildInningDivider(item.text);
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
      if (item.inning >= 900) {
        continue;
      }
      final label = '${item.inning}${item.half == "top" ? "초" : "말"}';
      if (!chips.contains(label)) {
        chips.add(label);
      }
    }

    if (chips.isEmpty) return const SizedBox.shrink();

    return Container(
      height: 36,
      margin: const EdgeInsets.only(bottom: 12),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: chips.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final isActive = index == chips.length - 1;
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isActive ? AppColors.textPrimary : AppColors.cardSub,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              chips[index],
              style: TextStyle(
                fontSize: 12,
                color: isActive ? AppColors.background : AppColors.textDisabled,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
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
            : isPitchDetail
            ? AppColors.cardSub.withValues(alpha: 0.45)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        border: Border(
          left: BorderSide(
            color: isGameEnd
                ? AppColors.textPrimary
                : isScoring
                ? AppColors.live
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
          Text(
            item.text,
            style: TextStyle(
              fontSize: isPitchDetail ? 12 : 14,
              fontWeight: isScoring || isGameEnd
                  ? FontWeight.w700
                  : FontWeight.normal,
              color: isPitchDetail
                  ? AppColors.textDisabled
                  : AppColors.textPrimary,
            ),
          ),
          if (item.pitchSequence != null) ...[
            const SizedBox(height: 4),
            Text(
              item.pitchSequence!,
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textDisabled,
              ),
            ),
          ],
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
}
