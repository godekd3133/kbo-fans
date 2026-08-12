from __future__ import annotations

from datetime import date as date_type
from typing import Any, Optional

from kbo_fans_backend.crawlers.relay import RelayCrawler
from kbo_fans_backend.services.push import KBO_TEAM_NAMES, KBO_TEAM_SHORT_NAMES
from kbo_fans_backend.services.scoreboard import ScoreboardService
from kbo_fans_backend.storage import JsonSnapshotStore
from kbo_fans_backend.utils.kbo_time import current_kbo_date


class RelayService:
    def __init__(
        self,
        relay_crawler: Optional[RelayCrawler] = None,
        scoreboard_service: Optional[ScoreboardService] = None,
        snapshot_store: Optional[JsonSnapshotStore] = None,
    ) -> None:
        self.relay_crawler = relay_crawler or RelayCrawler()
        self.scoreboard_service = scoreboard_service or ScoreboardService()
        self.snapshot_store = snapshot_store or JsonSnapshotStore()

    def get_relay(
        self,
        game_id: str,
        after: Optional[int] = None,
        force_refresh: bool = False,
    ) -> dict[str, Any]:
        game = self.scoreboard_service.get_game(
            game_id,
            force_refresh=force_refresh,
        )
        snapshot = self.snapshot_store.load_payload("relay", game_id)
        game_status = game.get("status") if game is not None else None

        if (
            self._is_past_game_id(game_id)
            and game_status == "FINAL"
            and self._has_detailed_snapshot(game_id, snapshot)
        ):
            snapshot = self._without_current_at_bat(snapshot)
            if after is not None:
                snapshot = {
                    **snapshot,
                    "relayItems": [
                        item for item in snapshot.get("relayItems", []) if item["seqNo"] > after
                    ],
                }
            return snapshot

        if game_status in {"SCHEDULED", "CANCELLED", "SUSPENDED"}:
            relay_items = self._build_summary_items(game)
            if after is not None:
                relay_items = [item for item in relay_items if item["seqNo"] > after]
            payload = {
                "gameId": game_id,
                "currentAtBat": None,
                "relayItems": relay_items,
            }
            return payload

        try:
            relay = self.relay_crawler.get_relay(game_id)
            relay_items = relay["relayItems"]
            current_at_bat = relay.get("currentAtBat")

            if game is not None:
                if game_status != "LIVE":
                    current_at_bat = None
                elif current_at_bat is None:
                    current_at_bat = self._build_current_at_bat(game)

            if after is not None:
                relay_items = [item for item in relay_items if item["seqNo"] > after]
            payload = {
                "gameId": game_id,
                "currentAtBat": current_at_bat,
                "relayItems": relay_items,
            }
            if game_status == "FINAL":
                self.snapshot_store.save("relay", game_id, payload)
            return payload
        except Exception:
            if (
                self._is_past_game_id(game_id)
                and self._has_detailed_snapshot(game_id, snapshot)
            ):
                snapshot = self._without_current_at_bat(snapshot)
                if after is not None:
                    snapshot = {
                        **snapshot,
                        "relayItems": [
                            item for item in snapshot.get("relayItems", []) if item["seqNo"] > after
                        ],
                    }
                return snapshot
            if game_status == "LIVE" or game is None:
                raise

        relay_items = self._build_summary_items(game)
        if after is not None:
            relay_items = [item for item in relay_items if item["seqNo"] > after]

        payload = {
            "gameId": game_id,
            "currentAtBat": self._build_current_at_bat(game),
            "relayItems": relay_items,
        }
        return payload

    def _build_summary_items(self, game: dict[str, Any]) -> list[dict[str, Any]]:
        away = game.get("away", {})
        home = game.get("home", {})
        away_scores = away.get("scores", [])
        home_scores = home.get("scores", [])
        away_name = _team_short_display_name(away, "원정팀")
        home_name = _team_short_display_name(home, "홈팀")

        items = []
        seq_no = 1

        innings = max(len(away_scores), len(home_scores))
        for inning_index in range(innings):
            inning = inning_index + 1
            away_runs = self._as_int(away_scores, inning_index)
            home_runs = self._as_int(home_scores, inning_index)

            if away_runs and away_runs > 0:
                items.append(
                    {
                        "seqNo": seq_no,
                        "inning": inning,
                        "half": "top",
                        "event": "RUNS",
                        "isScoring": True,
                        "text": f"{inning}회초 {away_name} {away_runs}득점",
                        "pitchSequence": None,
                    }
                )
                seq_no += 1

            if home_runs and home_runs > 0:
                items.append(
                    {
                        "seqNo": seq_no,
                        "inning": inning,
                        "half": "bottom",
                        "event": "RUNS",
                        "isScoring": True,
                        "text": f"{inning}회말 {home_name} {home_runs}득점",
                        "pitchSequence": None,
                    }
                )
                seq_no += 1

        if game.get("status") == "FINAL":
            items.append(
                {
                    "seqNo": seq_no,
                    "inning": 999,
                    "half": "bottom",
                    "event": "GAME_END",
                    "isScoring": False,
                    "text": (
                        f"경기종료 {away_name} {away.get('score', 0)} : "
                        f"{home.get('score', 0)} {home_name}"
                    ),
                    "pitchSequence": None,
                }
            )

        return items

    def _build_current_at_bat(self, game: dict[str, Any]) -> Optional[dict[str, Any]]:
        if game.get("status") != "LIVE":
            return None

        current = game.get("current")
        if not current:
            return None

        return {
            "batter": {
                "name": current.get("batterName") or "",
                "number": 0,
                "hand": "",
            },
            "pitcher": {
                "name": current.get("pitcherName") or "",
                "number": 0,
                "hand": "",
                "pitchCount": 0,
            },
            "ballCount": {
                "balls": current.get("balls") or 0,
                "strikes": current.get("strikes") or 0,
                "outs": current.get("outs") or 0,
            },
        }

    @staticmethod
    def _as_int(scores: list[Any], index: int) -> Optional[int]:
        if index >= len(scores):
            return None
        value = scores[index]
        if value in (None, "", "-"):
            return None
        return int(value)

    @staticmethod
    def _is_past_game_id(game_id: str) -> bool:
        try:
            game_date = date_type.fromisoformat(
                f"{game_id[:4]}-{game_id[4:6]}-{game_id[6:8]}"
            )
        except (TypeError, ValueError):
            return False
        return game_date < current_kbo_date()

    @staticmethod
    def _has_detailed_snapshot(game_id: str, snapshot: Any) -> bool:
        return (
            isinstance(snapshot, dict)
            and snapshot.get("gameId") == game_id
            and isinstance(snapshot.get("relayItems"), list)
            and RelayService._has_detailed_items(snapshot["relayItems"])
        )

    @staticmethod
    def _has_detailed_items(items: list[dict[str, Any]]) -> bool:
        for item in items:
            if not isinstance(item, dict):
                return False
            event = item.get("event")
            text = item.get("text") or ""
            if event not in {"RUNS", "GAME_END", "INNING_CHANGE"}:
                return True
            if ":" in text or item.get("pitchSequence"):
                return True
        return False

    @staticmethod
    def _without_current_at_bat(payload: dict[str, Any]) -> dict[str, Any]:
        if payload.get("currentAtBat") is None:
            return payload
        return {**payload, "currentAtBat": None}


def _team_short_display_name(team: dict[str, Any], fallback: str) -> str:
    team_id = str(team.get("teamId") or "").strip()
    if team_id in KBO_TEAM_SHORT_NAMES:
        return KBO_TEAM_SHORT_NAMES[team_id]

    short_name = str(team.get("shortName") or "").strip()
    if short_name in KBO_TEAM_SHORT_NAMES:
        return KBO_TEAM_SHORT_NAMES[short_name]

    team_name = str(team.get("teamName") or team.get("name") or "").strip()
    for known_team_id, known_team_name in KBO_TEAM_NAMES.items():
        normalized_name = team_name.replace(" ", "")
        normalized_known_name = known_team_name.replace(" ", "")
        if team_name == known_team_name or normalized_name == normalized_known_name:
            return KBO_TEAM_SHORT_NAMES[known_team_id]

    return short_name or team_name or team_id or fallback
