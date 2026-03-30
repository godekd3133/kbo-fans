import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/game.dart';

class ScoreTab extends StatelessWidget {
  final Game game;
  const ScoreTab({super.key, required this.game});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: _buildInningTable(),
    );
  }

  Widget _buildInningTable() {
    final headers = ['TEAM', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'R', 'H', 'E', 'B'];
    const headerStyle = TextStyle(fontSize: 12, color: AppColors.textDisabled, fontWeight: FontWeight.w500);
    const dataStyle = TextStyle(fontSize: 14, color: AppColors.textPrimary);
    const boldStyle = TextStyle(fontSize: 14, color: AppColors.textPrimary, fontWeight: FontWeight.w700);

    // 현재 이닝 인덱스 파싱 (예: "4회초" → 4)
    final currentInning = int.tryParse(game.inning.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Table(
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        columnWidths: const {
          0: FixedColumnWidth(48),
        },
        children: [
          // 헤더
          TableRow(
            children: headers.map((h) {
              final idx = headers.indexOf(h);
              final isCurrentInning = idx >= 1 && idx <= 9 && idx == currentInning;
              return _tableCell(h, headerStyle, isHighlight: isCurrentInning);
            }).toList(),
          ),
          // 구분선
          TableRow(
            children: List.generate(14, (_) => const Divider(height: 1, color: AppColors.divider)),
          ),
          // 어웨이
          _scoreRow(game.away, headers, currentInning, dataStyle, boldStyle),
          // 구분선
          TableRow(
            children: List.generate(14, (_) => const Divider(height: 1, color: AppColors.divider)),
          ),
          // 홈
          _scoreRow(game.home, headers, currentInning, dataStyle, boldStyle),
        ],
      ),
    );
  }

  TableRow _scoreRow(TeamScore team, List<String> headers, int currentInning, TextStyle dataStyle, TextStyle boldStyle) {
    return TableRow(
      children: [
        _tableCell(team.shortName, dataStyle),
        for (int i = 0; i < 9; i++)
          _tableCell(
            i < team.innings.length && team.innings[i] != null ? '${team.innings[i]}' : '-',
            dataStyle,
            isHighlight: (i + 1) == currentInning,
          ),
        _tableCell('${team.score}', boldStyle),
        _tableCell('${team.hits}', boldStyle),
        _tableCell('${team.errors}', boldStyle),
        _tableCell('${team.walks}', boldStyle),
      ],
    );
  }

  Widget _tableCell(String text, TextStyle style, {bool isHighlight = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      color: isHighlight ? AppColors.cardSub : null,
      child: Text(text, textAlign: TextAlign.center, style: style),
    );
  }
}
