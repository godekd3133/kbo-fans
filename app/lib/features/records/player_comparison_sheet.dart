import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/baseball_metric_guide.dart';
import '../../data/models/player.dart';

Future<void> showPlayerComparison(
  BuildContext context, {
  required List<PlayerProfile> players,
  required String teamId,
  required String teamName,
  required int season,
  required PlayerType playerType,
}) {
  // A sheet is a snapshot of the visible season/filter. Closing it discards
  // selections, so no selection can leak into a different season or group.
  final seen = <String>{};
  final candidates = players
      .where(
        (player) =>
            player.teamId == teamId &&
            player.playerType == playerType &&
            player.id.isNotEmpty &&
            seen.add(player.id),
      )
      .toList();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => PlayerComparisonSheet(
      players: candidates,
      teamName: teamName,
      season: season,
      playerType: playerType,
    ),
  );
}

class PlayerComparisonSheet extends StatefulWidget {
  final List<PlayerProfile> players;
  final String teamName;
  final int season;
  final PlayerType playerType;
  const PlayerComparisonSheet({
    super.key,
    required this.players,
    required this.teamName,
    required this.season,
    required this.playerType,
  });

  @override
  State<PlayerComparisonSheet> createState() => _PlayerComparisonSheetState();
}

class _PlayerComparisonSheetState extends State<PlayerComparisonSheet> {
  String? _firstId;
  String? _secondId;

  @override
  void initState() {
    super.initState();
    _firstId = widget.players.isEmpty ? null : widget.players.first.id;
    _secondId = widget.players.length < 2 ? null : widget.players[1].id;
  }

  PlayerProfile? _player(String? id) {
    for (final player in widget.players) {
      if (player.id == id) return player;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);
    final first = _player(_firstId);
    final second = _player(_secondId);
    final hitter = widget.playerType == PlayerType.hitter;
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.88,
      child: ListView(
        key: const ValueKey('player-comparison-sheet'),
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Expanded(
                child: Text(
                  '선수 나란히 비교',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
                ),
              ),
              IconButton(
                tooltip: '선수 비교 닫기',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${widget.season} · ${widget.teamName} · ${hitter ? '야수' : '투수'}',
            style: TextStyle(color: colors.textSecondary, fontSize: 14),
          ),
          const SizedBox(height: 16),
          _selector(firstSlot: true),
          const SizedBox(height: 12),
          _selector(firstSlot: false),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              key: const ValueKey('comparison-reset'),
              onPressed: () => setState(() {
                _firstId = null;
                _secondId = null;
              }),
              child: const Text('선택 초기화'),
            ),
          ),
          if (first != null && second != null) ...[
            Text(
              '시즌 기록',
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            if (hitter) ...[
              _metric('AVG', first.avg, second.avg, first, second, digits: 3),
              _metric('OPS', first.ops, second.ops, first, second, digits: 3),
            ] else ...[
              _metric(
                'ERA',
                first.era,
                second.era,
                first,
                second,
                digits: 2,
                lowerIsBetter: true,
              ),
              _metric(
                'WHIP',
                first.whip,
                second.whip,
                first,
                second,
                digits: 2,
                lowerIsBetter: true,
              ),
            ],
            for (final key in hitter ? const ['HR'] : const ['SO', 'W', 'SV'])
              if (_countingStat(first, key) case final left?)
                if (_countingStat(second, key) case final right?)
                  _metric(
                    key,
                    left.toDouble(),
                    right.toDouble(),
                    first,
                    second,
                    digits: 0,
                    cumulative: true,
                  ),
            const SizedBox(height: 12),
            Text(
              '출전 기회도 함께 보기',
              style: TextStyle(
                color: colors.accent,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            _sample(first),
            const SizedBox(height: 8),
            _sample(second),
            const SizedBox(height: 14),
            Text(
              '같은 시즌에 제공된 선수 기록을 비교합니다. 출전 기회가 다를 수 있으니 경기 수·타수·이닝도 함께 보세요. 수치 차이는 앱 계산값입니다.',
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: 12,
                height: 1.5,
              ),
            ),
          ] else
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                widget.players.length < 2
                    ? '현재 조건에서는 비교할 선수가 부족합니다. 필터를 넓혀 주세요.'
                    : '비교할 선수 두 명을 선택해 주세요.',
                style: TextStyle(color: colors.textSecondary, height: 1.5),
              ),
            ),
        ],
      ),
    );
  }

  Widget _selector({required bool firstSlot}) {
    final selectedId = firstSlot ? _firstId : _secondId;
    final otherId = firstSlot ? _secondId : _firstId;
    return DropdownButtonFormField<String>(
      key: ValueKey(
        'comparison-${firstSlot ? 'first' : 'second'}-$selectedId-$otherId',
      ),
      initialValue: selectedId,
      isExpanded: true,
      // Dense DropdownButton sizes from text/icon height (24px at normal size)
      // without accounting for menu-item padding. Use the actual item height
      // so Korean glyphs and accessibility scaling are not clipped.
      isDense: false,
      itemHeight: null,
      decoration: InputDecoration(
        labelText: firstSlot ? '첫 번째 선수' : '두 번째 선수',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      ),
      hint: const Text('선수 선택'),
      items: [
        for (final player in widget.players.where((p) => p.id != otherId))
          DropdownMenuItem(
            value: player.id,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(player.name, softWrap: true),
            ),
          ),
      ],
      onChanged: (id) => setState(() {
        if (firstSlot) {
          _firstId = id;
        } else {
          _secondId = id;
        }
      }),
    );
  }

  bool _valid(double? value) => value != null && value.isFinite && value >= 0;

  int? _countingStat(PlayerProfile player, String key) {
    final values = player.seasonStats
        .where(
          (value) => RegExp(
            '^$key(?:\\s|\$)',
            caseSensitive: false,
          ).hasMatch(value.trim()),
        )
        .toList();
    if (values.length != 1) return null;
    final match = RegExp(
      '^$key\\s+(\\d+)\$',
      caseSensitive: false,
    ).firstMatch(values.single.trim());
    return match == null ? null : int.tryParse(match.group(1)!);
  }

  Widget _metric(
    String metric,
    double? left,
    double? right,
    PlayerProfile first,
    PlayerProfile second, {
    required int digits,
    bool lowerIsBetter = false,
    bool cumulative = false,
  }) {
    final colors = AppTheme.colorsOf(context);
    final valid = _valid(left) && _valid(right);
    final gap = valid ? (left! - right!).abs() : null;
    final roundedGap = gap == null
        ? null
        : double.parse(gap.toStringAsFixed(digits));
    final guide = baseballMetricGuideFor(metric)!;
    return Container(
      key: ValueKey('comparison-metric-$metric'),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            guide.title,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final values = [
                _value(
                  first.name,
                  _valid(left) ? left!.toStringAsFixed(digits) : '–',
                ),
                _value(
                  second.name,
                  _valid(right) ? right!.toStringAsFixed(digits) : '–',
                ),
              ];
              if (MediaQuery.textScalerOf(context).scale(1) >= 1.6) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    values.first,
                    const SizedBox(height: 12),
                    values.last,
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: values.first),
                  const SizedBox(width: 12),
                  Expanded(child: values.last),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          Text(
            roundedGap == null
                ? '미제공 값이 있어 차이를 계산하지 않습니다'
                : roundedGap == 0
                ? '표시 정밀도에서 같은 값'
                : '차이 ${roundedGap.toStringAsFixed(digits)} · ${cumulative
                      ? '시즌 누적 기록'
                      : lowerIsBetter
                      ? '낮을수록 좋은 지표'
                      : '높을수록 좋은 지표'}',
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: 12,
              height: 1.4,
            ),
          ),
          BaseballMetricGuideButton(metric: metric, label: '이 지표 이해하기'),
        ],
      ),
    );
  }

  Widget _value(String name, String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(name, style: const TextStyle(fontSize: 13)),
      Text(
        value,
        style: const TextStyle(
          fontSize: 26,
          fontWeight: FontWeight.w800,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
      ),
    ],
  );

  Widget _sample(PlayerProfile player) {
    final samples = player.seasonStats
        .where(
          (stat) => RegExp(
            r'^(G|PA|AB|IP|경기|타석|타수|이닝)\s',
            caseSensitive: false,
          ).hasMatch(stat.trim()),
        )
        .toList();
    return Text(
      '${player.name} · ${samples.isEmpty ? '출전 표본 미제공' : samples.join(' · ')}',
      style: const TextStyle(fontSize: 13, height: 1.5),
    );
  }
}
