import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kbo_fans/core/utils/kbo_time.dart';
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

    final season = kboCurrentSeason();
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

  testWidgets('선수 상세 주요 기록은 지표명을 분리하고 빈 값을 숨긴다', (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          retry: (_, _) => null,
          overrides: [
            playerDetailProvider.overrideWith((ref, key) async {
              return _moonBatterWithMetrics;
            }),
          ],
          child: MaterialApp(
            theme: AppTheme.dark,
            home: const PlayerDetailScreen(playerId: '69102', season: 2026),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.scrollUntilVisible(
        find.text('시즌 기록'),
        160,
        scrollable: find.descendant(
          of: find.byKey(const ValueKey('player-detail-data-69102')),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('주요 기록'), findsOneWidget);
      expect(find.text('헤드라인'), findsNothing);
      expect(find.text('현재 상태'), findsNothing);
      expect(find.text('시즌'), findsNothing);
      expect(find.text('타율'), findsOneWidget);
      expect(find.text('0.321'), findsOneWidget);
      expect(find.text('보조 지표'), findsOneWidget);
      expect(find.text('최근 10경기 상승세'), findsOneWidget);
      expect(find.text('시즌 기록'), findsOneWidget);
      expect(find.text('경기'), findsOneWidget);
      expect(find.text('120'), findsOneWidget);
      expect(find.text('홈런'), findsOneWidget);
      expect(find.text('25'), findsOneWidget);
      expect(find.text('타점'), findsOneWidget);
      expect(find.text('88'), findsOneWidget);
      expect(find.text('ERA -'), findsNothing);

      final primaryMetric = find.byKey(
        const ValueKey('player-primary-metric-0'),
      );
      expect(
        tester.getSemantics(primaryMetric).getSemanticsData().label,
        '타율, 0.321',
      );
      expect(
        find.bySemanticsLabel('타율, 0.321'),
        findsOneWidget,
        reason: '주요 기록과 시즌 기록의 같은 지표·값을 반복하지 않아야 한다.',
      );
      expect(
        find.bySemanticsLabel('홈런, 25'),
        findsOneWidget,
        reason: '보조 주요 기록과 시즌 기록의 같은 지표·값을 반복하지 않아야 한다.',
      );

      final firstSeasonMetric = find.byKey(
        const ValueKey('player-season-metric-0'),
      );
      final secondSeasonMetric = find.byKey(
        const ValueKey('player-season-metric-1'),
      );
      expect(
        tester.getTopLeft(firstSeasonMetric).dy,
        closeTo(tester.getTopLeft(secondSeasonMetric).dy, 0.1),
      );
      expect(
        tester.getTopLeft(secondSeasonMetric).dx,
        greaterThan(tester.getTopLeft(firstSeasonMetric).dx),
      );

      await tester.scrollUntilVisible(
        find.text('노트'),
        160,
        scrollable: find.descendant(
          of: find.byKey(const ValueKey('player-detail-data-69102')),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('최근 5경기'), findsOneWidget);
      expect(find.text('06.28'), findsOneWidget);
      expect(find.text('노트'), findsOneWidget);
      expect(find.text('최근 타격감이 좋습니다'), findsOneWidget);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('선수 상세 주요 기록은 320px 큰 글자에서 한 열로 흐른다', (tester) async {
    tester.view.physicalSize = const Size(320, 844);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          playerDetailProvider.overrideWith((ref, key) async {
            return _moonBatterWithMetrics;
          }),
        ],
        child: MaterialApp(
          theme: AppTheme.dark,
          home: const PlayerDetailScreen(playerId: '69102', season: 2026),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('player-season-metric-1')),
      180,
      scrollable: find.descendant(
        of: find.byKey(const ValueKey('player-detail-data-69102')),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.pumpAndSettle();

    final firstSeasonMetric = find.byKey(
      const ValueKey('player-season-metric-0'),
    );
    final secondSeasonMetric = find.byKey(
      const ValueKey('player-season-metric-1'),
    );
    expect(
      tester.getTopLeft(secondSeasonMetric).dx,
      closeTo(tester.getTopLeft(firstSeasonMetric).dx, 0.1),
    );
    expect(
      tester.getTopLeft(secondSeasonMetric).dy,
      greaterThan(tester.getTopLeft(firstSeasonMetric).dy),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('선수 상세는 최근 5경기 기록을 최신순으로 보여준다', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          playerDetailProvider.overrideWith((ref, key) async {
            return _moonBatterWithRecentGames;
          }),
        ],
        child: MaterialApp(
          theme: AppTheme.dark,
          home: const PlayerDetailScreen(playerId: '69102', season: 2026),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.scrollUntilVisible(
      find.text('최근 5경기'),
      180,
      scrollable: find.descendant(
        of: find.byKey(const ValueKey('player-detail-data-69102')),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('최근 5경기'), findsOneWidget);
    expect(find.text('06.28'), findsOneWidget);
    expect(find.text('vs 두산'), findsAtLeastNWidgets(1));
    expect(find.text('AVG 0.500 · H 2 · HR 1 · RBI 1'), findsOneWidget);
    expect(find.text('06.24'), findsOneWidget);
    expect(find.text('06.23'), findsNothing);
  });

  testWidgets('시즌 리더 요약은 타자와 투수 대표를 함께 보여준다', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          recordsOverviewProvider.overrideWith((ref, season) async {
            return _overviewWithTodayPair;
          }),
        ],
        child: MaterialApp(theme: AppTheme.dark, home: const RecordsScreen()),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('시즌 리더 요약'), findsOneWidget);
    expect(find.text('오늘의 타자'), findsOneWidget);
    expect(find.text('김도영'), findsOneWidget);
    expect(find.text('오늘의 투수'), findsOneWidget);
    expect(find.text('폰세'), findsOneWidget);
  });

  testWidgets('기록실 첫 화면은 투수 리더를 별도 마운드 체크로 보여준다', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          recordsOverviewProvider.overrideWith((ref, season) async {
            return _overviewWithLeaders;
          }),
        ],
        child: MaterialApp(theme: AppTheme.dark, home: const RecordsScreen()),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      find.descendant(
        of: find.byKey(const ValueKey('records-metric-avg')),
        matching: find.text('타율 AVG'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('records-metric-hr')),
        matching: find.text('홈런 HR'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('records-metric-ops')),
        matching: find.text('출루·장타 OPS'),
      ),
      findsOneWidget,
    );

    final panel = find.byKey(const ValueKey('records-pitching-leader-panel'));
    expect(panel, findsOneWidget);
    expect(
      find.descendant(of: panel, matching: find.text('마운드 체크')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: panel, matching: find.text('평균자책 ERA')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: panel, matching: find.text('다승 W')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: panel, matching: find.text('세이브 SV')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: panel, matching: find.text('탈삼진 SO')),
      findsOneWidget,
    );
    expect(find.textContaining('wRC+'), findsNothing);
    expect(find.text('폰세'), findsWidgets);
  });

  testWidgets('시즌 리더 요약은 중복 수치 상자 없이 타자와 투수를 보여준다', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          recordsOverviewProvider.overrideWith((ref, season) async {
            return _overviewWithLeaders;
          }),
        ],
        child: MaterialApp(theme: AppTheme.dark, home: const RecordsScreen()),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('활성 지표'), findsNothing);
    expect(find.text('TOP5 선수'), findsNothing);
    expect(find.text('소스'), findsNothing);
    expect(find.text('공식+계산'), findsNothing);
    final summary = find.byKey(const ValueKey('records-briefing-panel'));
    expect(
      find.descendant(of: summary, matching: find.text('오늘의 타자')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: summary, matching: find.text('오스틴')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: summary, matching: find.text('오늘의 투수')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: summary, matching: find.text('폰세')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: summary, matching: find.text('타율 1위')),
      findsNothing,
    );
    expect(
      find.descendant(of: summary, matching: find.text('홈런 1위')),
      findsNothing,
    );
  });

  testWidgets('라이트 모드 기록실은 밝은 카드 표면과 읽히는 텍스트를 유지한다', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(() => AppColors.sync(AppTheme.darkColors));

    AppColors.sync(AppTheme.darkColors);

    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          recordsOverviewProvider.overrideWith((ref, season) async {
            return _overviewWithLeaders;
          }),
        ],
        child: MaterialApp(theme: AppTheme.light, home: const RecordsScreen()),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(AppColors.background, AppTheme.lightColors.background);
    expect(AppColors.card, AppTheme.lightColors.card);
    expect(AppColors.textPrimary, AppTheme.lightColors.textPrimary);

    final briefingCard = tester.widget<Container>(
      find.byKey(const ValueKey('records-briefing-panel')),
    );
    final briefingDecoration = briefingCard.decoration as BoxDecoration;
    final briefingGradient = briefingDecoration.gradient as LinearGradient;
    expect(briefingGradient.colors.first, AppTheme.lightColors.card);

    final titleContext = tester.element(find.text('시즌 리더 요약'));
    expect(
      DefaultTextStyle.of(titleContext).style.color,
      AppTheme.lightColors.textPrimary,
    );

    final hubFinder = find.byKey(const ValueKey('records-leaderboard-hub'));
    await tester.ensureVisible(hubFinder);
    await tester.pumpAndSettle();

    final leaderboardHub = tester.widget<Container>(hubFinder);
    final hubDecoration = leaderboardHub.decoration as BoxDecoration;
    expect(hubDecoration.color, AppTheme.lightColors.card);

    final leaderNameContext = tester.element(
      find.descendant(of: hubFinder, matching: find.text('최원준')),
    );
    expect(
      DefaultTextStyle.of(leaderNameContext).style.color,
      AppTheme.lightColors.textPrimary,
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

const _moonBatterWithRecentGames = PlayerProfile(
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
  seasonStats: ['AVG 0.300', 'OPS 0.800'],
  highlights: [],
  recentGames: [
    PlayerRecentGame(
      date: '06.28',
      opponent: '두산',
      summary: 'AVG 0.500 · H 2 · HR 1 · RBI 1',
    ),
    PlayerRecentGame(
      date: '06.27',
      opponent: '두산',
      summary: 'AVG 0.000 · H 0 · HR 0 · RBI 0',
    ),
    PlayerRecentGame(
      date: '06.26',
      opponent: 'KT',
      summary: 'AVG 0.250 · H 1 · HR 0 · RBI 0',
    ),
    PlayerRecentGame(
      date: '06.25',
      opponent: '키움',
      summary: 'AVG 0.750 · H 3 · HR 2 · RBI 4',
    ),
    PlayerRecentGame(
      date: '06.24',
      opponent: '키움',
      summary: 'AVG 0.400 · H 2 · HR 0 · RBI 3',
    ),
    PlayerRecentGame(
      date: '06.23',
      opponent: 'NC',
      summary: 'AVG 0.200 · H 1 · HR 0 · RBI 0',
    ),
  ],
);

const _moonBatterWithMetrics = PlayerProfile(
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
  headlineStat: 'AVG 0.321',
  secondaryStat: '최근 10경기 상승세',
  seasonStats: ['AVG 0.321', 'G 120', 'HR 25', 'RBI 88', '', 'ERA -'],
  highlights: ['최근 타격감이 좋습니다'],
  recentGames: [
    PlayerRecentGame(
      date: '06.28',
      opponent: '두산',
      summary: 'AVG 0.500 · H 2 · HR 1 · RBI 1',
    ),
  ],
);

const _overviewWithTodayPair = RecordsOverview(
  season: 2026,
  avgLeaders: [],
  hrLeaders: [],
  opsLeaders: [],
  opsPlusLeaders: [],
  eraLeaders: [],
  todayHitter: FeaturedPlayerCard(
    label: '오늘의 타자',
    playerId: '52605',
    playerType: 'hitter',
    name: '김도영',
    teamId: 'HT',
    headline: '타격감 확인',
    summary: '최근 경기에서 장타와 출루가 모두 살아났습니다.',
  ),
  todayPitcher: FeaturedPlayerCard(
    label: '오늘의 투수',
    playerId: '65764',
    playerType: 'pitcher',
    name: '폰세',
    teamId: 'HH',
    headline: '마운드 체크',
    summary: 'ERA 리더 흐름을 유지하는 선발 카드입니다.',
  ),
  monthHitter: FeaturedPlayerCard(label: '이달의 타자'),
  monthPitcher: FeaturedPlayerCard(label: '이달의 투수'),
);

const _overviewWithLeaders = RecordsOverview(
  season: 2026,
  avgLeaders: [
    RecordLeader(
      rank: 1,
      playerId: '52605',
      playerType: 'hitter',
      name: '최원준',
      teamId: 'KT',
      value: '0.365',
    ),
    RecordLeader(
      rank: 2,
      playerId: '79192',
      playerType: 'hitter',
      name: '오스틴',
      teamId: 'LG',
      value: '0.354',
    ),
  ],
  hrLeaders: [
    RecordLeader(
      rank: 1,
      playerId: '79192',
      playerType: 'hitter',
      name: '오스틴',
      teamId: 'LG',
      value: '24',
    ),
  ],
  opsLeaders: [
    RecordLeader(
      rank: 1,
      playerId: '79192',
      playerType: 'hitter',
      name: '오스틴',
      teamId: 'LG',
      value: '1.100',
    ),
  ],
  opsPlusLeaders: [
    RecordLeader(
      rank: 1,
      playerId: '79192',
      playerType: 'hitter',
      name: '오스틴',
      teamId: 'LG',
      value: '126',
    ),
  ],
  eraLeaders: [
    RecordLeader(
      rank: 1,
      playerId: '65764',
      playerType: 'pitcher',
      name: '폰세',
      teamId: 'HH',
      value: '2.51',
    ),
  ],
  winLeaders: [
    RecordLeader(
      rank: 1,
      playerId: '65764',
      playerType: 'pitcher',
      metricKey: 'W',
      name: '폰세',
      teamId: 'HH',
      value: '9',
    ),
  ],
  saveLeaders: [
    RecordLeader(
      rank: 1,
      playerId: '65062',
      playerType: 'pitcher',
      metricKey: 'SV',
      name: '김재윤',
      teamId: 'SS',
      value: '20',
    ),
  ],
  strikeoutLeaders: [
    RecordLeader(
      rank: 1,
      playerId: '55633',
      playerType: 'pitcher',
      metricKey: 'SO',
      name: '올러',
      teamId: 'HT',
      value: '108',
    ),
  ],
  todayHitter: FeaturedPlayerCard(
    label: '오늘의 타자',
    playerId: '79192',
    playerType: 'hitter',
    name: '오스틴',
    teamId: 'LG',
    headline: '홈런(HR)·출루/장타(OPS)·OPS 상대지수 선두',
    summary: '주요 타격 지표를 동시에 끌고 갑니다.',
  ),
  todayPitcher: FeaturedPlayerCard(
    label: '오늘의 투수',
    playerId: '65764',
    playerType: 'pitcher',
    name: '폰세',
    teamId: 'HH',
    headline: '마운드 체크',
    summary: '실점 억제 흐름을 확인합니다.',
  ),
  monthHitter: FeaturedPlayerCard(label: '이달의 타자'),
  monthPitcher: FeaturedPlayerCard(label: '이달의 투수'),
);
