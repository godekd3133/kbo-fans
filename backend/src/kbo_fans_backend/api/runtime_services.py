from __future__ import annotations

from kbo_fans_backend.services.boxscore import BoxscoreService
from kbo_fans_backend.services.home import HomeService
from kbo_fans_backend.services.lineup import LineupService
from kbo_fans_backend.services.player_stats import PlayerStatsService
from kbo_fans_backend.services.records_overview import RecordsOverviewService
from kbo_fans_backend.services.relay import RelayService
from kbo_fans_backend.services.schedule import ScheduleService
from kbo_fans_backend.services.scoreboard import ScoreboardService
from kbo_fans_backend.services.standings import StandingsService
from kbo_fans_backend.services.team_stats import TeamStatsService

scoreboard_service = ScoreboardService()
schedule_service = ScheduleService()
standings_service = StandingsService()
records_overview_service = RecordsOverviewService()
player_stats_service = PlayerStatsService()
team_stats_service = TeamStatsService()
home_service = HomeService(
    scoreboard_service=scoreboard_service,
    schedule_service=schedule_service,
    standings_service=standings_service,
    records_overview_service=records_overview_service,
)
boxscore_service = BoxscoreService(
    schedule_service=schedule_service,
    player_stats_service=player_stats_service,
)
lineup_service = LineupService(player_stats_service=player_stats_service)
relay_service = RelayService(scoreboard_service=scoreboard_service)
