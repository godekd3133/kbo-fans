class VisualAssets {
  static const onboardingHero = 'assets/visuals/casual_onboarding_01.webp';
  static const homeEmptyStadium = 'assets/visuals/casual_home_03.webp';
  static const scheduleTicketing = 'assets/visuals/casual_schedule_01.webp';
  static const liveRelayField = 'assets/visuals/casual_game_02.webp';
  static const recordsStats = 'assets/visuals/casual_records_01.webp';
  static const notificationPlaybook =
      'assets/visuals/casual_notifications_01.webp';
  static const standingsRace = 'assets/visuals/casual_standings_01.webp';
  static const gameDetailScoreboard = 'assets/visuals/casual_game_01.webp';
  static const myTeamBriefCommand = 'assets/visuals/casual_home_02.webp';
  static const boxscoreAnalytics = 'assets/visuals/casual_records_02.webp';
  static const lineupDugout = 'assets/visuals/casual_game_05.webp';
  static const lineupMatchup = 'assets/visuals/casual_game_04.webp';
  static const scoreLinescore = 'assets/visuals/casual_game_08.webp';
  static const dataRetry = 'assets/visuals/casual_onboarding_13.webp';
  static const scheduleEmptyCalendar = 'assets/visuals/casual_schedule_03.webp';

  static final casualHome = _sequence('casual_home', 25);
  static final casualGame = _sequence('casual_game', 25);
  static final casualSchedule = _sequence('casual_schedule', 25);
  static final casualStandings = _sequence('casual_standings', 25);
  static final casualRecords = _sequence('casual_records', 25);
  static final casualNotifications = _sequence('casual_notifications', 25);
  static final casualOnboarding = _sequence('casual_onboarding', 25);

  static final casualAll = List<String>.unmodifiable([
    ...casualHome,
    ...casualGame,
    ...casualSchedule,
    ...casualStandings,
    ...casualRecords,
    ...casualNotifications,
    ...casualOnboarding,
  ]);

  static List<String> _sequence(
    String prefix,
    int count,
  ) => List<String>.unmodifiable(
    List.generate(
      count,
      (index) =>
          'assets/visuals/${prefix}_${(index + 1).toString().padLeft(2, '0')}.webp',
    ),
  );
}
