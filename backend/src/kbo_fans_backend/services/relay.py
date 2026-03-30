from __future__ import annotations

from typing import Any, Optional

from kbo_fans_backend.services.scoreboard import ScoreboardService


class RelayService:
    def __init__(
        self,
        scoreboard_service: Optional[ScoreboardService] = None,
    ) -> None:
        self.scoreboard_service = scoreboard_service or ScoreboardService()

    def get_relay(self, game_id: str, after: Optional[int] = None) -> dict[str, Any]:
        game = self.scoreboard_service.get_game(game_id)
        if game is None:
            return {
                "gameId": game_id,
                "currentAtBat": None,
                "relayItems": [],
            }

        relay_items = self._build_summary_items(game)
        if after is not None:
            relay_items = [item for item in relay_items if item["seqNo"] > after]

        return {
            "gameId": game_id,
            "currentAtBat": self._build_current_at_bat(game),
            "relayItems": relay_items,
        }

    def _build_summary_items(self, game: dict[str, Any]) -> list[dict[str, Any]]:
        away = game.get("away", {})
        home = game.get("home", {})
        away_scores = away.get("scores", [])
        home_scores = home.get("scores", [])
        away_name = away.get("shortName") or away.get("teamName") or "원정팀"
        home_name = home.get("shortName") or home.get("teamName") or "홈팀"

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
                    "text": f"경기종료 {away_name} {away.get('score', 0)} : {home.get('score', 0)} {home_name}",
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
