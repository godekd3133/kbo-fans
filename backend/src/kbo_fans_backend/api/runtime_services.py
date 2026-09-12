from __future__ import annotations

from kbo_fans_backend.crawlers.main import MainCrawler
from kbo_fans_backend.crawlers.schedule import ScheduleCrawler
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
from kbo_fans_backend.utils.source_cache import KboSourceCache

_shared_main_crawler = MainCrawler()
_shared_schedule_crawler = ScheduleCrawler()
_shared_main_source = KboSourceCache(
    _shared_main_crawler.get_kbo_game_list,
    ttl_seconds=8,
)
_shared_schedule_source = KboSourceCache(
    _shared_schedule_crawler.get_month_schedule,
    ttl_seconds=8,
)
scoreboard_service = ScoreboardService(
    main_crawler=_shared_main_crawler,
    schedule_crawler=_shared_schedule_crawler,
    main_source=_shared_main_source,
    schedule_source=_shared_schedule_source,
)
schedule_service = ScheduleService(
    main_crawler=_shared_main_crawler,
    schedule_crawler=_shared_schedule_crawler,
    main_source=_shared_main_source,
    schedule_source=_shared_schedule_source,
)
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
    main_source=_shared_main_source,
)
relay_service = RelayService(scoreboard_service=scoreboard_service)

# Share the authenticated relay crawler with the boxscore live-context path
# and let lineup reuse the already-warmed boxscore instead of crawling it a
# second time during one live-game warm cycle.
if getattr(boxscore_service.crawler, "relay_crawler", None) is None:
    boxscore_service.crawler.relay_crawler = relay_service.relay_crawler
if hasattr(boxscore_service.crawler, "relay_service"):
    boxscore_service.crawler.relay_service = relay_service
lineup_service = LineupService(
    main_crawler=_shared_main_crawler,
    main_source=_shared_main_source,
    player_stats_service=player_stats_service,
    boxscore_service=boxscore_service,
)
