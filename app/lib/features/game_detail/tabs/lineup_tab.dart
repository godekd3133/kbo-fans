import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/mock/mock_game_detail.dart';

class LineupTab extends StatefulWidget {
  final String gameId;
  const LineupTab({super.key, required this.gameId});

  @override
  State<LineupTab> createState() => _LineupTabState();
}

class _LineupTabState extends State<LineupTab> {
  bool _showAway = true;

  @override
  Widget build(BuildContext context) {
    final lineup = mockAwayLineup; // TODO: away/home 전환

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // 팀 토글
          Row(
            children: [
              Expanded(child: _toggleButton('KT', _showAway, () => setState(() => _showAway = true))),
              const SizedBox(width: 8),
              Expanded(child: _toggleButton('LG', !_showAway, () => setState(() => _showAway = false))),
            ],
          ),
          const SizedBox(height: 16),
          // 선발 투수
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(12)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('선발투수', style: TextStyle(fontSize: 12, color: AppColors.textDisabled)),
                const SizedBox(height: 4),
                Text('사우어 (우투)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // 라인업 테이블
          Container(
            decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(12)),
            child: Table(
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              columnWidths: const {
                0: FixedColumnWidth(40),
                1: FlexColumnWidth(1),
                2: FlexColumnWidth(1.5),
              },
              children: [
                TableRow(
                  children: [
                    _cell('타순', const TextStyle(fontSize: 12, color: AppColors.textDisabled)),
                    _cell('포지션', const TextStyle(fontSize: 12, color: AppColors.textDisabled)),
                    _cell('이름', const TextStyle(fontSize: 12, color: AppColors.textDisabled), align: TextAlign.left),
                  ],
                ),
                for (int i = 0; i < lineup.length; i++)
                  TableRow(
                    decoration: BoxDecoration(
                      color: i.isEven ? Colors.transparent : const Color(0xFF1A1A1A),
                    ),
                    children: [
                      _cell('${lineup[i].order}', const TextStyle(fontSize: 14)),
                      _cell(lineup[i].positionKo, const TextStyle(fontSize: 14, color: AppColors.textSecondary)),
                      _cell(lineup[i].name, const TextStyle(fontSize: 14), align: TextAlign.left),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _toggleButton(String label, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? AppColors.textPrimary : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: active ? null : Border.all(color: AppColors.divider),
        ),
        child: Text(
          label,
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: active ? AppColors.background : AppColors.textDisabled),
        ),
      ),
    );
  }

  Widget _cell(String text, TextStyle style, {TextAlign align = TextAlign.center}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      child: Text(text, textAlign: align, style: style),
    );
  }
}
