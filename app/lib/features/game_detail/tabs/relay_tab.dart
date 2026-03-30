import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/relay.dart';
import '../../../data/mock/mock_game_detail.dart';

class RelayTab extends StatelessWidget {
  final String gameId;
  const RelayTab({super.key, required this.gameId});

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        // 현재 타석 카드
        SliverToBoxAdapter(child: _buildCurrentAtBat()),
        // 이닝 점프 칩
        SliverToBoxAdapter(child: _buildInningChips()),
        // 중계 피드
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverList.builder(
            itemCount: mockRelayItems.length,
            itemBuilder: (context, index) {
              final item = mockRelayItems[index];
              final prevItem = index > 0 ? mockRelayItems[index - 1] : null;
              final showDivider = prevItem != null &&
                  (prevItem.inning != item.inning || prevItem.half != item.half);

              return Column(
                children: [
                  if (item.event == 'INNING_CHANGE')
                    _buildInningDivider(item.text)
                  else ...[
                    if (showDivider) const SizedBox(height: 8),
                    _buildRelayItem(item),
                    const SizedBox(height: 8),
                  ],
                ],
              );
            },
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }

  Widget _buildCurrentAtBat() {
    const ab = mockCurrentAtBat;
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('타자: No.${ab.batterNumber} ${ab.batterName} (${ab.batterHand})',
                  style: const TextStyle(fontSize: 14)),
              Text('투수: No.${ab.pitcherNumber} ${ab.pitcherName} (${ab.pitcherHand}) · ${ab.pitchCount}구',
                  style: const TextStyle(fontSize: 14, color: AppColors.textSecondary)),
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
        Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textDisabled)),
        const SizedBox(width: 6),
        for (int i = 0; i < total; i++) ...[
          Container(
            width: 12,
            height: 12,
            margin: const EdgeInsets.only(right: 4),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: i < filled ? activeColor : Colors.transparent,
              border: Border.all(color: i < filled ? activeColor : AppColors.divider, width: 1.5),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildInningChips() {
    final chips = ['1초', '1말', '2초', '2말', '3초', '3말', '4초'];
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
            child: Text(text, style: const TextStyle(fontSize: 12, color: AppColors.textDisabled)),
          ),
          const Expanded(child: Divider(color: AppColors.divider)),
        ],
      ),
    );
  }

  Widget _buildRelayItem(RelayItem item) {
    final isScoring = item.isScoring;
    final borderColor = isScoring ? AppColors.live : AppColors.divider;
    final bgColor = isScoring ? const Color(0xFF1C1111) : Colors.transparent;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border(left: BorderSide(color: borderColor, width: 4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${isScoring ? "🔴" : "⚪"} ${item.text}',
            style: TextStyle(
              fontSize: 14,
              fontWeight: isScoring ? FontWeight.w600 : FontWeight.normal,
              color: isScoring ? AppColors.textPrimary : AppColors.textSecondary,
            ),
          ),
          if (item.pitchSequence != null) ...[
            const SizedBox(height: 4),
            Text(item.pitchSequence!, style: const TextStyle(fontSize: 11, color: AppColors.textDisabled)),
          ],
        ],
      ),
    );
  }
}
