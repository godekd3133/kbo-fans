import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/providers.dart';

class LineupTab extends ConsumerStatefulWidget {
  final String gameId;
  final String awayName;
  final String homeName;
  const LineupTab({super.key, required this.gameId, this.awayName = 'Away', this.homeName = 'Home'});

  @override
  ConsumerState<LineupTab> createState() => _LineupTabState();
}

class _LineupTabState extends ConsumerState<LineupTab> {
  bool _showAway = true;

  String get _lineupKey => '${widget.gameId}|$_showAway';

  @override
  Widget build(BuildContext context) {
    final lineupAsync = ref.watch(lineupProvider(_lineupKey));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: _toggleButton(widget.awayName, _showAway, () => setState(() => _showAway = true))),
              const SizedBox(width: 8),
              Expanded(child: _toggleButton(widget.homeName, !_showAway, () => setState(() => _showAway = false))),
            ],
          ),
          const SizedBox(height: 16),
          lineupAsync.when(
            loading: () => const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator(color: AppColors.live))),
            error: (e, _) => Text('라인업 로딩 실패: $e', style: TextStyle(color: AppColors.textDisabled)),
            data: (lineup) => _buildLineupContent(lineup),
          ),
        ],
      ),
    );
  }

  Widget _buildLineupContent(List lineup) {
    // 선발 투수 (타순 9번에서 포지션이 투수인 선수)
    final starter = lineup.isNotEmpty ? lineup.where((l) => l.position == 'P' || l.positionKo.contains('투수')).firstOrNull : null;

    return Column(
      children: [
        if (starter != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(12)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('선발투수', style: TextStyle(fontSize: 12, color: AppColors.textDisabled)),
                const SizedBox(height: 4),
                Text(starter.name, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        const SizedBox(height: 16),
        Container(
          decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(12)),
          child: Table(
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            columnWidths: const {0: FixedColumnWidth(40), 1: FlexColumnWidth(1), 2: FlexColumnWidth(1.5)},
            children: [
              TableRow(children: [
                _cell('타순', const TextStyle(fontSize: 12, color: AppColors.textDisabled)),
                _cell('포지션', const TextStyle(fontSize: 12, color: AppColors.textDisabled)),
                _cell('이름', const TextStyle(fontSize: 12, color: AppColors.textDisabled), align: TextAlign.left),
              ]),
              for (int i = 0; i < lineup.length; i++)
                TableRow(
                  decoration: BoxDecoration(color: i.isEven ? Colors.transparent : const Color(0xFF1A1A1A)),
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
        child: Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: active ? AppColors.background : AppColors.textDisabled)),
      ),
    );
  }

  Widget _cell(String text, TextStyle style, {TextAlign align = TextAlign.center}) {
    return Padding(padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8), child: Text(text, textAlign: align, style: style));
  }
}
