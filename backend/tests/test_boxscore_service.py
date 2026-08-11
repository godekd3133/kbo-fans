from copy import deepcopy
from datetime import timedelta

import pytest

from kbo_fans_backend.schemas.boxscore import official_unavailable_boxscore
from kbo_fans_backend.services.boxscore import BoxscoreService
from kbo_fans_backend.storage import JsonSnapshotStore
from kbo_fans_backend.utils.kbo_time import current_kbo_date


class _StubBoxscoreCrawler:
    def __init__(self, payloads):
        self.payloads = payloads
        self.calls = []

    def get_boxscore(self, game_id: str):
        self.calls.append(game_id)
        payload = self.payloads[game_id]
        if isinstance(payload, Exception):
            raise payload
        return deepcopy(payload)


class _StubScheduleService:
    def __init__(self, statuses):
        self.statuses = statuses

    def get_schedule_game(self, game_id: str):
        status = self.statuses.get(game_id)
        if status is None:
            return None
        return self._game(game_id, status)

    def get_month_schedule(self, month: str):
        days = []
        for game_id, status in self.statuses.items():
            date = _date_from_game_id(game_id)
            if date[:7] != month:
                continue
            days.append(
                {
                    "date": date,
                    "games": [self._game(game_id, status)],
                }
            )
        return {"month": month, "days": days}

    @staticmethod
    def _game(game_id: str, status: str):
        return {
            "gameId": game_id,
            "awayId": game_id[8:10],
            "homeId": game_id[10:12],
            "status": status,
        }


class _StubPlayerStatsService:
    def get_team_players(self, team_id: str, season: int):
        players_by_team = {
            "KT": [
                {
                    "id": "50054",
                    "name": "A",
                    "imageUrl": f"https://img.test/{season}/50054.jpg",
                }
            ],
            "LG": [
                {
                    "id": "60123",
                    "name": "Q",
                    "imageUrl": f"https://img.test/{season}/60123.jpg",
                }
            ],
        }
        return {"players": players_by_team.get(team_id, [])}


class _EmptyPlayerStatsService:
    def get_team_players(self, team_id: str, season: int):
        return {"teamId": team_id, "season": season, "players": []}


def test_boxscore_service_enriches_and_snapshots_verified_final_payload(tmp_path) -> None:
    game_id = "20260329KTLG0"
    crawler = _StubBoxscoreCrawler({game_id: _official_payload(game_id)})
    snapshot_store = JsonSnapshotStore(base_dir=str(tmp_path))
    service = BoxscoreService(
        crawler=crawler,
        schedule_service=_StubScheduleService({game_id: "FINAL"}),
        player_stats_service=_StubPlayerStatsService(),
        snapshot_store=snapshot_store,
    )

    payload = service.get_boxscore(game_id)

    assert payload["availability"] == "official"
    assert payload["away"]["batters"][0]["playerId"] == "50054"
    assert payload["away"]["batters"][0]["imageUrl"].endswith("/2026/50054.jpg")
    assert payload["home"]["pitchers"][0]["playerId"] == "60123"
    assert snapshot_store.load_payload("boxscore", game_id) == payload


def test_boxscore_service_uses_adjacent_official_only_for_historical_final(
    tmp_path,
) -> None:
    game_id = "20260330KTLG0"
    adjacent_game_id = "20260329KTLG0"
    crawler = _StubBoxscoreCrawler(
        {
            game_id: _unavailable_payload(game_id),
            adjacent_game_id: _official_payload(adjacent_game_id),
        }
    )
    snapshot_store = JsonSnapshotStore(base_dir=str(tmp_path))
    service = BoxscoreService(
        crawler=crawler,
        schedule_service=_StubScheduleService({game_id: "FINAL", adjacent_game_id: "FINAL"}),
        player_stats_service=_EmptyPlayerStatsService(),
        snapshot_store=snapshot_store,
    )

    payload = service.get_boxscore(game_id)

    assert crawler.calls == [game_id, adjacent_game_id]
    assert payload["gameId"] == game_id
    assert payload["sourceGameId"] == adjacent_game_id
    assert payload["source"] == "adjacent_official"
    assert payload["availability"] == "official"
    assert snapshot_store.load_payload("boxscore", game_id)["sourceGameId"] == (adjacent_game_id)


def test_current_live_ignores_official_snapshot_and_rejects_partial_crawler_payload(
    tmp_path,
) -> None:
    today = current_kbo_date()
    game_id = f"{today:%Y%m%d}SKWO0"
    snapshot_store = JsonSnapshotStore(base_dir=str(tmp_path))
    snapshot_store.save("boxscore", game_id, _official_payload(game_id))
    crawler = _StubBoxscoreCrawler({game_id: _partial_official_payload(game_id)})
    service = BoxscoreService(
        crawler=crawler,
        schedule_service=_StubScheduleService({game_id: "LIVE"}),
        player_stats_service=_EmptyPlayerStatsService(),
        snapshot_store=snapshot_store,
    )

    payload = service.get_boxscore(game_id)

    assert crawler.calls == [game_id]
    assert payload["availability"] == "official_unavailable"
    assert payload["officialAvailable"] is False
    assert payload["unavailableReason"] == "official_partial"
    assert payload["away"]["batters"] == []
    assert snapshot_store.load_payload("boxscore", game_id)["officialAvailable"] is True


def test_past_suspended_game_ignores_snapshot_and_adjacent_final(tmp_path) -> None:
    target_date = current_kbo_date() - timedelta(days=1)
    adjacent_date = target_date - timedelta(days=1)
    game_id = f"{target_date:%Y%m%d}SKWO0"
    adjacent_game_id = f"{adjacent_date:%Y%m%d}SKWO0"
    snapshot_store = JsonSnapshotStore(base_dir=str(tmp_path))
    snapshot_store.save("boxscore", game_id, _official_payload(game_id))
    crawler = _StubBoxscoreCrawler(
        {
            game_id: _unavailable_payload(game_id),
            adjacent_game_id: _official_payload(adjacent_game_id),
        }
    )
    service = BoxscoreService(
        crawler=crawler,
        schedule_service=_StubScheduleService({game_id: "SUSPENDED", adjacent_game_id: "FINAL"}),
        player_stats_service=_EmptyPlayerStatsService(),
        snapshot_store=snapshot_store,
    )

    payload = service.get_boxscore(game_id)

    assert crawler.calls == [game_id]
    assert payload["availability"] == "official_unavailable"
    assert payload["away"]["batters"] == []


def test_historical_final_uses_only_verified_snapshot(tmp_path) -> None:
    game_id = "20260330KTLG0"
    snapshot_store = JsonSnapshotStore(base_dir=str(tmp_path))
    expected = _official_payload(game_id)
    snapshot_store.save("boxscore", game_id, expected)
    crawler = _StubBoxscoreCrawler(
        {game_id: AssertionError("verified final snapshot should be used")}
    )
    service = BoxscoreService(
        crawler=crawler,
        schedule_service=_StubScheduleService({game_id: "FINAL"}),
        player_stats_service=_EmptyPlayerStatsService(),
        snapshot_store=snapshot_store,
    )

    payload = service.get_boxscore(game_id)

    assert crawler.calls == []
    assert payload == expected


def test_historical_verified_snapshot_survives_schedule_lookup_outage(tmp_path) -> None:
    game_id = "20260330KTLG0"
    snapshot_store = JsonSnapshotStore(base_dir=str(tmp_path))
    expected = _official_payload(game_id)
    snapshot_store.save("boxscore", game_id, expected)
    crawler = _StubBoxscoreCrawler(
        {game_id: AssertionError("verified historical snapshot should be used")}
    )
    service = BoxscoreService(
        crawler=crawler,
        schedule_service=_StubScheduleService({}),
        player_stats_service=_EmptyPlayerStatsService(),
        snapshot_store=snapshot_store,
    )

    payload = service.get_boxscore(game_id)

    assert crawler.calls == []
    assert payload == expected


def test_historical_final_rejects_partial_snapshot_before_fresh_crawl(tmp_path) -> None:
    game_id = "20260330KTLG0"
    snapshot_store = JsonSnapshotStore(base_dir=str(tmp_path))
    snapshot_store.save("boxscore", game_id, _partial_official_payload(game_id))
    crawler = _StubBoxscoreCrawler({game_id: _official_payload(game_id, batter="fresh")})
    service = BoxscoreService(
        crawler=crawler,
        schedule_service=_StubScheduleService({game_id: "FINAL"}),
        player_stats_service=_EmptyPlayerStatsService(),
        snapshot_store=snapshot_store,
    )

    payload = service.get_boxscore(game_id)

    assert crawler.calls == [game_id]
    assert payload["away"]["batters"][0]["name"] == "fresh"
    assert payload["availability"] == "official"


def test_historical_final_rejects_snapshot_without_source_provenance(tmp_path) -> None:
    game_id = "20260330KTLG0"
    snapshot = _official_payload(game_id, batter="unverified")
    snapshot.pop("source")
    snapshot_store = JsonSnapshotStore(base_dir=str(tmp_path))
    snapshot_store.save("boxscore", game_id, snapshot)
    crawler = _StubBoxscoreCrawler({game_id: _official_payload(game_id, batter="fresh")})
    service = BoxscoreService(
        crawler=crawler,
        schedule_service=_StubScheduleService({game_id: "FINAL"}),
        player_stats_service=_EmptyPlayerStatsService(),
        snapshot_store=snapshot_store,
    )

    payload = service.get_boxscore(game_id)

    assert crawler.calls == [game_id]
    assert payload["away"]["batters"][0]["name"] == "fresh"
    assert payload["source"] == "official_endpoint"


def test_historical_final_rejects_unverified_adjacent_snapshot_provenance(
    tmp_path,
) -> None:
    game_id = "20260330KTLG0"
    source_game_id = "20260329KTLG0"
    snapshot = {
        **_official_payload(game_id, batter="borrowed"),
        "source": "adjacent_official",
        "sourceGameId": source_game_id,
    }
    snapshot_store = JsonSnapshotStore(base_dir=str(tmp_path))
    snapshot_store.save("boxscore", game_id, snapshot)
    crawler = _StubBoxscoreCrawler({game_id: _official_payload(game_id, batter="fresh")})
    service = BoxscoreService(
        crawler=crawler,
        schedule_service=_StubScheduleService({game_id: "FINAL", source_game_id: "SUSPENDED"}),
        player_stats_service=_EmptyPlayerStatsService(),
        snapshot_store=snapshot_store,
    )

    payload = service.get_boxscore(game_id)

    assert crawler.calls == [game_id]
    assert payload["away"]["batters"][0]["name"] == "fresh"
    assert "sourceGameId" not in payload


def test_current_live_failure_does_not_fall_back_to_snapshot(tmp_path) -> None:
    today = current_kbo_date()
    game_id = f"{today:%Y%m%d}KTLG0"
    snapshot_store = JsonSnapshotStore(base_dir=str(tmp_path))
    snapshot_store.save("boxscore", game_id, _official_payload(game_id))
    crawler = _StubBoxscoreCrawler({game_id: RuntimeError("boxscore unavailable")})
    service = BoxscoreService(
        crawler=crawler,
        schedule_service=_StubScheduleService({game_id: "LIVE"}),
        snapshot_store=snapshot_store,
    )

    with pytest.raises(RuntimeError, match="boxscore unavailable"):
        service.get_boxscore(game_id)


def test_live_context_stays_explicit_and_is_not_snapshotted(tmp_path) -> None:
    today = current_kbo_date()
    game_id = f"{today:%Y%m%d}OBLG0"
    snapshot_store = JsonSnapshotStore(base_dir=str(tmp_path))
    crawler = _StubBoxscoreCrawler({game_id: _live_context_payload(game_id)})
    service = BoxscoreService(
        crawler=crawler,
        schedule_service=_StubScheduleService({game_id: "LIVE"}),
        player_stats_service=_EmptyPlayerStatsService(),
        snapshot_store=snapshot_store,
    )

    payload = service.get_boxscore(game_id)

    assert payload["availability"] == "live_context"
    assert payload["officialAvailable"] is False
    assert payload["liveContextAvailable"] is True
    assert snapshot_store.load_payload("boxscore", game_id) is None


def test_scheduled_game_downgrades_even_complete_official_endpoint_payload(
    tmp_path,
) -> None:
    game_id = "29990101KTLG0"
    crawler = _StubBoxscoreCrawler({game_id: _official_payload(game_id)})
    service = BoxscoreService(
        crawler=crawler,
        schedule_service=_StubScheduleService({game_id: "SCHEDULED"}),
        snapshot_store=JsonSnapshotStore(base_dir=str(tmp_path)),
    )

    payload = service.get_boxscore(game_id)

    assert payload["availability"] == "official_unavailable"
    assert payload["unavailableReason"] == "game_status_scheduled"
    assert payload["away"]["batters"] == []


def _official_payload(game_id: str, *, batter: str = "A"):
    return {
        "gameId": game_id,
        "availability": "official",
        "officialAvailable": True,
        "liveContextAvailable": False,
        "source": "official_endpoint",
        "away": {
            "teamId": game_id[8:10],
            "batters": [{"name": batter, "atBats": 4, "hits": 1}],
            "pitchers": [{"name": "P", "innings": "1.0"}],
        },
        "home": {
            "teamId": game_id[10:12],
            "batters": [{"name": "B", "atBats": 3, "hits": 1}],
            "pitchers": [{"name": "Q", "innings": "1.0"}],
        },
    }


def _partial_official_payload(game_id: str):
    return {
        "gameId": game_id,
        "availability": "official",
        "officialAvailable": True,
        "liveContextAvailable": False,
        "source": "official_endpoint",
        "away": {
            "teamId": game_id[8:10],
            "batters": [],
            "pitchers": [{"name": "P", "innings": "2.0"}],
        },
        "home": {
            "teamId": game_id[10:12],
            "batters": [],
            "pitchers": [{"name": "Q", "innings": "2.0"}],
        },
    }


def _unavailable_payload(game_id: str):
    return official_unavailable_boxscore(
        game_id,
        game_id[8:10],
        game_id[10:12],
        reason="official_not_available",
    )


def _live_context_payload(game_id: str):
    return {
        "gameId": game_id,
        "availability": "live_context",
        "officialAvailable": False,
        "liveContextAvailable": True,
        "source": "live_context",
        "unavailableReason": "official_not_available",
        "away": {
            "teamId": game_id[8:10],
            "batters": [
                {
                    "name": "양석환",
                    "liveContext": True,
                    "contextLabel": "3회초 현재 타자",
                }
            ],
            "pitchers": [],
        },
        "home": {
            "teamId": game_id[10:12],
            "batters": [],
            "pitchers": [
                {
                    "name": "임찬규",
                    "liveContext": True,
                    "decision": "LIVE",
                    "contextLabel": "3회초 현재 투수",
                }
            ],
        },
    }


def _date_from_game_id(game_id: str) -> str:
    return f"{game_id[:4]}-{game_id[4:6]}-{game_id[6:8]}"
