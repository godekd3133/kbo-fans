import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/providers.dart';

class BoxscoreTab extends ConsumerStatefulWidget {
  final String gameId;
  final String awayName;
  final String homeName;
  const BoxscoreTab({super.key, required this.gameId, this.awayName = 'Away', this.homeName = 'Home'});

  @override
  ConsumerState<BoxscoreTab> createState() => _BoxscoreTabState();
}

class _BoxscoreTabState extends ConsumerState<BoxscoreTab> {
  bool _showAway = true;

  String get _batterKey => '${widget.gameId}|$_showAway';
  String get _pitcherKey => '${widget.gameId}|$_showAway';

  @override
  Widget build(BuildContext context) {
    final battersAsync = ref.watch(battersProvider(_batterKey));
    final pitchersAsync = ref.watch(pitchersProvider(_pitcherKey));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildTeamToggle(),
          const SizedBox(height: 16),
          battersAsync.when(
            loading: () => const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator(color: AppColors.live))),
            error: (e, _) => Text('타자 데이터 로딩 실패: $e', style: TextStyle(color: AppColors.textDisabled)),
            data: (batters) => _buildBatterTable(batters),
          ),
          const SizedBox(height: 24),
          pitchersAsync.when(
            loading: () => const SizedBox.shrink(),
            error: (e, _) => Text('투수 데이터 로딩 실패: $e', style: TextStyle(color: AppColors.textDisabled)),
            data: (pitchers) => _buildPitcherTable(pitchers),
          ),
        ],
      ),
    );
  }

  Widget _buildTeamToggle() {
    return Row(
      children: [
        Expanded(child: _toggleButton(widget.awayName, _showAway, () => setState(() => _showAway = true))),
        const SizedBox(width: 8),
        Expanded(child: _toggleButton(widget.homeName, !_showAway, () => setState(() => _showAway = false))),
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

  Widget _buildBatterTable(List batters) {
    const headers = ['타순', '포지션', '이름', '타수', '득점', '안타', '타점'];
    const hStyle = TextStyle(fontSize: 12, color: AppColors.textDisabled);
    const dStyle = TextStyle(fontSize: 14, color: AppColors.textPrimary);
    const bStyle = TextStyle(fontSize: 14, color: AppColors.textPrimary, fontWeight: FontWeight.w700);
    final totalAtBats = batters.fold<int>(0, (sum, batter) => sum + batter.atBats as int);
    final totalRuns = batters.fold<int>(0, (sum, batter) => sum + batter.runs as int);
    final totalHits = batters.fold<int>(0, (sum, batter) => sum + batter.hits as int);
    final totalRbi = batters.fold<int>(0, (sum, batter) => sum + batter.rbi as int);

    return Container(
      decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(padding: EdgeInsets.fromLTRB(16, 16, 16, 8), child: Text('타자', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600))),
          Table(
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            columnWidths: const {0: FixedColumnWidth(36), 1: FixedColumnWidth(40), 2: FlexColumnWidth(1.5)},
            children: [
              TableRow(children: headers.map((h) => _cell(h, hStyle)).toList()),
              for (int i = 0; i < batters.length; i++)
                TableRow(
                  decoration: BoxDecoration(color: i.isEven ? Colors.transparent : AppColors.card),
                  children: [
                    _cell('${batters[i].order}', dStyle),
                    _cell(batters[i].position, dStyle),
                    _cell(batters[i].name, dStyle, align: TextAlign.left),
                    _cell('${batters[i].atBats}', dStyle),
                    _cell('${batters[i].runs}', dStyle),
                    _cell('${batters[i].hits}', dStyle),
                    _cell('${batters[i].rbi}', dStyle),
                  ],
                ),
              TableRow(
                decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.divider))),
                children: [
                  _cell('', bStyle), _cell('', bStyle), _cell('합계', bStyle, align: TextAlign.left),
                  _cell('$totalAtBats', bStyle),
                  _cell('$totalRuns', bStyle),
                  _cell('$totalHits', bStyle),
                  _cell('$totalRbi', bStyle),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPitcherTable(List pitchers) {
    const headers = ['이름', '이닝', '안타', '삼진', '사사구', '자책', '판정'];
    const hStyle = TextStyle(fontSize: 12, color: AppColors.textDisabled);
    const dStyle = TextStyle(fontSize: 14, color: AppColors.textPrimary);

    return Container(
      decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(padding: EdgeInsets.fromLTRB(16, 16, 16, 8), child: Text('투수', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600))),
          Table(
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            columnWidths: const {0: FlexColumnWidth(1.5)},
            children: [
              TableRow(children: headers.map((h) => _cell(h, hStyle)).toList()),
              for (final p in pitchers)
                TableRow(children: [
                  _cell(p.name, dStyle, align: TextAlign.left),
                  _cell(p.innings, dStyle),
                  _cell('${p.hits}', dStyle),
                  _cell('${p.strikeouts}', dStyle),
                  _cell('${p.walks}', dStyle),
                  _cell('${p.earnedRuns}', dStyle),
                  p.decision != null
                      ? Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Center(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(color: AppColors.positive.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(4)),
                              child: Text(p.decision!, style: const TextStyle(fontSize: 12, color: AppColors.positive, fontWeight: FontWeight.w600)),
                            ),
                          ),
                        )
                      : _cell('', dStyle),
                ]),
            ],
          ),
        ],
      ),
    );
  }

  Widget _cell(String text, TextStyle style, {TextAlign align = TextAlign.center}) {
    return Padding(padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4), child: Text(text, textAlign: align, style: style));
  }
}
