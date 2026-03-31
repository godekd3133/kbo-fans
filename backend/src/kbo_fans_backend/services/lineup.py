from __future__ import annotations

from typing import Any, Optional

from kbo_fans_backend.crawlers.boxscore import BoxscoreCrawler
from kbo_fans_backend.crawlers.lineup import LineupCrawler
from kbo_fans_backend.services.push import PushService
from kbo_fans_backend.storage import JsonSnapshotStore


class LineupService:
    def __init__(
        self,
        lineup_crawler: Optional[LineupCrawler] = None,
        boxscore_crawler: Optional[BoxscoreCrawler] = None,
        snapshot_store: Optional[JsonSnapshotStore] = None,
        push_service: Optional[PushService] = None,
    ) -> None:
        self.lineup_crawler = lineup_crawler or LineupCrawler()
        self.boxscore_crawler = boxscore_crawler or BoxscoreCrawler()
        self.snapshot_store = snapshot_store or JsonSnapshotStore()
        self.push_service = push_service or PushService()

    def get_lineup(self, game_id: str) -> dict[str, Any]:
        snapshot = self.snapshot_store.load_payload("lineup", game_id)
        try:
            lineup = self.lineup_crawler.get_lineup(game_id)
            boxscore = self.boxscore_crawler.get_boxscore(game_id)
        except Exception:
            if snapshot is not None:
                return snapshot
            raise

        for side in ("away", "home"):
            pitchers = boxscore[side]["pitchers"]
            starter = pitchers[0] if pitchers else None
            lineup[side]["starter"] = {
                "name": starter["name"] if starter else None,
                "hand": None,
            }

        if self._should_notify_lineup_opened(snapshot, lineup):
            try:
                self.push_service.send_lineup_opened(
                    game_id=game_id,
                    away_team_id=lineup["away"]["teamId"],
                    away_team_name=lineup["away"].get("teamName") or lineup["away"]["teamId"],
                    home_team_id=lineup["home"]["teamId"],
                    home_team_name=lineup["home"].get("teamName") or lineup["home"]["teamId"],
                )
            except Exception:
                pass

        self.snapshot_store.save("lineup", game_id, lineup)
        return lineup

    @staticmethod
    def _should_notify_lineup_opened(
        previous: Optional[dict[str, Any]],
        current: dict[str, Any],
    ) -> bool:
        prev_ready = bool(previous and previous.get("away", {}).get("lineup") and previous.get("home", {}).get("lineup"))
        curr_ready = bool(current.get("away", {}).get("lineup") and current.get("home", {}).get("lineup"))
        return (not prev_ready) and curr_ready
