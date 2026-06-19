import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kbo_fans/core/theme/app_theme.dart';
import 'package:kbo_fans/data/models/game.dart';
import 'package:kbo_fans/features/home/widgets/my_team_game_card.dart';

void main() {
  testWidgets('hides team total tiles when stats are unavailable', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: MyTeamGameCard(
            game: _game(
              away: const TeamScore(
                teamId: 'XX',
                teamName: '원정',
                shortName: '원정',
                score: 2,
                innings: [],
                hasStats: false,
              ),
              home: const TeamScore(
                teamId: 'YY',
                teamName: '홈',
                shortName: '홈',
                score: 1,
                innings: [],
                hasStats: false,
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('안타'), findsNothing);
    expect(find.text('실책'), findsNothing);
    expect(find.text('볼넷'), findsNothing);
    expect(find.text('중계 보기'), findsOneWidget);
  });

  testWidgets('shows team total tiles when stats are available', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: MyTeamGameCard(
            game: _game(
              away: const TeamScore(
                teamId: 'XX',
                teamName: '원정',
                shortName: '원정',
                score: 2,
                innings: [],
                hits: 7,
                errors: 1,
                walks: 3,
              ),
              home: const TeamScore(
                teamId: 'YY',
                teamName: '홈',
                shortName: '홈',
                score: 1,
                innings: [],
                hits: 5,
                errors: 0,
                walks: 2,
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('안타'), findsOneWidget);
    expect(find.text('7-5'), findsOneWidget);
    expect(find.text('실책'), findsOneWidget);
    expect(find.text('1-0'), findsOneWidget);
    expect(find.text('볼넷'), findsOneWidget);
    expect(find.text('3-2'), findsOneWidget);
  });

  testWidgets('opens relay when tapping the live card body', (tester) async {
    var detailTaps = 0;
    var relayTaps = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: MyTeamGameCard(
            game: _game(
              away: const TeamScore(
                teamId: 'XX',
                teamName: '원정',
                shortName: '원정',
                score: 2,
                innings: [],
              ),
              home: const TeamScore(
                teamId: 'YY',
                teamName: '홈',
                shortName: '홈',
                score: 1,
                innings: [],
              ),
            ),
            onOpenDetail: () => detailTaps++,
            onOpenRelay: () => relayTaps++,
          ),
        ),
      ),
    );

    await tester.tap(find.byType(MyTeamGameCard));
    await tester.pump();

    expect(relayTaps, 1);
    expect(detailTaps, 0);
  });

  testWidgets('marks live follow action when the game is already followed', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: MyTeamGameCard(
            game: _game(
              away: const TeamScore(
                teamId: 'XX',
                teamName: '원정',
                shortName: '원정',
                score: 2,
                innings: [],
              ),
              home: const TeamScore(
                teamId: 'YY',
                teamName: '홈',
                shortName: '홈',
                score: 1,
                innings: [],
              ),
            ),
            isFollowing: true,
          ),
        ),
      ),
    );

    expect(find.text('따라가는 중'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
    expect(find.text('따라가기'), findsNothing);
  });

  testWidgets('uses concise LIVE badge for live games', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: MyTeamGameCard(
            game: _game(
              away: const TeamScore(
                teamId: 'XX',
                teamName: '원정',
                shortName: '원정',
                score: 2,
                innings: [],
              ),
              home: const TeamScore(
                teamId: 'YY',
                teamName: '홈',
                shortName: '홈',
                score: 1,
                innings: [],
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('LIVE'), findsOneWidget);
    expect(find.text('LIVE 경기중'), findsNothing);
  });
}

Game _game({required TeamScore away, required TeamScore home}) {
  return Game(
    gameId: '20260520XXYY0',
    status: GameStatus.live,
    inning: '8회초',
    away: away,
    home: home,
    stadium: '잠실',
    startTime: '18:30',
  );
}
