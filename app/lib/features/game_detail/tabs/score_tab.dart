import 'package:flutter/material.dart';

import '../../../core/constants/visual_assets.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_artwork_card.dart';
import '../../../core/widgets/app_motion.dart';
import '../../../data/models/game.dart';
import '../../../data/models/relay.dart';

class ScoreTab extends StatelessWidget {
  final String gameId;
  final Game game;
  final Future<void> Function()? onRefresh;
  final Widget? footer;

  const ScoreTab({
    super.key,
    required this.gameId,
    required this.game,
    this.onRefresh,
    this.footer,
  });

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh ?? () async {},
      color: AppColors.live,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildInningTable(context, const <RelayItem>[]),
            if (footer != null) ...[const SizedBox(height: 12), footer!],
          ],
        ),
      ),
    );
  }

  Widget _buildInningTable(BuildContext context, List<RelayItem> relayItems) {
    final headers = [
      'TEAM',
      '1',
      '2',
      '3',
      '4',
      '5',
      '6',
      '7',
      '8',
      '9',
      'R',
      'H',
      'E',
      'B',
    ];
    const headerStyle = TextStyle(
      fontSize: 12,
      color: AppColors.textDisabled,
      fontWeight: FontWeight.w500,
    );
    const dataStyle = TextStyle(fontSize: 14, color: AppColors.textPrimary);
    const boldStyle = TextStyle(
      fontSize: 14,
      color: AppColors.textPrimary,
      fontWeight: FontWeight.w700,
    );
    final currentInning =
        int.tryParse(game.inning.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (relayItems.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              '이닝을 누르면 해당 회차 주요 장면을 볼 수 있습니다.',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.divider),
          ),
          child: Stack(
            children: [
              const Positioned.fill(
                child: AppArtworkLayer(
                  assetName: VisualAssets.scoreLinescore,
                  alignment: Alignment.centerRight,
                  opacity: 0.18,
                ),
              ),
              Table(
                defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                columnWidths: const {0: FixedColumnWidth(48)},
                children: [
                  TableRow(
                    children: headers.asMap().entries.map((entry) {
                      final idx = entry.key;
                      final text = entry.value;
                      final inningNo = idx >= 1 && idx <= 9 ? idx : null;
                      final isCurrentInning =
                          inningNo != null && inningNo == currentInning;
                      return _tableCell(
                        context,
                        text,
                        headerStyle,
                        isHighlight: isCurrentInning,
                        onTap: inningNo == null || relayItems.isEmpty
                            ? null
                            : () => _openInningSheet(
                                context,
                                inningNo,
                                relayItems,
                              ),
                      );
                    }).toList(),
                  ),
                  TableRow(
                    children: List.generate(
                      14,
                      (_) => const Divider(height: 1, color: AppColors.divider),
                    ),
                  ),
                  _scoreRow(
                    context,
                    game.away,
                    currentInning,
                    dataStyle,
                    boldStyle,
                    relayItems,
                  ),
                  TableRow(
                    children: List.generate(
                      14,
                      (_) => const Divider(height: 1, color: AppColors.divider),
                    ),
                  ),
                  _scoreRow(
                    context,
                    game.home,
                    currentInning,
                    dataStyle,
                    boldStyle,
                    relayItems,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  TableRow _scoreRow(
    BuildContext context,
    TeamScore team,
    int currentInning,
    TextStyle dataStyle,
    TextStyle boldStyle,
    List<RelayItem> relayItems,
  ) {
    return TableRow(
      children: [
        _tableCell(context, team.shortName, dataStyle),
        for (int i = 0; i < 9; i++)
          _tableCell(
            context,
            i < team.innings.length && team.innings[i] != null
                ? '${team.innings[i]}'
                : '-',
            dataStyle,
            isHighlight: (i + 1) == currentInning,
            onTap: relayItems.isEmpty
                ? null
                : () => _openInningSheet(context, i + 1, relayItems),
          ),
        _tableCell(context, '${team.score}', boldStyle),
        _tableCell(context, _teamStatText(team, team.hits), boldStyle),
        _tableCell(context, _teamStatText(team, team.errors), boldStyle),
        _tableCell(context, _teamStatText(team, team.walks), boldStyle),
      ],
    );
  }

  String _teamStatText(TeamScore team, int value) {
    return team.hasStats ? '$value' : '-';
  }

  Widget _tableCell(
    BuildContext context,
    String text,
    TextStyle style, {
    bool isHighlight = false,
    VoidCallback? onTap,
  }) {
    final child = Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      color: isHighlight ? AppColors.cardSub : null,
      child: Text(text, textAlign: TextAlign.center, style: style),
    );

    if (onTap == null) {
      return child;
    }

    return AppPressable(
      onTap: onTap,
      pressedScale: 0.97,
      pressedOpacity: 0.92,
      child: child,
    );
  }

  void _openInningSheet(
    BuildContext context,
    int inning,
    List<RelayItem> relayItems,
  ) {
    final items = relayItems
        .where((item) => item.inning == inning && item.event != 'INNING_CHANGE')
        .toList();

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.card,
      isScrollControlled: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$inning회 주요 장면',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                if (items.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      '이 회차에 기록된 이벤트가 없습니다.',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  )
                else
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: items.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final item = items[index];
                        return Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: item.isScoring
                                ? const Color(0xFF1C1111)
                                : AppColors.cardSub,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: item.isScoring
                                  ? AppColors.live
                                  : AppColors.divider,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${item.half == 'top' ? '초' : '말'} · ${item.text}',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: item.isScoring
                                      ? FontWeight.w700
                                      : FontWeight.w600,
                                ),
                              ),
                              if (item.pitchSequence != null &&
                                  item.pitchSequence!.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text(
                                  item.pitchSequence!,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
