import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models/game.dart';
import '../../data/mock/mock_games.dart';
import 'widgets/my_team_game_card.dart';
import 'widgets/game_card.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String? _myTeamId;
  final List<Game> _games = mockGames;

  @override
  void initState() {
    super.initState();
    _loadMyTeam();
  }

  Future<void> _loadMyTeam() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _myTeamId = prefs.getString('myTeam'));
  }

  Game? get _myTeamGame {
    if (_myTeamId == null) return null;
    try {
      return _games.firstWhere(
        (g) => g.away.teamId == _myTeamId || g.home.teamId == _myTeamId,
      );
    } catch (_) {
      return null;
    }
  }

  List<Game> get _otherGames {
    final myGame = _myTeamGame;
    if (myGame == null) return _games;
    return _games.where((g) => g.gameId != myGame.gameId).toList();
  }

  bool get _hasLiveGames => _games.any((g) => g.status == GameStatus.live);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            // TODO: API에서 데이터 새로고침
            await Future.delayed(const Duration(milliseconds: 500));
          },
          color: AppColors.live,
          child: CustomScrollView(
            slivers: [
              // 헤더
              SliverToBoxAdapter(child: _buildHeader()),
              // 마이팀 경기 카드
              if (_myTeamGame != null)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: MyTeamGameCard(
                      game: _myTeamGame!,
                      onTap: () => context.push('/game/${_myTeamGame!.gameId}'),
                    ),
                  ),
                ),
              // 나머지 경기 카드
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                sliver: SliverList.separated(
                  itemCount: _otherGames.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final game = _otherGames[index];
                    return GameCard(
                      game: game,
                      onTap: () => context.push('/game/${game.gameId}'),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('KBO Fans', style: Theme.of(context).textTheme.headlineMedium),
          Row(
            children: [
              Text('3.28 토', style: TextStyle(fontSize: 14, color: AppColors.textSecondary)),
              if (_hasLiveGames) ...[
                const SizedBox(width: 8),
                Container(width: 8, height: 8, decoration: const BoxDecoration(color: AppColors.live, shape: BoxShape.circle)),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
