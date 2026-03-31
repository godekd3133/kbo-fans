from __future__ import annotations

from typing import Any, Optional

from kbo_fans_backend.crawlers.boxscore import BoxscoreCrawler
from kbo_fans_backend.crawlers.lineup import LineupCrawler
from kbo_fans_backend.storage import JsonSnapshotStore


class LineupService:
    def __init__(
        self,
        lineup_crawler: Optional[LineupCrawler] = None,
        boxscore_crawler: Optional[BoxscoreCrawler] = None,
        snapshot_store: Optional[JsonSnapshotStore] = None,
    ) -> None:
        self.lineup_crawler = lineup_crawler or LineupCrawler()
        self.boxscore_crawler = boxscore_crawler or BoxscoreCrawler()
        self.snapshot_store = snapshot_store or JsonSnapshotStore()

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

        self.snapshot_store.save("lineup", game_id, lineup)
        return lineup
