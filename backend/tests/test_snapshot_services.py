import json

import pytest

from kbo_fans_backend.services.player_stats import PlayerStatsService
from kbo_fans_backend.services.records_overview import RecordsOverviewService
from kbo_fans_backend.services.scoreboard import ScoreboardService
from kbo_fans_backend.services.standings import StandingsService
from kbo_fans_backend.services.team_stats import TeamStatsService
from kbo_fans_backend.storage import JsonSnapshotStore
from kbo_fans_backend.utils.kbo_time import current_kbo_year


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


class _FreshStandingsCrawler:
    def __init__(self) -> None:
        self.calls = 0

    def get_standings(self, season: int):
        self.calls += 1
        return {
            "season": season,
            "sourceSeason": season,
            "sourceDate": f"{season}-04-01",
            "standings": [{"rank": 1, "teamId": "KT", "teamName": "KT 위즈"}],
            "updatedAt": f"{season}-04-01T16:30:00+09:00",
        }


class _PayloadStandingsCrawler:
    def __init__(self, payload) -> None:
        self.payload = payload
        self.calls = 0

    def get_standings(self, season: int):
        self.calls += 1
        return self.payload


class _FailingPlayerCrawler:
    def get_team_players(self, team_id: str, season: int):
        raise RuntimeError("players unavailable")

    def get_player_detail(self, player_id: str, player_type, season: int, include_recent: bool):
        raise RuntimeError("player unavailable")


class _FreshPlayerCrawler:
    def get_team_players(self, team_id: str, season: int):
        return [{"id": "67893", "name": "박성한", "position": "내야수"}]

    def get_player_detail(self, player_id: str, player_type, season: int, include_recent: bool):
        raise RuntimeError("player unavailable")


class _FailingTeamStatsCrawler:
    def get_team_stats(self, team_id: str, season: int):
        raise RuntimeError("team stats unavailable")


class _FreshTeamStatsCrawler:
    def get_team_stats(self, team_id: str, season: int):
        return {
            "teamId": team_id,
            "season": season,
            "hitting": {"AVG": "0.279"},
            "pitching": {"ERA": "3.88"},
        }


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


def test_historical_scoreboard_rejects_snapshot_game_from_another_date(tmp_path) -> None:
    store = JsonSnapshotStore(base_dir=str(tmp_path))
    requested_date = "2025-01-01"
    store.save(
        "scoreboard",
        requested_date,
        {
            "date": requested_date,
            "games": [{"gameId": "20240101KTLG0", "status": "FINAL"}],
        },
    )

    service = ScoreboardService(
        main_crawler=_FailingMainCrawler(),
        schedule_crawler=_FailingScheduleCrawler(),
        scoreboard_crawler=_FailingScoreboardCrawler(),
        snapshot_store=store,
    )

    with pytest.raises(RuntimeError, match="schedule unavailable"):
        service.get_scoreboard(requested_date)


def test_historical_scoreboard_rejects_snapshot_game_without_identity(tmp_path) -> None:
    store = JsonSnapshotStore(base_dir=str(tmp_path))
    requested_date = "2025-01-01"
    store.save(
        "scoreboard",
        requested_date,
        {
            "date": requested_date,
            "games": [{"status": "FINAL"}],
        },
    )

    service = ScoreboardService(
        main_crawler=_FailingMainCrawler(),
        schedule_crawler=_FailingScheduleCrawler(),
        scoreboard_crawler=_FailingScoreboardCrawler(),
        snapshot_store=store,
    )

    with pytest.raises(RuntimeError, match="schedule unavailable"):
        service.get_scoreboard(requested_date)


def test_historical_scoreboard_rejects_snapshot_game_with_malformed_id(tmp_path) -> None:
    store = JsonSnapshotStore(base_dir=str(tmp_path))
    requested_date = "2025-01-01"
    store.save(
        "scoreboard",
        requested_date,
        {
            "date": requested_date,
            "games": [{"gameId": "20250101", "status": "FINAL"}],
        },
    )

    service = ScoreboardService(
        main_crawler=_FailingMainCrawler(),
        schedule_crawler=_FailingScheduleCrawler(),
        scoreboard_crawler=_FailingScoreboardCrawler(),
        snapshot_store=store,
    )

    with pytest.raises(RuntimeError, match="schedule unavailable"):
        service.get_scoreboard(requested_date)


def test_historical_standings_falls_back_to_snapshot(tmp_path) -> None:
    store = JsonSnapshotStore(base_dir=str(tmp_path))
    season = current_kbo_year() - 1
    expected = {
        "season": season,
        "standings": [{"rank": 1, "teamId": "LG", "teamName": "LG 트윈스"}],
        "updatedAt": f"{season}-03-31T16:30:00+09:00",
    }
    store.save("standings_latest", str(season), expected)

    service = StandingsService(
        crawler=_FailingStandingsCrawler(),
        snapshot_store=store,
    )

    assert service.get_standings(season) == expected


def test_historical_standings_uses_snapshot_before_crawling(tmp_path) -> None:
    store = JsonSnapshotStore(base_dir=str(tmp_path))
    season = current_kbo_year() - 1
    expected = {
        "season": season,
        "standings": [{"rank": 1, "teamId": "LG", "teamName": "LG 트윈스"}],
        "updatedAt": f"{season}-03-31T16:30:00+09:00",
    }
    store.save("standings_latest", str(season), expected)
    crawler = _FreshStandingsCrawler()

    service = StandingsService(
        crawler=crawler,
        snapshot_store=store,
    )

    assert service.get_standings(season) == expected
    assert crawler.calls == 0


def test_current_standings_rejects_fresh_snapshot_on_failure(tmp_path) -> None:
    store = JsonSnapshotStore(base_dir=str(tmp_path))
    season = current_kbo_year()
    expected = {
        "season": season,
        "standings": [{"rank": 1, "teamId": "LG", "teamName": "LG 트윈스"}],
        "updatedAt": f"{season}-03-31T16:30:00+09:00",
    }
    store.save("standings_latest", str(season), expected)

    service = StandingsService(
        crawler=_FailingStandingsCrawler(),
        snapshot_store=store,
    )

    with pytest.raises(RuntimeError):
        service.get_standings(season)


def test_current_standings_reject_old_snapshot_on_failure(tmp_path) -> None:
    store = JsonSnapshotStore(base_dir=str(tmp_path))
    season = current_kbo_year()
    _write_snapshot_record(
        tmp_path,
        "standings_latest",
        str(season),
        {
            "season": season,
            "standings": [{"rank": 1, "teamId": "LG", "teamName": "LG 트윈스"}],
            "updatedAt": f"{season}-03-31T16:30:00+09:00",
        },
    )
    service = StandingsService(
        crawler=_FailingStandingsCrawler(),
        snapshot_store=store,
    )

    with pytest.raises(RuntimeError):
        service.get_standings(season)


def test_historical_standings_rejects_cross_season_snapshot_before_crawling(
    tmp_path,
) -> None:
    store = JsonSnapshotStore(base_dir=str(tmp_path))
    season = current_kbo_year() - 1
    store.save(
        "standings_latest",
        str(season),
        {
            "season": season,
            "standings": [{"rank": 1, "teamId": "LG", "teamName": "LG 트윈스"}],
            "updatedAt": f"{current_kbo_year()}년 04월10일",
        },
    )
    crawler = _FreshStandingsCrawler()
    service = StandingsService(crawler=crawler, snapshot_store=store)

    payload = service.get_standings(season)

    assert crawler.calls == 1
    assert payload["standings"][0]["teamId"] == "KT"


@pytest.mark.parametrize(
    "payload",
    [
        {
            "season": 2025,
            "sourceSeason": 2026,
            "sourceDate": "2026-04-01",
            "updatedAt": "2026-04-01",
            "standings": [{"rank": 1, "teamId": "LG"}],
        },
        {
            "season": 2025,
            "sourceSeason": 2025,
            "sourceDate": "2025-04-01",
            "updatedAt": "2025-04-01",
            "standings": [],
        },
    ],
)
def test_standings_rejects_invalid_crawler_payload_without_cache_or_snapshot(
    tmp_path,
    payload,
) -> None:
    store = JsonSnapshotStore(base_dir=str(tmp_path))
    crawler = _PayloadStandingsCrawler(payload)
    service = StandingsService(crawler=crawler, snapshot_store=store)

    with pytest.raises(ValueError):
        service.get_standings(2025)
    with pytest.raises(ValueError):
        service.get_standings(2025)

    assert crawler.calls == 2
    assert list(tmp_path.rglob("*.json")) == []


def test_standings_daily_snapshot_key_uses_iso_source_date(tmp_path) -> None:
    store = JsonSnapshotStore(base_dir=str(tmp_path))
    season = current_kbo_year() - 1
    crawler = _FreshStandingsCrawler()
    service = StandingsService(crawler=crawler, snapshot_store=store)

    payload = service.get_standings(season)

    record = store.load("standings_daily", f"{season}-{season}-04-01")
    assert record is not None
    assert record["payload"] == payload


def test_historical_player_detail_falls_back_to_snapshot(tmp_path) -> None:
    store = JsonSnapshotStore(base_dir=str(tmp_path))
    season = current_kbo_year() - 1
    expected = {
        "id": "61102",
        "teamId": "LG",
        "season": season,
        "playerType": "hitter",
        "name": "홍길동",
        "recentGames": [],
    }
    store.save("player_detail", f"61102-{season}-auto", expected)

    service = PlayerStatsService(
        crawler=_FailingPlayerCrawler(),
        snapshot_store=store,
    )

    assert service.get_player_detail("61102", season=season) == expected


def test_historical_player_detail_rejects_snapshot_for_another_player_or_season(tmp_path) -> None:
    store = JsonSnapshotStore(base_dir=str(tmp_path))
    season = current_kbo_year() - 1
    store.save(
        "player_detail",
        f"61102-{season}-auto",
        {
            "id": "99999",
            "teamId": "LG",
            "season": season - 1,
            "playerType": "hitter",
            "name": "다른 선수",
            "recentGames": [],
        },
    )

    service = PlayerStatsService(
        crawler=_FailingPlayerCrawler(),
        snapshot_store=store,
    )

    with pytest.raises(RuntimeError, match="player unavailable"):
        service.get_player_detail("61102", season=season)


def test_historical_team_stats_rejects_snapshot_for_another_team_or_season(tmp_path) -> None:
    store = JsonSnapshotStore(base_dir=str(tmp_path))
    season = current_kbo_year() - 1
    store.save(
        "team_stats",
        f"LG-{season}",
        {
            "teamId": "KT",
            "season": season - 1,
            "hitting": {"AVG": "0.382"},
            "pitching": {"ERA": "6.00"},
        },
    )

    service = TeamStatsService(
        crawler=_FailingTeamStatsCrawler(),
        snapshot_store=store,
    )

    with pytest.raises(RuntimeError, match="team stats unavailable"):
        service.get_team_stats("LG", season=season)


def test_current_player_detail_rejects_snapshot_on_failure(tmp_path) -> None:
    store = JsonSnapshotStore(base_dir=str(tmp_path))
    season = current_kbo_year()
    store.save(
        "player_detail",
        f"61102-{season}-auto",
        {
            "id": "61102",
            "teamId": "LG",
            "playerType": "hitter",
            "name": "홍길동",
            "recentGames": [],
        },
    )

    service = PlayerStatsService(
        crawler=_FailingPlayerCrawler(),
        snapshot_store=store,
    )

    with pytest.raises(RuntimeError):
        service.get_player_detail("61102", season=season)


def test_current_season_team_players_crawl_before_snapshot(tmp_path) -> None:
    store = JsonSnapshotStore(base_dir=str(tmp_path))
    season = current_kbo_year()
    stale = {
        "teamId": "KT",
        "season": season,
        "players": [{"id": "79240", "name": "허경민", "position": "내야수"}],
    }
    store.save("team_players", f"KT-{season}", stale)

    service = PlayerStatsService(
        crawler=_FreshPlayerCrawler(),
        snapshot_store=store,
    )

    payload = service.get_team_players("KT", season=season)
    assert payload["players"][0]["name"] == "박성한"


def test_historical_team_players_rejects_snapshot_for_another_team_or_season(tmp_path) -> None:
    store = JsonSnapshotStore(base_dir=str(tmp_path))
    season = current_kbo_year() - 1
    store.save(
        "team_players",
        f"LG-{season}",
        {
            "teamId": "KT",
            "season": season - 1,
            "players": [{"id": "79240", "name": "홍길동", "position": "내야수"}],
        },
    )

    service = PlayerStatsService(
        crawler=_FailingPlayerCrawler(),
        snapshot_store=store,
    )

    with pytest.raises(RuntimeError, match="players unavailable"):
        service.get_team_players("LG", season=season)


def test_current_season_team_players_reject_old_snapshot_on_failure(tmp_path) -> None:
    store = JsonSnapshotStore(base_dir=str(tmp_path))
    season = current_kbo_year()
    _write_snapshot_record(
        tmp_path,
        "team_players",
        f"KT-{season}",
        {
            "teamId": "KT",
            "season": season,
            "players": [{"id": "79240", "name": "허경민", "position": "내야수"}],
        },
    )

    service = PlayerStatsService(
        crawler=_FailingPlayerCrawler(),
        snapshot_store=store,
    )

    try:
        service.get_team_players("KT", season=season)
    except RuntimeError as error:
        assert "players unavailable" in str(error)
    else:
        raise AssertionError("old current-season team player snapshot was used")


def test_current_season_team_players_reject_fresh_snapshot_on_failure(tmp_path) -> None:
    store = JsonSnapshotStore(base_dir=str(tmp_path))
    season = current_kbo_year()
    store.save(
        "team_players",
        f"KT-{season}",
        {
            "teamId": "KT",
            "season": season,
            "players": [{"id": "79240", "name": "허경민", "position": "내야수"}],
        },
    )

    service = PlayerStatsService(
        crawler=_FailingPlayerCrawler(),
        snapshot_store=store,
    )

    with pytest.raises(RuntimeError):
        service.get_team_players("KT", season=season)


def test_current_season_team_stats_crawl_before_snapshot(tmp_path) -> None:
    store = JsonSnapshotStore(base_dir=str(tmp_path))
    season = current_kbo_year()
    stale = {
        "teamId": "KT",
        "season": season,
        "hitting": {"AVG": "0.382"},
        "pitching": {"ERA": "6.00"},
    }
    store.save("team_stats", f"KT-{season}", stale)

    service = TeamStatsService(
        crawler=_FreshTeamStatsCrawler(),
        snapshot_store=store,
    )

    payload = service.get_team_stats("KT", season=season)
    assert payload["hitting"]["AVG"] == "0.279"
    assert payload["pitching"]["ERA"] == "3.88"


def test_current_season_team_stats_reject_old_snapshot_on_failure(tmp_path) -> None:
    store = JsonSnapshotStore(base_dir=str(tmp_path))
    season = current_kbo_year()
    _write_snapshot_record(
        tmp_path,
        "team_stats",
        f"KT-{season}",
        {
            "teamId": "KT",
            "season": season,
            "hitting": {"AVG": "0.382"},
            "pitching": {"ERA": "6.00"},
        },
    )

    service = TeamStatsService(
        crawler=_FailingTeamStatsCrawler(),
        snapshot_store=store,
    )

    try:
        service.get_team_stats("KT", season=season)
    except RuntimeError as error:
        assert "team stats unavailable" in str(error)
    else:
        raise AssertionError("old current-season team stats snapshot was used")


def test_current_season_team_stats_reject_fresh_snapshot_on_failure(tmp_path) -> None:
    store = JsonSnapshotStore(base_dir=str(tmp_path))
    season = current_kbo_year()
    store.save(
        "team_stats",
        f"KT-{season}",
        {
            "teamId": "KT",
            "season": season,
            "hitting": {"AVG": "0.382"},
            "pitching": {"ERA": "6.00"},
        },
    )

    service = TeamStatsService(
        crawler=_FailingTeamStatsCrawler(),
        snapshot_store=store,
    )

    with pytest.raises(RuntimeError):
        service.get_team_stats("KT", season=season)


def test_records_overview_falls_back_to_snapshot(tmp_path) -> None:
    store = JsonSnapshotStore(base_dir=str(tmp_path))
    season = current_kbo_year() - 1
    snapshot = {
        "season": season,
        "leaders": {
            "avg": [
                {
                    "rank": 1,
                    "playerId": "",
                    "playerType": "hitter",
                    "metricKey": "AVG",
                    "name": "Snapshot Leader",
                    "teamId": "LG",
                    "value": ".345",
                }
            ],
            "hr": [],
            "ops": [],
            "era": [],
            "opsPlus": [],
            "wins": [],
            "saves": [],
            "strikeouts": [],
        },
        "featured": {},
    }
    store.save("records_overview", str(season), snapshot)

    service = RecordsOverviewService(
        crawler=_FailingRecordsOverviewCrawler(),
        snapshot_store=store,
    )

    payload = service.get_overview(season)

    assert payload["leaders"]["avg"][0]["name"] == "Snapshot Leader"
    assert payload["featured"]["todayHitter"]["name"] == "Snapshot Leader"


def _write_snapshot_record(tmp_path, namespace: str, key: str, payload: dict) -> None:
    path = tmp_path / namespace / f"{key}.json"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(
            {
                "savedAt": "2000-01-01T00:00:00+00:00",
                "payload": payload,
            },
            ensure_ascii=False,
        ),
        encoding="utf-8",
    )
