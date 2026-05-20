import json
from datetime import datetime, timezone

import pytest

from kbo_fans_backend.services.player_stats import PlayerStatsService
from kbo_fans_backend.services.records_overview import RecordsOverviewService
from kbo_fans_backend.services.scoreboard import ScoreboardService
from kbo_fans_backend.services.standings import StandingsService
from kbo_fans_backend.services.team_stats import TeamStatsService
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


def test_standings_falls_back_to_snapshot(tmp_path) -> None:
    store = JsonSnapshotStore(base_dir=str(tmp_path))
    season = datetime.now(timezone.utc).year
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


def test_current_standings_reject_old_snapshot_on_failure(tmp_path) -> None:
    store = JsonSnapshotStore(base_dir=str(tmp_path))
    season = datetime.now(timezone.utc).year
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


def test_current_season_team_players_crawl_before_snapshot(tmp_path) -> None:
    store = JsonSnapshotStore(base_dir=str(tmp_path))
    season = datetime.now(timezone.utc).year
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


def test_current_season_team_players_reject_old_snapshot_on_failure(tmp_path) -> None:
    store = JsonSnapshotStore(base_dir=str(tmp_path))
    season = datetime.now(timezone.utc).year
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


def test_current_season_team_stats_crawl_before_snapshot(tmp_path) -> None:
    store = JsonSnapshotStore(base_dir=str(tmp_path))
    season = datetime.now(timezone.utc).year
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
    season = datetime.now(timezone.utc).year
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


def test_records_overview_falls_back_to_snapshot(tmp_path) -> None:
    store = JsonSnapshotStore(base_dir=str(tmp_path))
    expected = {
        "season": 2026,
        "leaders": {"avg": [], "hr": [], "ops": [], "era": [], "opsPlus": []},
        "featured": {
            "todayHitter": {"label": "시즌 타율 리더"},
            "todayPitcher": {"label": "시즌 ERA 리더"},
            "monthHitter": {"label": "시즌 홈런왕"},
            "monthPitcher": {"label": "시즌 OPS 리더"},
        },
    }
    store.save("records_overview", "2026", expected)

    service = RecordsOverviewService(
        crawler=_FailingRecordsOverviewCrawler(),
        snapshot_store=store,
    )

    assert service.get_overview(2026) == expected


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
