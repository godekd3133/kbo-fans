import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kbo_fans/core/config/app_config.dart';
import 'package:kbo_fans/core/theme/app_theme.dart';
import 'package:kbo_fans/data/models/player.dart';
import 'package:kbo_fans/data/models/records_overview.dart';
import 'package:kbo_fans/data/models/team_records_bundle.dart';
import 'package:kbo_fans/data/models/team_stats.dart';
import 'package:kbo_fans/data/providers.dart';
import 'package:kbo_fans/features/records/player_detail_screen.dart';
import 'package:kbo_fans/features/records/records_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  AppConfig.initialize();

  testWidgets('기록실 선수 목록은 프로필 id 기반 이미지 URL로 보강한다', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final season = DateTime.now().year;
    final expectedImageUrl = kboPlayerImageUrl(
      season: season,
      playerId: '69102',
    );

    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          teamRecordsProvider.overrideWith((ref, key) async {
            return const TeamRecordsBundle(
              players: [_moonBatterWithoutImage],
              teamStats: TeamStats(
                teamId: 'LG',
                season: 2026,
                hitting: {},
                pitching: {},
              ),
            );
          }),
        ],
        child: MaterialApp(
          theme: AppTheme.dark,
          home: const RecordsScreen(teamId: 'LG'),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is CachedNetworkImage && widget.imageUrl == expectedImageUrl,
      ),
      findsOneWidget,
    );
  });

  testWidgets('선수 상세는 프로필 id 기반 이미지 URL로 보강한다', (tester) async {
    const season = 2026;
    final expectedImageUrl = kboPlayerImageUrl(
      season: season,
      playerId: '69102',
    );

    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          playerDetailProvider.overrideWith((ref, key) async {
            return _moonBatterWithoutImage;
          }),
        ],
        child: MaterialApp(
          theme: AppTheme.dark,
          home: const PlayerDetailScreen(playerId: '69102', season: season),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is CachedNetworkImage && widget.imageUrl == expectedImageUrl,
      ),
      findsOneWidget,
    );
  });
}

const _moonBatterWithoutImage = PlayerProfile(
  id: '69102',
  teamId: 'LG',
  playerType: PlayerType.hitter,
  name: '문보경',
  number: 2,
  position: '3B',
  roleLabel: '내야수',
  handedness: '우투좌타',
  heightWeight: '',
  birthDate: '',
  status: PlayerAvailabilityStatus.available,
  rosterGroup: PlayerRosterGroup.entry,
  headlineStat: 'AVG 0.300',
  secondaryStat: 'OPS 0.800',
  seasonStats: [],
  highlights: [],
  recentGames: [],
);
