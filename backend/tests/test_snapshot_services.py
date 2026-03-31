from kbo_fans_backend.services.player_stats import PlayerStatsService
from kbo_fans_backend.services.records_overview import RecordsOverviewService
from kbo_fans_backend.services.scoreboard import ScoreboardService
from kbo_fans_backend.services.standings import StandingsService
from kbo_fans_backend.storage import JsonSnapshotStore


class _FailingScheduleCrawler:
    def get_games_by_date(self, date: str):
        raise RuntimeError("schedule unavailable")


class _FailingMainCrawler:
    def get_kbo_game_list(self, date: str):
        raise RuntimeError("main unavailable")


class _FailingScoreboardCrawler:
    def get_game_scoreboard(self, game_id: str):
        raise RuntimeError("scoreboard unavailable")


class _FailingStandingsCrawler:
    def get_standings(self, season: int):
        raise RuntimeError("standings unavailable")


class _FailingPlayerCrawler:
    def get_team_players(self, team_id: str, season: int):
        raise RuntimeError("players unavailable")

    def get_player_detail(self, player_id: str, player_type, season: int, include_recent: bool):
        raise RuntimeError("player unavailable")


class _FailingRecordsOverviewCrawler:
    def get_overview(self, season: int):
        raise RuntimeError("overview unavailable")


def test_scoreboard_uses_historical_snapshot_before_crawling(tmp_path) -> None:
    store = JsonSnapshotStore(base_dir=str(tmp_path))
    expected = {
        "date": "2026-03-28",
        "games": [{"gameId": "20260328KTLG0", "status": "FINAL"}],
    }
    store.save("scoreboard", "2026-03-28", expected)
    store.save("games", "20260328KTLG0", expected["games"][0])

    service = ScoreboardService(
        main_crawler=_FailingMainCrawler(),
        schedule_crawler=_FailingScheduleCrawler(),
        scoreboard_crawler=_FailingScoreboardCrawler(),
        snapshot_store=store,
    )

    assert service.get_scoreboard("2026-03-28") == expected
    assert service.get_game("20260328KTLG0") == expected["games"][0]


def test_standings_falls_back_to_snapshot(tmp_path) -> None:
    store = JsonSnapshotStore(base_dir=str(tmp_path))
    expected = {
        "season": 2026,
        "standings": [{"rank": 1, "teamId": "LG", "teamName": "LG 트윈스"}],
        "updatedAt": "2026-03-31T16:30:00+09:00",
    }
    store.save("standings_latest", "2026", expected)

    service = StandingsService(
        crawler=_FailingStandingsCrawler(),
        snapshot_store=store,
    )

    assert service.get_standings(2026) == expected


def test_player_detail_falls_back_to_snapshot(tmp_path) -> None:
    store = JsonSnapshotStore(base_dir=str(tmp_path))
    expected = {
        "id": "61102",
        "teamId": "LG",
        "playerType": "hitter",
        "name": "홍길동",
        "recentGames": [],
    }
    store.save("player_detail", "61102-2026-auto", expected)

    service = PlayerStatsService(
        crawler=_FailingPlayerCrawler(),
        snapshot_store=store,
    )

    assert service.get_player_detail("61102", season=2026) == expected


def test_records_overview_falls_back_to_snapshot(tmp_path) -> None:
    store = JsonSnapshotStore(base_dir=str(tmp_path))
    expected = {
        "season": 2026,
        "leaders": {"avg": [], "hr": [], "ops": [], "era": []},
        "featured": {
            "todayHitter": {"label": "오늘의 타자"},
            "todayPitcher": {"label": "오늘의 투수"},
            "monthHitter": {"label": "이달의 타자"},
            "monthPitcher": {"label": "이달의 투수"},
        },
    }
    store.save("records_overview", "2026", expected)

    service = RecordsOverviewService(
        crawler=_FailingRecordsOverviewCrawler(),
        snapshot_store=store,
    )

    assert service.get_overview(2026) == expected
