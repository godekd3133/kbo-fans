import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models/boxscore.dart';
import '../../../data/providers.dart';

class LineupTab extends ConsumerStatefulWidget {
  final String gameId;
  final String awayName;
  final String homeName;

  const LineupTab({
    super.key,
    required this.gameId,
    this.awayName = 'Away',
    this.homeName = 'Home',
  });

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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minWidth: MediaQuery.of(context).size.width - 32,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _toggleButton(
                      widget.awayName,
                      _showAway,
                      () => setState(() => _showAway = true),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _toggleButton(
                      widget.homeName,
                      !_showAway,
                      () => setState(() => _showAway = false),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          lineupAsync.when(
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.all(40),
                child: CircularProgressIndicator(color: AppColors.live),
              ),
            ),
            error: (e, _) => Text(
              '라인업 로딩 실패: $e',
              style: const TextStyle(color: AppColors.textDisabled),
            ),
            data: (lineup) => _buildLineupContent(lineup),
          ),
        ],
      ),
    );
  }

  Widget _buildLineupContent(List<LineupEntry> lineup) {
    final starter = lineup
        .where((entry) => entry.position == 'P' || entry.positionKo.contains('투수'))
        .cast<LineupEntry?>()
        .firstWhere((entry) => entry != null, orElse: () => null);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (starter != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '선발투수',
                  style: TextStyle(fontSize: 12, color: AppColors.textDisabled),
                ),
                const SizedBox(height: 4),
                Text(
                  starter.name,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        const SizedBox(height: 16),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Container(
            constraints: const BoxConstraints(minWidth: 720),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Table(
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              columnWidths: const {
                0: FixedColumnWidth(88),
                1: FixedColumnWidth(140),
                2: FixedColumnWidth(220),
              },
              children: [
                const TableRow(
                  children: [
                    _LineupHeaderCell('타순'),
                    _LineupHeaderCell('포지션'),
                    _LineupHeaderCell('이름', align: TextAlign.left),
                  ],
                ),
                for (int i = 0; i < lineup.length; i++)
                  TableRow(
                    decoration: BoxDecoration(
                      color: i.isEven ? Colors.transparent : const Color(0xFF1A1A1A),
                    ),
                    children: [
                      _lineupCell('${lineup[i].order}', const TextStyle(fontSize: 16)),
                      _lineupCell(
                        lineup[i].positionKo,
                        const TextStyle(fontSize: 16, color: AppColors.textSecondary),
                      ),
                      _lineupCell(
                        lineup[i].name,
                        const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                        align: TextAlign.left,
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _toggleButton(String label, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? AppColors.textPrimary : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: active ? null : Border.all(color: AppColors.divider),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: active ? AppColors.background : AppColors.textDisabled,
          ),
        ),
      ),
    );
  }

  Widget _lineupCell(String text, TextStyle style, {TextAlign align = TextAlign.center}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
      child: Text(text, textAlign: align, style: style),
    );
  }
}

class _LineupHeaderCell extends StatelessWidget {
  final String text;
  final TextAlign align;

  const _LineupHeaderCell(this.text, {this.align = TextAlign.center});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
      child: Text(
        text,
        textAlign: align,
        style: const TextStyle(fontSize: 13, color: AppColors.textDisabled),
      ),
    );
  }
}
