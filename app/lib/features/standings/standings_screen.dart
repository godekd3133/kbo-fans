import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/team_data.dart';
import '../../core/theme/app_theme.dart';

class StandingsScreen extends StatefulWidget {
  const StandingsScreen({super.key});

  @override
  State<StandingsScreen> createState() => _StandingsScreenState();
}

class _StandingsScreenState extends State<StandingsScreen> {
  String? _myTeamId;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((prefs) {
      setState(() => _myTeamId = prefs.getString('myTeam'));
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Text('📊 2026 정규시즌 순위', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(height: 12),
            // 헤더
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _buildHeaderRow(),
            ),
            const Divider(color: AppColors.divider, height: 1, indent: 16, endIndent: 16),
            // 순위 리스트
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _mockStandings.length,
                itemBuilder: (context, index) {
                  final s = _mockStandings[index];
                  final isMyTeam = s.teamId == _myTeamId;
                  final team = KboTeams.byId(s.teamId);

                  return Container(
                    height: 48,
                    decoration: BoxDecoration(
                      color: isMyTeam ? const Color(0xFF1C1111) : (index.isOdd ? AppColors.card : Colors.transparent),
                      border: isMyTeam ? const Border(left: BorderSide(color: Color(0xFFC60C30), width: 4)) : null,
                    ),
                    child: Row(
                      children: [
                        SizedBox(width: 32, child: Center(child: Text('${s.rank}', style: const TextStyle(fontSize: 14)))),
                        if (isMyTeam)
                          const Padding(padding: EdgeInsets.only(right: 4), child: Text('★', style: TextStyle(fontSize: 12, color: Color(0xFFC60C30)))),
                        CachedNetworkImage(
                          imageUrl: team?.logoUrl ?? '', width: 24, height: 24,
                          placeholder: (_, _) => const SizedBox(width: 24, height: 24),
                          errorWidget: (_, _, _) => Container(
                            width: 24, height: 24,
                            decoration: BoxDecoration(color: AppColors.cardSub, shape: BoxShape.circle),
                            child: Center(child: Text(team?.shortName ?? '', style: const TextStyle(fontSize: 8, color: AppColors.textSecondary))),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(child: Text(s.teamName, style: const TextStyle(fontSize: 14))),
                        SizedBox(width: 32, child: Center(child: Text('${s.wins}', style: const TextStyle(fontSize: 14)))),
                        SizedBox(width: 32, child: Center(child: Text('${s.losses}', style: const TextStyle(fontSize: 14)))),
                        SizedBox(width: 28, child: Center(child: Text('${s.draws}', style: const TextStyle(fontSize: 14)))),
                        SizedBox(width: 48, child: Center(child: Text(s.pct, style: const TextStyle(fontSize: 14)))),
                        SizedBox(width: 28, child: Center(child: Text(s.gb, style: const TextStyle(fontSize: 14, color: AppColors.textSecondary)))),
                      ],
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: Text('마지막 업데이트: 2026.03.28 16:30', style: TextStyle(fontSize: 12, color: AppColors.textDisabled)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderRow() {
    const style = TextStyle(fontSize: 12, color: AppColors.textDisabled);
    return SizedBox(
      height: 36,
      child: Row(
        children: [
          const SizedBox(width: 32, child: Center(child: Text('순위', style: style))),
          const Expanded(child: Padding(padding: EdgeInsets.only(left: 36), child: Text('팀', style: style))),
          const SizedBox(width: 32, child: Center(child: Text('승', style: style))),
          const SizedBox(width: 32, child: Center(child: Text('패', style: style))),
          const SizedBox(width: 28, child: Center(child: Text('무', style: style))),
          const SizedBox(width: 48, child: Center(child: Text('승률', style: style))),
          const SizedBox(width: 28, child: Center(child: Text('차', style: style))),
        ],
      ),
    );
  }
}

class _Standing {
  final int rank;
  final String teamId, teamName, pct, gb;
  final int wins, losses, draws;
  const _Standing(this.rank, this.teamId, this.teamName, this.wins, this.losses, this.draws, this.pct, this.gb);
}

const _mockStandings = <_Standing>[
  _Standing(1, 'LG', 'LG 트윈스', 1, 0, 0, '1.000', '-'),
  _Standing(2, 'HT', 'KIA 타이거즈', 1, 0, 0, '1.000', '-'),
  _Standing(3, 'NC', 'NC 다이노스', 1, 0, 0, '1.000', '-'),
  _Standing(4, 'HH', '한화 이글스', 1, 0, 0, '1.000', '-'),
  _Standing(5, 'LT', '롯데 자이언츠', 1, 0, 0, '1.000', '-'),
  _Standing(6, 'KT', 'KT 위즈', 0, 1, 0, '.000', '1'),
  _Standing(7, 'SK', 'SSG 랜더스', 0, 1, 0, '.000', '1'),
  _Standing(8, 'SS', '삼성 라이온즈', 0, 1, 0, '.000', '1'),
  _Standing(9, 'OB', '두산 베어스', 0, 1, 0, '.000', '1'),
  _Standing(10, 'WO', '키움 히어로즈', 0, 1, 0, '.000', '1'),
];
